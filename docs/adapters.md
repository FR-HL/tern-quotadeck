# Adapters

Quota discovers adapters by directory. Add a `.luau` file; no core edit is
needed.

```text
providers/   one provider each
sources/     one adapter that returns several providers
contexts/    one agent session log each
models.json  context-window overrides
```

Files named `util.luau` are ignored. A file that fails to load or has no
`fetch` function is skipped, so one broken adapter does not take the plugin
down.

## Provider adapter (quota)

```lua
return {
  api = 1,
  id = "example",
  name = "Example",
  short = "EX",
  icon = "provider-openai",
  windows = {
    { key = "hourly", label = "Hourly" },
  },
  detect = function(): boolean end, -- optional
  fetch = function(done)
    -- Read only the CLI's own credential file and call its usage endpoint.
    -- Call done exactly once.
    done({
      status = "ok", -- ok | auth | signed_out | error
      windows = {
        hourly = { used = 12, resets_at = "2026-10-31T12:00:00Z" },
      },
      balance = "$1.49", -- optional
      plan = "Pro",      -- optional
    })
  end,
}
```

`used` is a percentage from 0 to 100. `resets_at` is UTC ISO-8601.

## Source adapter

A source returns `{ item, item, … }` from `fetch(done)`, each item shaped like
the result of a provider adapter plus `id`, `name`, `icon` and `windows`.
`window.key` is arbitrary; `window.label` is the display label. Use a source
when one file already knows several providers, such as Magpie.

## Context adapter

```lua
return {
  api = 1,
  id = "example-agent",
  name = "Example Agent",
  icon = "activity",
  fetch = function(done)
    done({
      {
        agent = "Example Agent",
        icon = "activity",
        project = "my-project",       -- optional
        model = "example-model",      -- optional
        used = 451185,                -- prompt tokens of the latest request
        window = 1048576,             -- optional; omit when unknown
        at = "2026-10-31T12:00:00Z",  -- optional
      },
    })
  end,
}
```

Read the agent's own session file; never query a proxy or a vendor quota API
for context. Each agent counts tokens differently:

- OpenAI-compatible/Codex: `input_tokens` already includes cached input.
- Anthropic: `input_tokens + cache_read_input_tokens +
  cache_creation_input_tokens`.
- omp: use its `contextSnapshot.promptTokens`.

If the session does not carry a context window, leave `window` nil or add the
model to `models.json`.

## models.json

A JSON object from model id to context window, for agents whose logs do not
carry one:

```json
{
  "deepseek-v4.1-flash": 1000000,
  "my-model": 200000
}
```

The adapter looks up the full id, then the id without its provider prefix.
Users can extend this file without touching Lua.

## Data written by the plugin

Provider state and context state are plain JSON in the plugin's `kv.json`:

```json
{
  "context_state": {
    "updated": 0,
    "sessions": [
      { "agent": "omp", "project": "repo", "model": "m", "used": 1, "window": 2 }
    ]
  }
}
```

The format is public; another tool can write a compatible adapter or read the
data. Credentials never leave the machine.

## Testing an adapter

```sh
tern plugin reload
```

The plugin status must stay `ready`; open **Quota: Show details** and check the
new card. Adapters run in-process: a broken adapter is other people's code, so
review it before installing.
