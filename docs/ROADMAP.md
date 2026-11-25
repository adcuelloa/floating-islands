# Roadmap (Pre-v1.0)

GitHub Issues, Pull Requests, and Discussions are the live day-to-day tracker for Floating Islands. This document summarizes the milestone structure and product boundaries toward **v1.0**.

## What v1.0 Means

A recoverable, daily-use Omarchy floating-islands bar with:
- full compatibility with Omarchy's bar and widget-hosting contracts;
- clear installation, trial, and TTY-safe rollback scripts;
- a community-shaped, keyboard-accessible Unified Control Center;
- verified contrast across dark and light Omarchy themes, reduced-motion compliance, and multi-monitor coverage;
- honest documentation of upstream platform limits.

## Non-Goals for v1.0

- Forking or modifying `/usr/share/omarchy`.
- Custom notification history center (blocked upstream: no notification history API for bar plugins).
- Invisible stacked buttons or pointer-mask hacks to hide hosted widgets.
- Reimplementing complex stock panels (Wi-Fi passwords, Bluetooth pairing, display arrangement) when native Omarchy panels already handle them cleanly.
- Universal external-monitor DDC/CI brightness controls.
- Full Minimal Notch or Full Adaptive Bar variants (post-v1.0). Incremental adaptive bar improvements (such as dynamic Clock Island expansion, dynamic critical indicators, and island visibility) and the exploratory Floating / Unified / Automatic presentation modes below are distinct from full Minimal Notch or Full Adaptive Bar shell variants; none of the unscheduled proposals broaden v1.0 acceptance criteria.

## Milestone Overview

| Milestone | Scope | Status |
|---|---|---|
| **M0 — Native Bar Core** | Omarchy `kind: "bar"` host contract, per-output surfaces, floating islands, responsive tiers, theme binding | Completed |
| **M1 — Calendar, Media & Routing** | Native calendar panel, native media island (hover preview + pin), tooltips, stock/third-party widget hosting and shortcut routing | Completed |
| **M2 — Safe Daily Use** | Trial mode with wall-clock watchdog, TTY-safe `rollback.sh`, `branch-test.sh` snapshots, bubblewrap sandbox tests, 24-hour single-display trial | Completed (reboot restore path pending live verification) |
| **M3 — Control Center Core** | Experimental panel (`bar.islands.controlCenter: false`): Night Light, Stay Awake, Do Not Disturb, Pipewire audio, Wi-Fi/Bluetooth toggles, grouped keyboard dashboard | Merged (experimental) |
| **M4 — Power Profiles** | UPower reactive profile selector with keyboard group navigation | Merged (experimental) |
| **M5 — Built-in Display Brightness** | Event-driven sysfs readback (`FileView`) + serialized `omarchy-brightness-display` writes | Merged (experimental) |
| **M6 — Visual Contrast & Polish** | Contrast fixes across Omarchy themes for failure/secondary/active/outside text; QML warning gates | Merged |
| **M7 — Open Source Readiness & Unified Control Center** | Public governance & docs consolidation, CI hardening (merged), plugin identity migration (`islands.bar` → `floating-islands`, merged), Upstream Watch read-only inspection stage (completed; automated reporting and canary work deferred), licensing/icon provenance resolution, community-driven Unified Control Center RFC and progressive implementation, multi-monitor & AT-SPI verification | **In Progress** |
| **M8 — v1.0 Release** | Finalized support matrix, release notes, tagged release, post-tag install/rollback verification | Planned |

## Product Design Direction & Proposals

To preserve design continuity without committing to unscheduled versions or silently expanding v1.0 acceptance criteria, items below are separated by maturity.

### Completed Foundation

- Core floating-islands bar, native calendar and media islands, responsive tiers (`full` / `compact` / `minimal`), configurable window-title (`showTitle`) and media (`showMedia`) visibility, safe trial/rollback tooling, and experimental Control Center modules (M0–M6).
- **Upstream Watch (read-only inspection stage):** Deterministic upstream capability inventory and read-only inspection/aggregation checks are completed (`docs/UPSTREAM_WATCH.md`). Automated reporting and canary workflows remain deferred.

### Owner-Supported Design Direction

These directions guide incremental improvements without committing to a single release date or blocking v1.0:

- **Adaptive Bar**
  - Compact idle Clock Island that expands on hover (after the existing delay) and while the calendar is open, restoring idle width afterward.
  - Dynamic critical indicators for screen recording, microphone activity, privilege (`PasswordlessSudo`), and remote sessions.
  - Responsive island sizing that prioritizes essential functionality over decorative content.
  - Configurable window-title and media island visibility (building on existing `showTitle` / `showMedia` settings).
  - Clear separation between presentation style, density (`compact` / `comfortable`), and responsive content tiers (`full` / `compact` / `minimal`).
- **Unified Control Center** (detailed in [docs/CONTROL_CENTER_RFC.md](CONTROL_CENTER_RFC.md))
  - Samsung One UI-inspired grouped quick settings, stateful circular controls, thick sliders, and modular customization.
  - macOS-inspired desktop composition, information hierarchy, and secondary navigation.
  - Native Omarchy services, theme tokens, and panel integration (`KeyboardPanel`).
  - Dynamic media module with album artwork and optional artwork-derived colors where supported, sharing the media service with the existing bar `MediaIsland`.
  - Progressive migration with verified functional parity before retiring any hosted widget.
- **Personalization**
  - Discrete module size variants.
  - Visual layout editing to reorder, resize, add, and remove controls.
  - Customizable Quick Settings group.
  - Explicit apply, cancel, and reset behavior backed by validated persistent preferences.
  - Full keyboard-accessible editing.
  - **Safety invariant:** Removing a control from the layout must never disable its underlying service or hide required critical indicators.

### Exploratory Proposals (Unscheduled)

- **Bar presentation modes (`Floating`, `Unified`, `Automatic`):** Proposed presentation styles orthogonal to density and responsive content tiers, where `Automatic` reacts to effective desktop gaps. Kept distinct from the deferred post-v1.0 Full Minimal Notch and Full Adaptive Bar shell variants.
- **Desktop Appearance controls:** Proposed visual controls for window rounding, border thickness, active/inactive/fullscreen opacity, inner and outer gaps, native appearance and animation settings where supported, and bar visual settings (style, density, island visibility, and placement). **Prerequisite:** Investigate native Omarchy configuration mechanisms before designing any persistence or compositor writes; direct modification of `/usr/share/omarchy` or unmanaged Hyprland user config remains a non-goal.
- **Upstream Watch automation:** Automated reporting and canary runs remain deferred beyond the completed read-only inspection stage.

### Unresolved Community Decisions

Widget placement, navigation hierarchy, single-entry vs. multi-glyph status composition, critical indicator placement, and numbered hotkey mapping remain open for community feedback in [docs/CONTROL_CENTER_RFC.md](CONTROL_CENTER_RFC.md) and GitHub Discussion #2.

## Unified Control Center Migration Rule

The target product direction is **one unified system-control entry point** on the status island, shaped with community input via [docs/CONTROL_CENTER_RFC.md](CONTROL_CENTER_RFC.md).

Migration follows a strict safety rule:

> **Never unhost a stock widget before its native replacement provides sufficient functional parity or an explicitly accepted fallback.**

Implementation order:
1. Finalize widget placement and navigation structure with community feedback (RFC).
2. Build shared navigation/subpage infrastructure first.
3. Implement and validate native replacements progressively (including accessibility and theme contrast).
4. Only then retire the corresponding legacy status button — without deleting user `bar.layout` entries, disabling underlying services, or using invisible anchor buttons.
