# Changelog

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
