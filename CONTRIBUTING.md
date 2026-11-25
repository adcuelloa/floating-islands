# Contributing to Floating Islands

Thank you for your interest in contributing to Floating Islands. This guide covers local setup, safe testing, and pull request expectations.

## Before a Big Change

Small bug fixes, tests, translations, and documentation improvements can go straight to a pull request.

For larger changes — new widgets, Control Center layout or navigation changes, new system adapters, or changes to widget hosting and focus behavior — open an issue or join the relevant [GitHub Discussion](docs/CONTROL_CENTER_RFC.md) first so we can align on the approach and Omarchy compatibility constraints.

Read [AGENTS.md](AGENTS.md) before modifying code; it states the project's non-negotiable architectural and safety rules.

## Development Setup

### Full local environment (Arch Linux / Omarchy)
To run every test stage locally, you need:
- Omarchy 4.5.0+ (`omarchy`, `omarchy-settings`)
- Quickshell 0.3.2+ and Qt 6 (`qt6-base`, `qt6-declarative`, `qt6-svg`, `qt6-wayland`)
- `nodejs`, `jq`, `bash`, `bubblewrap`

### Pure JS / docs contributions (any Linux / macOS)
You can run the pure JavaScript unit tests and privacy checks with only `node`, `bash`, and `git`:

```bash
node --test tests/unit/*.test.mjs
tests/privacy.sh
```

## Running Tests

Run the full isolated test suite (touches nothing outside `/tmp`):

```bash
tests/run-all.sh
```

Individual stages can also be run directly — see [docs/TESTING.md](docs/TESTING.md).

## Safe Live Desktop Testing & Rollback

Never edit `~/.config/omarchy/shell.json` by hand or test unverified changes directly on your daily bar without a recovery path. Read [docs/RECOVERY.md](docs/RECOVERY.md) first.

### Testing from the stock Omarchy bar (trial mode)

```bash
scripts/install.sh                        # Install plugin files only (does not activate)
scripts/activate.sh --check               # Pre-flight validation only
scripts/activate.sh --confirm --watchdog 30  # Trial for this login with automatic 30-minute rollback
```

To return to the stock bar at any time (including from a TTY via `Ctrl+Alt+F3`):

```bash
scripts/rollback.sh
```

### Testing a branch over an already-active Floating Islands bar

```bash
scripts/branch-test.sh --arm 45           # Snapshot current plugin + shell.json with 45-minute auto-restore
scripts/install.sh                        # Install the branch build under test
omarchy restart shell                     # Reload QML
# ... run supervised checks ...
scripts/branch-test.sh --restore          # Restore exact pre-test plugin + shell.json
```

If the shell fails to come back during a branch test, `scripts/rollback.sh` always restores the stock Omarchy bar from a TTY.

## Pull Request Guidelines

- **Language:** English for all code, comments, commits, docs, issues, and PR descriptions.
- **Scope:** Keep each PR focused on one logical change.
- **Commit titles:** Follow [Conventional Commits](https://www.conventionalcommits.org/) (e.g., `feat(clock): ...`, `fix(hosting): ...`, `docs: ...`, `test(qml): ...`). PRs are squash-merged into `main`.
- **Tests & evidence:**
  - Add or update unit (`tests/unit/`) and offscreen QML (`tests/qml/`) tests for behavioral changes.
  - Update `tests/contract/contract.tsv` if you use a new upstream Omarchy/Quickshell/Hyprland symbol.
  - State clearly in the PR description what was tested offscreen versus on a real Wayland desktop.
- **Translations:** Add any new user-facing string to all catalogs in `plugin/i18n/` (`en.json`, `es.json`, `ja.json`).
- **Privacy:** Ensure `tests/privacy.sh` passes and never include personal paths, usernames, hostnames, credentials, or unredacted desktop screenshots/logs.

## Review & CI Approval Workflow

- **Workflow approvals:** For security (the sandbox job prepares an ephemeral Ubuntu runner with AppArmor's distro `bwrap-userns-restrict` profile), GitHub Actions requires **manual maintainer approval before running workflows on all external contributor pull requests**. A maintainer will review the diff and approve the CI run.
- **Automated code review:** CodeRabbit provides advisory review comments on pull requests (it is not a blocking merge gate). Address valid findings or explain why a suggestion does not apply, then resolve review threads.
- **Merging:** Pull requests require passing `qa` and `sandbox` checks, resolved review conversations, an up-to-date branch against `main`, and squash merging.
