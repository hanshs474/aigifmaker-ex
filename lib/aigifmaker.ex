defmodule Aigifmaker do
  @moduledoc """
  Official Elixir SDK for [AI GIF Maker](https://aigifmaker.ai): turn text into
  animated GIFs.

      {:ok, url} = Aigifmaker.generate("a corgi in sunglasses dancing on a beach")
      {:ok, left} = Aigifmaker.credits()

  Pass `api_key:` or set `AIGIFMAKER_API_KEY`; create a key at
  https://aigifmaker.ai/settings/apikeys. Each GIF costs 1 credit on your
  AI GIF Maker account, the same as on the website.

  Failures are `{:error, reason, message}` where `reason` is `:auth`, `:quota`,
  `:rejected`, `:failed`, `:timeout` or `:other`.

  Options for every call: `:api_key`, `:base_url` (`"https://aigifmaker.ai"`),
  `:timeout` (milliseconds `generate/2` and `wait/2` keep polling, 15 minutes),
  `:poll_ms` (3000).

  Uses only `:httpc` from OTP and the standard `JSON` module; no dependencies.
  """

  @base "https://aigifmaker.ai"
  @keys_url "https://aigifmaker.ai/settings/apikeys"
  @pricing_url "https://aigifmaker.ai/pricing"

  @type reason :: :auth | :quota | :rejected | :failed | :timeout | :other
  @type error :: {:error, reason(), String.t()}

  @doc "Generates one animated GIF and returns its URL."
  @spec generate(String.t(), keyword()) :: {:ok, String.t()} | error()
  def generate(prompt, opts \\ []) do
    with {:ok, id} <- submit(prompt, opts), do: wait(id, opts)
  end

  @doc "Starts one GIF and returns its task id without waiting."
  @spec submit(String.t(), keyword()) :: {:ok, String.t()} | error()
  def submit(prompt, opts \\ []) do
    if not is_binary(prompt) or String.trim(prompt) == "" do
      {:error, :other, "aigifmaker: prompt is required"}
    else
      body = %{
        "provider" => "openlux",
        "mediaType" => "image",
        "model" => "gif-maker-v1",
        "scene" => "text-to-image",
        "prompt" => prompt,
        "options" => %{"output_format" => "gif"}
      }

      case "/api/ai/generate" |> call(body, opts) |> public() do
        {:ok, %{"id" => id}} when is_binary(id) and id != "" -> {:ok, id}
        {:ok, %{"id" => id}} when is_integer(id) -> {:ok, Integer.to_string(id)}
        {:ok, _} -> {:error, :other, "aigifmaker: the service returned no task id"}
        err -> err
      end
    end
  end

  @doc """
  Returns the task record: a map with `"id"`, `"status"` (`"pending"`,
  `"processing"`, `"success"` or `"failed"`), `"images"` (the GIF URL first,
  once it succeeds) and, while an account without purchased credits waits its
  turn, `"queued" => true`.
  """
  @spec status(String.t(), keyword()) :: {:ok, map()} | error()
  def status(task_id, opts \\ []), do: task_id |> query(opts) |> public()

  defp query(task_id, opts), do: call("/api/ai/query", %{"taskId" => task_id}, opts)

  # A dropped connection is :network inside the poll loop (retry), :other outside it.
  defp public({:error, :network, msg}), do: {:error, :other, msg}
  defp public(other), do: other

  @doc "Remaining credits on the account. Free to call."
  @spec credits(keyword()) :: {:ok, integer()} | error()
  def credits(opts \\ []) do
    case "/api/user/get-user-credits" |> call(%{}, opts) |> public() do
      {:ok, %{"remainingCredits" => n}} when is_integer(n) -> {:ok, n}
      {:ok, _} -> {:ok, 0}
      err -> err
    end
  end

  @doc "Polls a task every 3 seconds until it finishes and returns the GIF URL."
  @spec wait(String.t(), keyword()) :: {:ok, String.t()} | error()
  def wait(task_id, opts \\ []) do
    limit = opts[:timeout] || 900_000
    deadline = System.monotonic_time(:millisecond) + limit
    poll(task_id, opts[:poll_ms] || 3_000, deadline, limit, opts)
  end

  defp poll(id, every, deadline, limit, opts) do
    case query(id, opts) do
      {:ok, %{"status" => "success", "images" => [url | _]}} when is_binary(url) ->
        {:ok, url}

      {:ok, %{"status" => s} = d} when s in ["failed", "canceled"] ->
        msg = d["errorMessage"] || "the GIF #{s}"
        {:error, if(d["failureKind"] == "moderation", do: :rejected, else: :failed), msg}

      {:error, reason, _} = err when reason != :network ->
        err

      # pending, processing (queued or not), or a dropped poll
      _ ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :timeout,
           "aigifmaker: still running after #{div(limit, 1000)}s; task #{id} may finish later in your AI GIF Maker history"}
        else
          Process.sleep(every)
          poll(id, every, deadline, limit, opts)
        end
    end
  end

  @doc """
  Turns a response envelope into `{:ok, data}` or the error that says what to
  do next. Every response is HTTP 200; the JSON `code` tells success from refusal.
  """
  @spec unwrap(integer(), term()) :: {:ok, map()} | error()
  def unwrap(http_status, env) do
    env = if is_map(env), do: env, else: %{}
    data = if is_map(env["data"]), do: env["data"], else: %{}

    case env["code"] do
      0 ->
        if data["wall"] == true,
          do:
            {:error, :auth,
             "aigifmaker: an API key is required; create one at #{@keys_url} and set AIGIFMAKER_API_KEY"},
          else: {:ok, data}

      code ->
        msg = to_string(env["message"] || env["error"] || "HTTP #{http_status}")
        low = String.downcase(msg)

        cond do
          String.contains?(low, ["invalid api key", "no auth"]) or http_status == 401 ->
            {:error, :auth, msg}

          String.contains?(low, "insufficient credits") ->
            {:error, :quota, "#{msg}. Top up at #{@pricing_url}"}

          is_integer(code) and code != -1 ->
            {:error, :rejected, msg}

          true ->
            {:error, :other, msg}
        end
    end
  end

  defp call(path, body, opts) do
    key = opts[:api_key] || System.get_env("AIGIFMAKER_API_KEY")
    key = if is_binary(key) and String.trim(key) != "", do: String.trim(key), else: nil
    transport = opts[:transport] || (&http/3)
    base = String.trim_trailing(opts[:base_url] || @base, "/")

    case transport.(base <> path, body, key) do
      {:ok, status, env} -> unwrap(status, env)
      {:error, why} -> {:error, :network, "aigifmaker: " <> inspect(why)}
    end
  end

  @doc false
  def http(url, body, key) do
    headers =
      [{~c"user-agent", ~c"aigifmaker-elixir/0.1.0"}] ++
        if(key, do: [{~c"authorization", String.to_charlist("Bearer " <> key)}], else: [])

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    request = {String.to_charlist(url), headers, ~c"application/json", JSON.encode!(body)}

    case :httpc.request(:post, request, [timeout: 60_000, ssl: ssl], body_format: :binary) do
      {:ok, {{_, status, _}, _headers, resp}} ->
        data =
          case JSON.decode(resp) do
            {:ok, d} when is_map(d) -> d
            _ -> %{"code" => -1, "message" => "HTTP #{status}"}
          end

        {:ok, status, data}

      {:error, why} ->
        {:error, why}
    end
  end
end
