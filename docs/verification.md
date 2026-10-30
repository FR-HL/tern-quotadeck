# UI verification

Tern 0.9.8 · plugin 0.6.2 · 2026-10-31

Checked by clicking the live plugin in Tern, not only by reading the source.

## Checked

- Overview: only signed-in quota cards; no login, key or configuration controls.
- Providers: every provider keeps its own Sign in/Key button; Hide/Show changes
  the overview and status line; DeepSeek Key and Custom Add use Tern's native
  prompt and accept pasted text.
- Settings: refresh interval, language, open mode, remaining/used value, and
  window/countdown/percentage/network toggles all take effect immediately.
- Status line: modules are separated with `|`; items inside one provider module
  are not split. Example:

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
