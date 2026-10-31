# UI verification

Tern 0.9.8 · plugin 0.7.6 · 2026-10-31

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
- Settings: refresh interval, language, open mode, remaining/used value, and
  window/countdown/percentage/network toggles all take effect immediately.
- Status line: modules are separated with `|`; items inside one provider module
  are not split. The separator is its own segment with the default white color
  and does not inherit the download or upload tone. Example:

  ```text
  OC 5h 4h32m 96% | ↓ 2.3 MB/s ↑ 38 KB/s
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
