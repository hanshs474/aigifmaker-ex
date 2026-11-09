# aigifmaker

Turn text into animated GIFs with AI GIF Maker. Native GIF generation — no video conversion. Type what you want and download your GIF in about a minute.

This is the official Elixir client for [AI GIF Maker](https://aigifmaker.ai/?utm_source=hex&utm_medium=package). One call sends your prompt, waits for the GIF and returns its URL.

```elixir
def deps do
  [{:aigifmaker, "~> 0.1"}]
end
```

```elixir
{:ok, url} = Aigifmaker.generate("a corgi in sunglasses dancing on a beach, looping")
```

No dependencies: `:httpc` from OTP and the standard `JSON` module. Elixir 1.18+.

## API key

Create a key at https://aigifmaker.ai/settings/apikeys, then pass it as `api_key:` or export it:

```bash
export AIGIFMAKER_API_KEY=sk-...
```

Each GIF costs 1 credit on your AI GIF Maker account, the same as on the website. New accounts get one free GIF (it carries a small aigifmaker.ai badge). A GIF that fails to generate gives its credit back. Credit packs are on the [pricing](https://aigifmaker.ai/pricing?utm_source=hex&utm_medium=package) page.

```elixir
{:ok, left} = Aigifmaker.credits()   # remaining credits, free to call
```

## Options

Every function takes `api_key:`, `base_url:` and `timeout:` (milliseconds `generate/2` waits, 5 minutes by default):

```elixir
Aigifmaker.generate("a tiny dragon sneezing a puff of glitter", api_key: "sk-...", timeout: 300_000)
```

## Submit now, collect later

```elixir
{:ok, task_id} = Aigifmaker.submit("happy birthday text bouncing in rainbow letters")
{:ok, %{"status" => status}} = Aigifmaker.status(task_id)   # pending | processing | success | failed
{:ok, url} = Aigifmaker.wait(task_id)                        # polls every 3 seconds
```

A run from an account that has not bought credits yet may wait in a short queue first (`"queued" => true` while `status` stays `processing`). That is normal; `generate/2` and `wait/2` keep polling.

## Errors worth matching

Failures are `{:error, reason, message}`:

- `:auth`: no key, or the key is wrong or deleted
- `:quota`: the account is out of credits
- `:rejected`: the content filter refused the prompt, or a cooldown is active; reword it
- `:failed`: the run was accepted but failed; the message says why
- `:timeout`: still running when the timeout passed; the GIF may finish later in your history
- `:other`: any other refusal or a network error, with the message

## Tests

```bash
mix test              # mocked, offline
mix test --only live  # two free live checks, no generation
```

MIT licensed. Questions: support@aigifmaker.ai
