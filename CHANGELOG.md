# Changelog

## 0.8.11 — 2026-10-31

- Rename the display name, block title, commands and documentation to
  QuotaDeck; the internal plugin id stays `quota` for compatibility.

## 0.8.10 — 2026-10-31

- Move history charts into expanded Context details: context-token history and
  provider remaining history. Remove the quota-card sparkline.

## 0.8.9 — 2026-10-31

- Record up to seven days of remaining-quota samples.
- Show a remaining-history sparkline on each quota card.

## 0.8.8 — 2026-10-31

- Click a Context card to expand provider, full model, used/window,
  remaining, exact timestamp and session file path.

## 0.8.7 — 2026-10-31

- Use the provider icon in Context cards, matching the quota card, instead
  of the agent app icon.

## 0.8.6 — 2026-10-31

- Show only the bare model name in Context cards; provider prefixes and
  account suffixes are removed.

## 0.8.5 — 2026-10-31

- Read up to eight recent session files per agent instead of only the newest,
  so the Context section shows more history.

## 0.8.4 — 2026-10-31

- Add a Hidden name style to the status line.
- Add an Icon toggle for provider icons in the status line.

## 0.8.3 — 2026-10-31

- Normalize status-line window labels (5h/7d/mo) and provider names across
  sources, so OpenCode and Open Design no longer use different formats.
- Add Status line → Names: short codes (default) or full names.

## 0.8.2 — 2026-10-31

- Add a provider icon strip at the top of Overview; clicking one filters
  quota cards and context sessions to that provider. An All icon restores both.

## 0.8.1 — 2026-10-31

- Move the Context section from its own tab onto Overview.

## 0.8.0 — 2026-10-31

- Relicensed under MIT.
- Added a Context tab reading omp, Claude Code and Codex session logs directly;
  no Magpie dependency.
- Added drop-in adapter loading for providers/, sources/ and contexts/.
- Added models.json overrides for context windows.

## 0.7.6 — 2026-10-31

- Keep the status-line separator a separate white segment instead of
  inheriting the download or upload color.

## 0.7.5 — 2026-10-31

- Merge status and sign-in/key into one control: a check when normal, the
  action itself when not, so login and not-signed-in never both show.

## 0.7.4 — 2026-10-31

- Remove the redundant status icon from overview cards.
- Split visibility into two independent toggles: grid for the overview and
  gauge for the status bar, for built-in and custom providers.
- Use Tern icon names for the warning and trash glyphs.

## 0.7.3 — 2026-10-31

- Provider status and actions are icons with tooltips: signed out, sign in,
  key, hide, show and remove.
- Keep provider icons visible in narrow floating cards.
- Status and action icons share one tile: same frame, background and size;
  color alone distinguishes them.

## 0.7.2 — 2026-10-31

- Keep the last Magpie provider list across plugin reloads and gateway restarts.

## 0.7.1 — 2026-10-31

- One custom endpoint entry, auto-detecting New API or OpenAI billing.
- Keep provider icons visible in narrow floating cards.

## 0.7.0 — 2026-10-31

- Auto-discover providers from Magpie's local quota API, including Open Design.
- Merge Magpie entries with direct providers without duplicate cards.
- Add a New API / One API relay preset and keep OpenAI billing as a preset.
- Use Tern's native prompt for custom fields; clipboard paste and selection work.

## 0.6.2 — 2026-10-31

- Removed the download icon and the middle dot from the quota module.
- Split network speed into separately colored download/upload segments.
- Added download and upload color settings.
- Verified settings survive closing the detail page and reloading the plugin.

## 0.6.1 — 2026-10-31

- Relicensed under PolyForm Noncommercial 1.0.0; commercial use requires a
  separate written license.
- Added NOTICE with the Required Notice and attribution requirements.
- Added bilingual English and Simplified Chinese README files.
- Documented provider data sources, credits and modification attribution.

## 0.6.0 — 2026-10-31

- Configurable status line: remaining or used value; window label, reset
  countdown, percentage and network speed can be toggled separately.
- Status-line modules are separated with `|`; items within a provider module
  stay together.
- Added download/upload speed from the OS adapter counters (Windows).
- Equal-width bottom tabs with consistent padding and narrow PiP adaptation.
- Provider rows, dock labels and settings controls adapt to floating PiP width
  without wrapping labels.
- DeepSeek keys and custom endpoints use Tern's native prompt fields.
- Removed the inline input experiments; native prompts support paste.

## 0.5.0

- DeepSeek balance provider.
- Custom OpenAI-compatible billing endpoints.
- Provider page with login, key, hide/show and custom endpoint controls.
