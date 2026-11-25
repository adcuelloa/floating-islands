# Testing

Floating Islands separates **isolated automated verification** (safe to run on any checkout, touching nothing outside `/tmp`) from **supervised live Wayland trials** (explicitly armed with automatic rollback).

## Full Isolated Suite

```bash
tests/run-all.sh
```

Stages executed in order:

| Stage | Command | What it verifies |
|---|---|---|
| Plugin validation | `omarchy-plugin-validate` | `plugin/manifest.json` schema, plugin ID rules, entry points |
| QML imports | `tests/imports.sh` | Every QML import resolves and stays within the declared allowlist |
| Static lint | `tests/lint.sh` | `qmllint` against installed `qs` modules with `tests/lint-allowlist.txt` |
| Upstream contract | `tests/contract/check-contract.sh` | Symbol-level check of every Omarchy/Quickshell/Hyprland API in `tests/contract/contract.tsv` |
| Contract self-test | `tests/contract/self-test.sh` | Proves unrelated upstream edits pass and simulated symbol removals fail |
| Pure JS unit tests | `node --test tests/unit/*.test.mjs` | Layout geometry, tiers, routes, hosting reconciliation, calendar/media, Control Center logic, theme contrast, upstream capability inventory (schema, states, references against the installed Omarchy tree), read-only upstream watcher and aggregation (detectors, ranges, state validation, report schema, correlation, safe rendering; synthetic fixtures only) |
| Offscreen QML tests | `tests/qml/run.sh` | `qmltestrunner` offscreen component tests with service stubs; fails on unexpected stderr/warnings |
| Sandbox script tests | `tests/scripts/isolated.sh tests/scripts/sandbox.test.sh` | Bubblewrap-isolated tests of `install.sh`, `activate.sh`, `rollback.sh`, `uninstall.sh`, `branch-test.sh`, TTY fallback, and atomic `shell.json` edits |
| Privacy gate | `tests/privacy.sh` | Blocks current username, home path, hostname, email-shaped text, or key-shaped text |

## Running Subsets Without Omarchy Installed

If you are editing pure JavaScript logic or documentation on a non-Arch machine:

```bash
node --test tests/unit/*.test.mjs
tests/privacy.sh
```

## Supervised Live Desktop Testing

Offscreen tests use stubs for Hyprland, Pipewire, NetworkManager, BlueZ, UPower, and sysfs backlight files. Changes affecting compositor layout, focus, panels, or hardware adapters should also be verified live:

1. Read [docs/RECOVERY.md](RECOVERY.md) first.
2. From the stock bar, use `scripts/activate.sh --confirm --watchdog 30`.
3. Over an already-installed Floating Islands bar, use `scripts/branch-test.sh --arm 45` before `scripts/install.sh` and `omarchy restart shell`, then `scripts/branch-test.sh --restore` when done.
4. In PR descriptions, explicitly distinguish **automated/offscreen evidence** from **live Wayland/hardware evidence**.

## Current Verification Coverage (Live vs. Offscreen)

| Area | Live Wayland / Hardware Status | Automated / Offscreen Coverage |
|---|---|---|
| Core bar (islands, workspaces, title, clock, calendar, media, tooltips, hosted widgets, bottom placement, reduced motion, hot reload) | **Verified** on single display (1920×1080 @ 1.25), including a 24-hour supervised trial with unattended watchdog rollback and zero plugin errors | Full unit + QML + sandbox suite |
| Recovery (`rollback.sh` from TTY/minimal PATH, `activate.sh` watchdog, `branch-test.sh` timer restore) | **Verified** live (except real reboot with `islands-branch-restore-boot.service`, which is pending) | Full bubblewrap sandbox suite |
| Control Center (experimental, `bar.islands.controlCenter: false`): service tiles, Pipewire audio, Bluetooth toggle, Power Profiles (AC), built-in display brightness, keyboard navigation | **Partially verified** live (single display, built-in audio sink, Bluetooth adapter-retained path, AC power profiles, built-in `eDP-1` backlight) | Full unit + QML stub suite |
| **Known untested / open live gaps** | Multi-monitor & mixed-scale setups; suspend/resume; real reboot restore; physical Wi-Fi radio toggle; platform-rfkill Bluetooth adapter disappearance; battery-mode power profiles; external monitors (DDC/CI); real AT-SPI screen reader (Orca) | Stubbed where applicable; community testing welcome |
