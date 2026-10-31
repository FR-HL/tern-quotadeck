# UI verification

Tern 0.9.8 · plugin 0.8.10 · 2026-10-31

Checked by clicking the live plugin in Tern, not only by reading the source.

## Checked

- Overview: only signed-in quota cards; no login, key, configuration or status
  badge (a visible card is normal by definition).
- Providers: each provider has one status/sign-in control, not two. Normal
  shows a check; signed out shows the sign-in icon; both never appear together.
  Grid hides from the overview and gauge from the status bar; changing one left
  the other unchanged. DeepSeek Key and the Custom endpoint use Tern's native
  prompt and accept pasted text.
- Magpie: Open Design and OpenCode Zen were discovered from
  `http://127.0.0.1:3425/v1/magpie/quotas` without manual configuration; the
  direct OpenCode Go card was not duplicated.
- Custom: the single endpoint entry detected a New API relay (balance) and a
  mock OpenAI billing endpoint (25% included window) without asking which
  protocol to use; both appeared as status badges and refreshed automatically.
- Context: omp, Claude Code and Codex were read from their own session logs,
  without Magpie. The Overview section showed up to eight recent sessions per
  agent (21 entries at once), with model, used/window, percentage and age;
  the model badge showed only `gpt-6.1-sol` / `deepseek-v4.1-flash`, without
  the provider prefix. Each card reused the provider icon from the quota card
  (`provider-opencode`, `provider-openai`, `provider-claude`). Clicking a card
  expanded provider, full model, used/window, remaining, exact timestamp and
  session path, then collapsed again. omp's numeric millisecond timestamp and
  Codex's direct context window were handled. The bottom dock stayed at three
  tabs.
- Context charts: expanding a Context card rendered a context-token history
  spark (`Context history · N`) and the matching provider's remaining history
  spark (`Remaining history · N`) from local samples; the history store keeps
  up to 7 days.
- Overview filter: the icon strip showed All, OpenCode Go, Codex, Claude and
  Open Design; choosing OpenCode kept only its quota card and dropped unrelated
  context, while Codex showed its context and All restored the complete page.
- Settings: refresh interval, language, open mode, remaining/used value, and
  window/countdown/percentage/network toggles all take effect immediately.
- Status line: modules are separated with `|`; items inside one provider module
  are not split. The separator is its own segment with the default white color
  and does not inherit the download or upload tone. Window labels normalize to
  `5h`/`7d`/`mo`, and the Names setting switched between `OD`/`OC`, full
  names, and hidden (`5h 2h38m 88%`). The Icon toggle removed the provider icon
  SVG entirely. Example:

  ```text
  OD 5h 2h51m 93% | OC 5h 2h41m 91% | ↓ 2.3 MB/s ↑ 38 KB/s
  ```

- Bottom dock: three equal-width tabs, consistent 12px outer padding and gap;
  measured 162.28px per tab in a 533px card.
- Narrow floating card: dock labels stay on one line (icons hidden, 11px text);
  provider rows keep name, badge and actions on one line with the name
  ellipsized if needed.
- Error paths: clicking an OAuth Sign in opens the provider CLI; no plugin
  handler error is logged.

## Screenshot

- `docs/preview.png` — current Overview page.
