# Naming and Project Identity

## Canonical Project Identity

| Field | Canonical Value | Notes |
|---|---|---|
| **Project name** | **Floating Islands** | Descriptive phrasing: "a native floating bar plugin for Omarchy" |
| **Repository** | `adcuelloa/floating-islands` | Canonical GitHub repository |
| **Plugin ID** | `floating-islands` | Legacy `islands.bar` remains supported by upgrade/rollback scripts |
| **IPC target** | `floating-islands` | `omarchy-shell floating-islands <command>` |
| **Plugin kind** | `bar` | Declared via `"kinds": ["bar"]` in `plugin/manifest.json` |
| **Settings namespace** | `bar.islands` | Decoupled from plugin ID to preserve user settings across upgrades |
| **Layer-shell namespace** | `omarchy-bar` | Matches Omarchy's Hyprland layer rules |
| **Recovery / watchdog namespaces** | `islands-*` | `islands-bar-watchdog`, `islands-branch-restore`, `islands-branch-restore-boot.service`, `~/.local/state/islands-branch-test` |
| **License & copyright** | MIT — `Copyright (c) 2026 Floating Islands contributors` | See [docs/LICENSING.md](LICENSING.md) |

## Strategy

- **No redundant `.bar` suffix:** The plugin type is already declared via `"kinds": ["bar"]` in `plugin/manifest.json`. `floating-islands` passes `omarchy-plugin-validate`, `PluginRegistry.qml`, `omarchy-plugin-remove`, and `omarchy-plugin-update` (`^[A-Za-z0-9][A-Za-z0-9._-]*$`, outside the reserved `omarchy.*` namespace).
- **Decoupled settings and recovery namespaces:**
  - `bar.islands` in `~/.config/omarchy/shell.json` is intentionally decoupled from the plugin ID so migrating from `islands.bar` to `floating-islands` preserves user configuration unchanged.
  - Layer-shell namespace stays `omarchy-bar` so Omarchy's Hyprland layer rules apply unchanged.
  - Internal recovery and watchdog namespaces (`islands-*`, such as `islands-bar-watchdog`, `islands-branch-restore`, `islands-branch-restore-boot.service`, and `~/.local/state/islands-branch-test`) are retained for continuity.
- **Legacy compatibility:** `scripts/install.sh`, `scripts/activate.sh`, `scripts/rollback.sh`, and `scripts/branch-test.sh` preserve legacy `islands.bar` handling (including TTY rollback without `--any-bar` and exact snapshot restoration on failed upgrades) without deleting existing `~/.config/omarchy/plugins/islands.bar` directories automatically.
- **Single source of truth in code:**
  - `plugin/manifest.json` (`id`, `name`): source of truth, injected by the shell and read by scripts with `jq`.
  - `plugin/core/Identity.js`: pre-injection fallback ID, settings key (`bar.islands`), diagnostics IPC target, and layer-shell namespace.
  - `scripts/rollback.sh` (`PLUGIN_ID_DEFAULT`, `LEGACY_PLUGIN_IDS`, `SETTINGS_KEY`): standalone fallbacks so TTY rollback works even from a broken checkout.
  - `scripts/lib/common.sh` (`settings_key`, legacy ID helpers).
- **No brand confusion:** "Omarchy" is used only descriptively ("a bar for the Omarchy shell"), never as part of the project name or plugin ID.
