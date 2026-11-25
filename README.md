# Floating Islands

A native, theme-adaptive shell extension for [Omarchy](https://omarchy.org), built with Quickshell and QML.

Floating Islands is a native `kind: "bar"` plugin written in QML and pure JavaScript that runs inside `omarchy-shell` with no background daemon or separate process. It is **not** a theme, wallpaper collection, dotfiles distribution, or standalone shell replacement: Omarchy retains ownership of themes, wallpapers, fonts, notifications, launcher, OSD, lock screen, and core system services, while Floating Islands adapts live to the active Omarchy theme and replaces only the bar presentation.

> **Status: Alpha / Pre-v1.0 development.** Automated checks pass on CI (`qa` + `sandbox`), and single-display daily use has completed a 24-hour supervised trial. Multi-monitor sessions, suspend/resume, reboot restore, and the experimental Control Center (`bar.islands.controlCenter: false` by default) are still in progress. See [docs/ROADMAP.md](docs/ROADMAP.md) and [docs/TESTING.md](docs/TESTING.md).

## Screenshots & Demo

*Verified Floating Islands desktop screenshots and a short Wayland walkthrough capture will be added here prior to the initial alpha release (dark and light Omarchy themes, calendar and media popouts, and hosted status island).*

## Current Functionality

- **Floating island layout:** Launcher + workspace dots, elastic active-window title, centered clock, media controls, and a dedicated status island — with per-output responsive tiers (`full`, `compact`, `minimal`) computed from measured widths rather than fixed pixel breakpoints.
- **Native Omarchy integration:**
  - Hosts stock and third-party right-section widgets via Omarchy's public `PluginBarApi` contract (`SUPER+CTRL+1..9` numbered shortcuts, `SUPER+CTRL+ALT+*` named shortcuts, and one-panel-at-a-time handover).
  - Binds directly to `Commons.Color` and `Commons.Style` (live theme switching across dark and light Omarchy themes, zero transitions when reduced motion is enabled, and `bar.position: "bottom"` support).
  - Uses the `omarchy-bar` layer-shell namespace and explicit `exclusiveZone` with an exact island-only input mask so the bar never steals focus or swallows clicks outside the islands.
- **Native popouts & media:** Native Calendar panel (`SUPER+CTRL+ALT+D`), native Media island (hover preview + click pin), and bar-drawn tooltips.
- **Experimental Control Center (opt-in):** Behind `bar.islands.controlCenter: false` — grouped keyboard-accessible dashboard with Night Light, Stay Awake, Do Not Disturb, Pipewire audio output, Wi-Fi/Bluetooth toggles, UPower power profiles, and event-driven built-in display brightness.
- **Internationalization:** English (`en`), Spanish (`es`), and Japanese (`ja`) translation catalogs under `plugin/i18n/`.

## Architecture

Floating Islands separates pure logic from Quickshell views and system adapters:

```text
plugin/            Installable Omarchy plugin folder (id: floating-islands)
  manifest.json    Plugin metadata, kind "bar", entry point
  Bar.qml          Entry point, host contract, settings, trial mode, IPC
  core/            Per-output BarSurface, WidgetHosting, HostedBarApi, Identity
  geometry/        Layout.js — responsive tiers, exclusive zone, hit areas (pure JS)
  theme/           Theme.qml (bound to Commons.Color/Style), Palette.js, Icons.js
  logic/           Pure JS modules: workspaces, titles, settings, clock, calendar, media, routes, control center
  adapters/        Compositor and system-service adapters (Hyprland, Pipewire, Connectivity, UPower, Brightness)
  components/      Island, IslandButton, StrokeIcon, Divider, TooltipBubble
  widgets/         Launcher/workspaces, title, clock, calendar, media, hosted status island, Control Center
  i18n/            en, es, ja translation catalogs
scripts/           install, activate, branch-test, rollback, uninstall
tests/             contract, lint, imports, unit (Node), QML (offscreen), bubblewrap sandbox, privacy
docs/              architecture, compatibility, decisions, testing, recovery, roadmap, design references, RFC
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/DECISIONS.md](docs/DECISIONS.md) for details.

## Supported & Tested Environments

Verified against:

- **Omarchy** `4.5.0-3` (`omarchy`, `omarchy-settings`)
- **Quickshell** `0.3.2`
- **Qt 6** `6.12.0` (`qt6-base`, `qt6-declarative`, `qt6-svg`, `qt6-wayland`)
- **Hyprland** `0.56.2` (Lua configuration)
- **Live desktop trial reference:** single display `1920×1080` at scale `1.25` (`1536×864` logical)

Compatibility is verified symbol by symbol rather than by strict version equality: run `tests/contract/check-contract.sh` to check whether your installed Omarchy tree satisfies every upstream API this bar uses. See [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) and [docs/TESTING.md](docs/TESTING.md) for the live vs. offscreen verification matrix and known gaps (multi-monitor, suspend/resume, external DDC/CI monitors, real AT-SPI screen readers).

## Safe Installation, Trial, and Rollback

Read [docs/RECOVERY.md](docs/RECOVERY.md) before activating the bar on a live desktop. Activation is always explicit, and a default trial never survives a logout or reboot.

```bash
tests/run-all.sh                     # Run the full isolated test suite (touches nothing outside /tmp)
scripts/install.sh                   # Copy plugin into ~/.config/omarchy/plugins/floating-islands (does not activate)
scripts/activate.sh --check          # Pre-flight validation only (no config changes)
scripts/activate.sh --confirm        # Explicit trial for this login session; rolls back automatically on failure
scripts/rollback.sh                  # Restore the stock Omarchy bar (works from a TTY)
scripts/branch-test.sh --arm 45      # Safely test a development build over an existing daily bar with auto-restore
```

*Existing `bar.islands` settings and legacy `islands.bar` installations/recovery paths remain supported; see [docs/NAMING.md](docs/NAMING.md).*

## Settings

Configured under `bar.islands` in `~/.config/omarchy/shell.json` (hot-reloads automatically):

| Key | Values | Default |
|---|---|---|
| `density` | `compact` (40 px islands), `comfortable` (46 px) | `compact` |
| `tier` | `auto`, `full`, `compact`, `minimal` | `auto` |
| `timeFormat` | Qt time format string | `HH:mm` |
| `showTitle` | boolean | `true` |
| `hostWidgets` | boolean: host stock right-section widgets | `true` |
| `hosted` | list of widget IDs to host instead of `bar.layout.right` | — |
| `extraHosted` | list of additional widget IDs (e.g., `["omarchy.elsewhen", "omarchy.weather"]`) | `[]` |
| `locale` | `auto`, `en`, `es`, `ja` (clock and calendar) | `auto` |
| `showMedia` | boolean: native media island | `true` |
| `mediaEqualizer` | `animated`, `static` | `animated` |
| `launcherIcon` | `omarchy` (Omarchy logo glyph), `grid` (generic app grid) | `omarchy` |
| `controlCenter` | boolean: experimental Control Center entry and panel | `false` |
| `titleIcon` | `app` (application icon with symbol fallback), `symbol` (monochrome symbol) | `app` |

`extraHosted` brings placed stock widgets from other sections into the status island without replacing `bar.layout.right`. They keep their named shortcuts (`SUPER+CTRL+ALT+E` for World Clock, `SUPER+CTRL+ALT+W` for Weather) without shifting `SUPER+CTRL+1..9`.

**Shortcuts & IPC:**
- Calendar (`SUPER+CTRL+ALT+D` / `omarchy.clock`) toggles the native calendar on the focused output.
- `omarchy-shell floating-islands toggleCalendar` / `toggleControlCenter` / `toggleMedia` toggle panels via IPC.
- `omarchy-shell floating-islands geometry` / `slots` / `tooltip` report read-only diagnostics.
- `bar.position: "bottom"` anchors islands to the bottom edge (left/right map to top).

## Roadmap, Design RFC & References

- [Roadmap (Pre-v1.0)](docs/ROADMAP.md) — milestone status, v1.0 criteria, and non-goals.
- [Upstream Watch](docs/UPSTREAM_WATCH.md) — capability inventory, upstream findings, and the planned watcher and compatibility canary.
- [Unified Control Center RFC](docs/CONTROL_CENTER_RFC.md) — open community design questions for widget placement, indicators, and navigation before v1.0.
- [Design References](docs/DESIGN_REFERENCES.md) — architectural and interaction inspirations (Shoji Bar, Caelestia as a concept-only GPL-3.0 boundary, Shibumi-Shell, Stellarchy, Omarchy 4.5.0).

## Documentation

- [Contributing](CONTRIBUTING.md), [Code of Conduct](CODE_OF_CONDUCT.md), and [Security Policy](SECURITY.md)
- [Engineering Invariants (AGENTS.md)](AGENTS.md)
- [Architecture](docs/ARCHITECTURE.md) and [Design Decisions](docs/DECISIONS.md)
- [Compatibility & Upstream Contract](docs/COMPATIBILITY.md)
- [Testing](docs/TESTING.md) and [Recovery](docs/RECOVERY.md)
- [Naming & Identity](docs/NAMING.md), [Licensing & Attribution](docs/LICENSING.md), and [Third-Party Licenses](THIRD_PARTY_LICENSES.md)

## Contributing & Community

Floating Islands is being built as a community-driven open-source project before v1.0. Contributions are welcome across QML/JS implementation, multi-monitor and hardware testing, dark/light theme contrast checks, keyboard/AT-SPI accessibility, translations (`plugin/i18n/`), and documentation.

- Read [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md) before opening a pull request.
- Join the [Unified Control Center RFC](docs/CONTROL_CENTER_RFC.md) to help shape widget placement and interaction before v1.0.
- Report security issues privately via [SECURITY.md](SECURITY.md).

## Attribution & License

Built for the [Omarchy](https://omarchy.org) shell, implementing its public bar and widget-hosting contracts.

Current-tree license: **MIT** ([LICENSE](LICENSE), `Copyright (c) 2026 Floating Islands contributors`), with pinned Lucide (`1.79.0`) interface icon notices (ISC and applicable Feather MIT) in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md). Current-tree icon remediation does not retroactively resolve historical asset provenance in prior Git commits; see [docs/LICENSING.md](docs/LICENSING.md) for current-tree vs. historical provenance notes and the design-token review.
