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
- Full Minimal Notch or Full Adaptive Bar variants (post-v1.0).

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
| **M7 — Open Source Readiness & Unified Control Center** | Public governance & docs consolidation, CI hardening (merged), plugin identity migration (`islands.bar` → `floating-islands`, merged), licensing/icon provenance resolution, community-driven Unified Control Center RFC and progressive implementation, multi-monitor & AT-SPI verification | **In Progress** |
| **M8 — v1.0 Release** | Finalized support matrix, release notes, tagged release, post-tag install/rollback verification | Planned |

## Unified Control Center Migration Rule

The target product direction is **one unified system-control entry point** on the status island, shaped with community input via [docs/CONTROL_CENTER_RFC.md](CONTROL_CENTER_RFC.md).

Migration follows a strict safety rule:

> **Never unhost a stock widget before its native replacement provides sufficient functional parity or an explicitly accepted fallback.**

Implementation order:
1. Finalize widget placement and navigation structure with community feedback (RFC).
2. Build shared navigation/subpage infrastructure first.
3. Implement and validate native replacements progressively (including accessibility and theme contrast).
4. Only then retire the corresponding legacy status button — without deleting user `bar.layout` entries, disabling underlying services, or using invisible anchor buttons.
