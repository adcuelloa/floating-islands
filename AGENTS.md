# AGENTS.md

Floating Islands is a native `kind: "bar"` plugin for the Omarchy shell, written in QML and pure JavaScript. It runs inside `omarchy-shell` (Quickshell) and adds no background daemon or separate process.

**Read this file before changing code.** It defines the architectural invariants, compatibility boundaries, and verification gates every contribution must respect.

## Hard Invariants

Violating any rule below is a bug regardless of the feature benefit. Stop and raise an issue if a task appears to require an exception.

1. **Plugin only — never fork or modify Omarchy.**
   Never edit `/usr/share/omarchy`, system services, Hyprland user config, or unrelated plugins. Interact only through Omarchy's public plugin contracts (`PluginShellApi`, `PluginBarApi`, `KeyboardPanel`, `qs.Commons`, `qs.Ui`) and documented CLI commands.
2. **Never break hosted widgets, anchors, shortcuts, or third-party plugins.**
   Stock and third-party widgets hosted in `HostedIsland` must keep their live lifecycle, panel anchoring, `SUPER+CTRL+1..9` numbered shortcuts, `SUPER+CTRL+ALT+*` named shortcuts, and one-panel-at-a-time handover (`WidgetHosting`). Never use invisible stacked buttons, pointer-mask hacks, or synthetic click forwarding to hide hosted widgets. Never remove an existing hosted widget before its native replacement has verified functional parity or an explicitly accepted fallback.
3. **Never steal focus or swallow application input on the bar surface.**
   `BarSurface` (`PanelWindow`) takes no keyboard focus and sets no focus grab. Keyboard-interactive popouts (`CalendarPanel`, `ControlCenterPanel`) must use Omarchy's `KeyboardPanel` so focus is scoped strictly while the panel is open and Escape / outside clicks dismiss cleanly.
4. **Event-driven state, observed truth only.**
   Read live state from Quickshell services, D-Bus/Pipewire/BlueZ/UPower signals, or kernel file watchers (`FileView`). Do not add polling timers where event signals exist. Never assume a hardware or service toggle succeeded from a process exit code alone — reflect the observed state, show pending/failure states honestly, and serialize external commands.
5. **Safe subprocess execution.**
   Every `Quickshell.Io.Process` call must pass a fixed argument array with no shell interpolation (`sh -c` with dynamic input is forbidden). Guard against hung commands with bounded timeouts.
6. **Theme tokens and reduced motion.**
   Use `plugin/theme/Theme.qml` tokens bound to `Commons.Color` and `Commons.Style` — no hard-coded colors. Route all animations through `Style.duration` so disabling Omarchy animations results in zero motion. Maintain readable contrast across dark and light Omarchy themes.
7. **Full keyboard accessibility and i18n parity.**
   Interactive panels must support keyboard navigation (Tab between groups, arrows within grids, slider keys, Escape to go back/close), show focus rings only after keyboard use, and expose accurate `Accessible` roles, names, and descriptions. Any new user-facing string must be added to all catalogs under `plugin/i18n/` (`en.json`, `es.json`, `ja.json`) in the same PR.
8. **Safe desktop testing and atomic configuration.**
   Automated tests must never touch the user's real `~/.config/omarchy`, running shell, radios, brightness, or power profiles. Live desktop trials must use `scripts/activate.sh` or `scripts/branch-test.sh` with a watchdog/restore snapshot, and `scripts/rollback.sh` must always remain self-contained (bash, `jq`, coreutils) so it works from a TTY.

## Architecture Map

- `plugin/geometry/Layout.mjs`, `plugin/logic/ClockFormat.mjs`: Native ECMAScript modules (`.mjs`) with JSDoc contracts, executed directly by Qt/QML and Node (`tests/unit/`) and type-checked via `tsconfig.qml.json`.
- `plugin/logic/*.js`, `plugin/theme/Palette.js`, `plugin/theme/Icons.js`: Legacy `.pragma library` pure JS modules loaded in Node via `tests/unit/qmljs.mjs`. Keep pure logic out of QML views.
- `plugin/adapters/*.qml`: Only layer allowed to touch Hyprland, Pipewire, Networking, Bluetooth, UPower, or `FileView`/`Process`.
- `plugin/core/`: `BarSurface.qml`, `WidgetHosting.qml`, `HostedBarApi.qml`, `Facades.js`, `Identity.js`.
- `plugin/widgets/` & `plugin/components/`: Views taking `theme` and adapters by injection so `tests/qml/` can drive them offscreen with stubs.
- `tests/contract/contract.tsv`: Symbol-level upstream Omarchy/Quickshell/Hyprland compatibility contract. Update it whenever a new upstream symbol or import is used.

## Validation Gates

Install the dev-only TypeScript tooling once before running the suite locally (never required to install or run the plugin):

```bash
pnpm install --frozen-lockfile --ignore-scripts
```

Run the full isolated suite before opening or updating a PR:

```bash
tests/run-all.sh
```

This runs:
1. `omarchy-plugin-validate` (manifest & structure)
2. `tests/imports.sh` (allowlisted QML imports and single-line static relative `.mjs` imports)
3. `tests/lint.sh` (`qmllint` with documented allowlist in `tests/lint-allowlist.txt`)
4. `tests/contract/check-contract.sh` and `tests/contract/self-test.sh`
5. `node --test tests/unit/*.test.mjs` (pure JS unit tests)
6. `tests/typecheck.sh` (strict TypeScript `checkJs` via `tsc --noEmit` + isolated negative checks)
7. `tests/qml/run.sh` (offscreen `qmltestrunner`, fails on unexpected stderr/warnings)
8. `tests/scripts/isolated.sh tests/scripts/sandbox.test.sh` (bubblewrap-isolated install/activate/rollback/branch-test checks)
9. `tests/privacy.sh` (blocks personal usernames, paths, hostnames, emails, or key-shaped strings)

Report clearly in PR descriptions which behavior was verified by automated/offscreen tests versus live Wayland/hardware trials.

## Conventions

- **Language:** Write all code, comments, commit messages, docs, issues, and PRs in English.
- **Language & typing policy:**
  - Typed QML for presentation and native bindings (`plugin/widgets/`, `plugin/components/`, `plugin/core/`, `plugin/adapters/`).
  - Native `.mjs` with JSDoc and strict TypeScript `checkJs` (`tsconfig.qml.json`) for Qt-executed pure logic (`plugin/**/*.mjs`).
  - TypeScript (or strictly checked `.mjs`) for new Node tooling and tests where practical (`tsconfig.node.json`).
  - Legacy QML JavaScript (`.js` / `.pragma library`) retained only where Qt/Quickshell compatibility requires it.
  - Self-contained Bash for installation and recovery (`scripts/`), with zero Node.js/pnpm/TypeScript runtime dependency.
  - Migrate incrementally as modules are touched rather than performing repository-wide conversions.
- **Commits & PRs:** Use Conventional Commits (`feat(scope): ...`, `fix(scope): ...`, `docs: ...`, `test(scope): ...`, `ci: ...`). Keep PRs focused on one logical change.
- **Documentation:** Update relevant docs (`docs/COMPATIBILITY.md`, `docs/DECISIONS.md`, `docs/TESTING.md`, `README.md`) when behavior, settings, or upstream contracts change.
