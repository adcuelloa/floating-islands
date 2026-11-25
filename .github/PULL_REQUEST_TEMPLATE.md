## Summary

- What changed and why.
- Related issue / RFC: `#`

## Verification

State clearly what was verified by automated/offscreen tests versus a live Wayland desktop:

- [ ] `tests/run-all.sh` passes locally (or note which stages ran if not on Omarchy/Arch)
- [ ] `tests/privacy.sh` passes (no personal paths, usernames, hostnames, emails, or credentials)
- [ ] Live Wayland verification (if applicable): specify monitor/scale setup and confirm clean rollback/restore via `scripts/branch-test.sh` or `scripts/rollback.sh`

## Checklist

- [ ] Followed the invariants in `AGENTS.md` (no Omarchy modifications, no bar focus grabs, Theme.qml tokens, reduced motion)
- [ ] Updated `tests/contract/contract.tsv` if new upstream Omarchy/Quickshell/Hyprland symbols are used
- [ ] Updated all `plugin/i18n/*.json` catalogs (`en`, `es`, `ja`) if user-facing strings changed
- [ ] Updated relevant documentation (`README.md`, `docs/`)
