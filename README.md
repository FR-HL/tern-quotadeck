# Quota

English | [简体中文](README.zh-CN.md)

Remaining coding-agent quota in Tern's status line, with a native detail page.

![Quota detail page](docs/preview.png)

Quota reads the logins your CLIs already keep on this machine, asks each
vendor's usage endpoint from the daemon, and renders the result with Tern's
native UI. One fetch covers every window; a broken or expired login never
hides the other providers.

## Features

- OpenCode Go, Claude, Codex, GitHub Copilot, Cursor, Gemini CLI and DeepSeek
- **Context** section on Overview, reading omp, Claude Code and Codex session
  logs directly
- Provider icon strip on Overview: click one to show only that provider's
  quota and sessions; click **All** to restore
- Drop-in adapters: every `.luau` in `providers/`, `sources/` and `contexts/`
  is loaded automatically
- Magpie's providers appear automatically through its local quota API,
  including Open Design and plugin-managed accounts
- One custom endpoint that detects New API / One API relays or OpenAI billing
- Status line with configurable remaining/used value, window label, reset
  countdown, percentage and network speed
- Five-hour, weekly and monthly windows where the provider exposes them
- Native providers, Providers and Settings pages; no web dashboard
- Read-only provider requests; no token refresh and no credential upload

## Install

From GitHub:

```sh
tern plugin install github.com/FR-HL/tern-quota
```

Or link a checkout while developing:

```sh
tern plugin link /path/to/tern-quota
tern plugin reload
```

Click the status segment, or run **Quota: Show details**, to open the detail
page. Preferences → Plugins can also install a directory or Git URL.

## Status line

The default segment combines the first window, its reset countdown and the
remaining percentage:

```text
OC 5h 4h32m 96%
```

A separate network module follows it:

```text
OC 5h 4h32m 96% | ↓ 2.3 MB/s ↑ 38 KB/s
```

Settings → **Status line** lets you choose:

- value: remaining or used
- names: short codes (default, `OC`, `OD`, `CX`), full provider names, or hidden
- icon: show or hide the provider icon in each status segment
- show window label, reset countdown, percentage and network speed; the speed module has separate download/upload colors

Window labels are normalized to `5h`, `7d` and `mo` for every source, so
OpenCode and Open Design share one format:

```text
OD 5h 2h51m 93% | OC 5h 2h41m 91%
```

For example, countdown plus remaining only:

```text
OC 4h32m 96%
```

Download and upload are separate status-line segments with their own color
settings and no extra icon. Network speed is sampled from the operating
system's adapter counters every few seconds. It is currently implemented with
PowerShell, so the speed module is Windows-only; quota segments work wherever
Tern runs.

## Providers

| Provider | Read from | Notes |
| --- | --- | --- |
| OpenCode Go | `~/.local/share/opencode/auth.json` | 5-hour, weekly and monthly windows |
| Claude | `~/.claude/.credentials.json` | 5-hour and weekly windows; uses the stored access token |
| Codex | `~/.codex/auth.json` | ChatGPT OAuth only; the WHAM endpoint is undocumented |
| GitHub Copilot | Copilot CLI `hosts.json`, else `gh auth token` | Premium requests, chat, completions |
| Cursor | `Cursor/auth.json` | Included and API usage |
| Gemini CLI | `~/.gemini/oauth_creds.json` | Code Assist quota; read-only, no token refresh |
| DeepSeek | Providers → **Key**, `DEEPSEEK_API_KEY`, or **Quota: Set DeepSeek API key** | Account balance (`¥`/`$`), no percentage windows |
| Magpie | `http://127.0.0.1:3425/v1/magpie/quotas` | Auto-detected; includes Open Design and plugin providers Magpie tracks |
| Custom endpoint | Providers → **Custom → Add endpoint** | Auto-detects New API `/api/usage/token/` or OpenAI `dashboard/billing` |

DeepSeek keys and the custom endpoint use Tern's native prompt field, so normal
clipboard paste works. The overview shows only providers that are signed in
and have quota to draw; every provider is listed on **Providers** with
one icon-only status control per provider. When the provider is normal it
shows a check; when it is not, the same control is its **Sign in** / **Key**
action, so both never appear together. Separate grid (overview) and gauge
(status bar) toggles follow, each labelled on hover. Magpie entries are
read-only and marked **Auto**.

## Commands

| Command | What it does |
| --- | --- |
| **Quota: Show details** | Opens the one detail page (or focuses it) |
| **Quota: Choose providers** | Opens the detail page on Providers |
| **Quota: Settings** | Opens the detail page on Settings |
| **Quota: Set DeepSeek API key** | Asks for the DeepSeek key with Tern's native prompt |
| **Quota: Refresh now** | Fetches immediately instead of waiting |

Only one detail page exists per window: clicking the status segment again
focuses it instead of opening another. Inside the page, `r` refreshes and
`q`/Esc closes it. Click a provider's header to fold it; the choice is
remembered.

## Detail page

The page has three tabs in the bottom dock:

- **Overview** — a provider icon strip filters the page; quota cards follow,
  then a **Context** section with up to eight recent sessions per agent from
  its own log (omp, Claude Code and Codex): used/window, percentage and age.
  No login, key or provider settings.
- **Providers** — one icon-only status control per provider: a check when
  normal, otherwise the **Sign in** / **Key** action. Then **grid** controls
  the overview and **gauge** controls the status bar; each is labelled on
  hover and neither signs you out. **Custom → Add endpoint** asks for the name,
  base URL and key with Tern's native prompt, then detects the protocol.
- **Settings** — refresh interval (1, 2 or 5 minutes), language (Auto,
  English, 中文), how the page opens (Floating by default; Tab, Docked), and
  the status-line format.

Settings live in the plugin's own `kv`, not in Tern's preferences. DeepSeek
keys and custom endpoint keys are stored there too; treat that folder as
private to your user account, not as a secret vault.

## Privacy and security

- Reads only the credential files listed above, capped at 64 KiB each.
- Provider tokens stay in memory for the request and are never written back.
- Provider usage results are cached in Tern's plugin data folder: percentages,
  reset times and 24 hours of history.
- DeepSeek and custom-endpoint keys are stored in the plugin's own `kv` so the
  daemon can refresh balances. They are sent only to the endpoint you chose.
- No Tern servers are involved.

## Limitations

- Codex and Copilot use undocumented endpoints; they can change without notice.
- Claude and Gemini tokens are used as stored; Quota does not refresh them.
  Re-run the provider CLI if a token expires.
- Quota is a window plugin: it reads the machine the window runs on, not a
  remote host's.
- Context shows recent sessions (up to eight per agent), not necessarily the
  session in a particular pane; parallel sessions can make that ambiguous.
- Context adapters currently cover omp, Claude Code and Codex. Other agents
  need an adapter; a session without a known context window still shows used
  tokens, without a percentage.
- Network speed is currently Windows-only.

## Development

Providers, sources and contexts are plain Luau modules. Every `.luau` file in
`providers/`, `sources/` or `contexts/` is loaded automatically; there is no
list to edit.

```lua
return {
  api = 1,
  id = "example",
  name = "Example",
  short = "EX",              -- used in the status line
  icon = "provider-openai",  -- any Tern icon name
  windows = {
    { key = "hourly", label = "Hourly" },
  },
  fetch = function(done)     -- call done exactly once
    done({ status = "ok", windows = { hourly = { used = 12 } } })
  end,
}
```

Context adapters read their agent's own session log and return
`{ agent, project, model, used, window, at }`. See
[`docs/adapters.md`](docs/adapters.md) for the full contract, the public JSON
shape and `models.json` overrides. Keep requests read-only and never write a
credential.

## License and attribution

This project is open source under the [MIT License](LICENSE).

You may use, copy, modify, merge, publish, distribute, sublicense and sell
copies, including closed-source and commercial versions, provided the
copyright and permission notice in `LICENSE` are kept.

## Credits

- Built for [Tern](https://stencil.so/tern) by Stencil.
- Provider names, endpoints and CLI login formats belong to their respective
  vendors. Quota is an independent, unofficial client and is not endorsed by
  any provider.
- No vendor documentation text or credential files are bundled with this
  repository.
