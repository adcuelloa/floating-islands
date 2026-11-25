# Security Policy

## Supported Versions

Floating Islands is in pre-v1.0 development. Security fixes are applied to the `main` branch.

| Version | Supported |
|---|---|
| `main` (pre-v1.0) | Yes |
| Older commits / snapshots | No |

## Reporting a Vulnerability

**Do not report security vulnerabilities in public GitHub issues or discussions.**

Use GitHub's **Private Vulnerability Reporting** feature on this repository (**Security → Advisories → Report a vulnerability**).

Please include:
- A clear description of the vulnerability and its impact.
- Steps to reproduce or a minimal proof of concept.
- Your Omarchy, Quickshell, Qt, and Hyprland versions (redacting any personal paths or credentials).

We aim to acknowledge reports within 7 days and coordinate a fix before public disclosure.

## Security Boundaries of This Project

Floating Islands runs inside the user's `omarchy-shell` session and interacts with desktop configuration and system helpers. Reports are especially welcome for issues involving:

- **Subprocess execution:** Any shell injection, untrusted argument interpolation, or unsafe `PATH` handling in QML adapters (`plugin/adapters/`) or shell scripts (`scripts/`).
- **Configuration & recovery safety:** Unsafe temporary files, symlink attacks, or non-atomic writes in `scripts/install.sh`, `scripts/activate.sh`, `scripts/branch-test.sh`, or `scripts/rollback.sh` (including `~/.local/state/islands-branch-test` and `~/.config/omarchy/shell.json`).
- **Focus & input boundaries:** Unexpected focus grabs or input interception on the Wayland bar surface.
- **CI / supply chain:** GitHub Actions workflow permission escalation, unpinned actions, or unsafe handling of external pull requests.
