defmodule AigifmakerTest do
  use ExUnit.Case

  # Mocked unit tests in the real response shapes (every response is HTTP 200;
  # the JSON code decides).
  @gif "https://cdn.aigifmaker.ai/out/a.gif"

  defp ok(data), do: {:ok, 200, %{"code" => 0, "message" => "ok", "data" => data}}
  defp err(msg, code \\ -1), do: {:ok, 200, %{"code" => code, "message" => msg}}

  # Replays replies in order (the last one repeats) and reports each request.
  defp script(replies) do
    {:ok, agent} = Agent.start_link(fn -> replies end)
    me = self()

    fn url, body, key ->
      send(me, {:req, url, body, key})

      Agent.get_and_update(agent, fn
        [r] -> {r, [r]}
        [r | rest] -> {r, rest}
      end)
    end
  end

  defp opts(t, extra \\ []), do: [api_key: "sk-test", poll_ms: 0, transport: t] ++ extra

  test "success: fixed body, bearer key, GIF URL" do
    t =
      script([
        ok(%{"id" => "t1", "status" => "pending", "taskId" => "up-1"}),
        ok(%{"id" => "t1", "status" => "processing"}),
        ok(%{"id" => "t1", "status" => "success", "images" => [@gif], "watermarked" => [false]})
      ])

    assert {:ok, @gif} = Aigifmaker.generate("a dancing cat", opts(t))

    assert_received {:req, "https://aigifmaker.ai/api/ai/generate", body, "sk-test"}

    assert body == %{
             "provider" => "openlux",
             "mediaType" => "image",
             "model" => "gif-maker-v1",
             "scene" => "text-to-image",
             "prompt" => "a dancing cat",
             "options" => %{"output_format" => "gif"}
           }

    assert_received {:req, "https://aigifmaker.ai/api/ai/query", %{"taskId" => "t1"}, _}
  end

  test "credits" do
    t = script([ok(%{"remainingCredits" => 7, "made" => 2})])
    assert {:ok, 7} = Aigifmaker.credits(opts(t))
  end

  test "queued: keeps polling" do
    q = ok(%{"id" => "t1", "status" => "processing", "queued" => true, "queueEta" => 30})

    t =
      script([
        ok(%{"id" => "t1", "status" => "pending"}),
        q,
        q,
        ok(%{"id" => "t1", "status" => "success", "images" => [@gif], "watermarked" => [true]})
      ])

    assert {:ok, @gif} = Aigifmaker.generate("x", opts(t))
    for _ <- 1..4, do: assert_received({:req, _, _, _})
  end

  test "failed run" do
    t =
      script([
        ok(%{"id" => "t1", "status" => "pending"}),
        ok(%{"id" => "t1", "status" => "failed", "errorMessage" => "upstream error"})
      ])

    assert {:error, :failed, "upstream error"} = Aigifmaker.generate("x", opts(t))
  end

  test "moderation failure is :rejected" do
    t =
      script([
        ok(%{"id" => "t1", "status" => "pending"}),
        ok(%{
          "id" => "t1",
          "status" => "failed",
          "errorMessage" => "blocked",
          "failureKind" => "moderation"
        })
      ])

    assert {:error, :rejected, _} = Aigifmaker.generate("x", opts(t))
  end

  test "invalid key" do
    t = script([err("invalid API key — create one at https://aigifmaker.ai/settings/apikeys")])
    assert {:error, :auth, _} = Aigifmaker.credits(opts(t))
  end

  test "wall without key: no Authorization sent" do
    t = script([ok(%{"wall" => true, "reason" => "anon_credits"})])
    old = System.get_env("AIGIFMAKER_API_KEY")
    System.delete_env("AIGIFMAKER_API_KEY")

    try do
      assert {:error, :auth, msg} = Aigifmaker.submit("x", poll_ms: 0, transport: t)
      assert msg =~ "settings/apikeys"
      assert_received {:req, _, _, nil}
    after
      if old, do: System.put_env("AIGIFMAKER_API_KEY", old)
    end
  end

  test "insufficient credits" do
    t = script([err("insufficient credits")])
    assert {:error, :quota, msg} = Aigifmaker.submit("x", opts(t))
    assert msg =~ "aigifmaker.ai/pricing"
  end

  test "cooldown and generic refusals" do
    assert {:error, :rejected, _} = Aigifmaker.submit("x", opts(script([err("slow down", 429)])))

    assert {:error, :other, "something else"} =
             Aigifmaker.submit("x", opts(script([err("something else")])))
  end

  test "a dropped poll is retried" do
    t =
      script([
        ok(%{"id" => "t1", "status" => "pending"}),
        {:error, :econnreset},
        ok(%{"id" => "t1", "status" => "success", "images" => [@gif]})
      ])

    assert {:ok, @gif} = Aigifmaker.generate("x", opts(t))
  end

  test "timeout" do
    t = script([ok(%{"id" => "t1", "status" => "processing"})])
    assert {:error, :timeout, _} = Aigifmaker.generate("x", opts(t, timeout: 0))
  end

  test "empty prompt" do
    assert {:error, :other, _} = Aigifmaker.submit("  ", opts(script([])))
  end

  # Free live checks against https://aigifmaker.ai, no generation: mix test --only live
  @tag :live
  test "live: invalid key -> :auth" do
    assert {:error, :auth, _} = Aigifmaker.credits(api_key: "sk-invalidtest000")
  end

  @tag :live
  test "live: no key -> :auth (wall)" do
    System.delete_env("AIGIFMAKER_API_KEY")
    assert {:error, :auth, _} = Aigifmaker.submit("smoke test: a blinking star")
  end
end
