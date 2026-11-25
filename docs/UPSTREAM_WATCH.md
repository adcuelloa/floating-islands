# Upstream Watch and Compatibility Canary

Status: design. Implemented so far: the capability inventory
(`docs/upstream/capabilities.json`, validated by
`tests/unit/upstream-inventory.test.mjs`). The watcher and the canary are not
built yet.

Floating Islands runs inside Omarchy's shell. This document describes how the
project notices upstream changes, how it judges their impact on the bar, and
how it reports them. It does not use an AI service, a server or a daemon. It
never decides for maintainers.

## 1. How upstream is organised (verified 2026-11-24)

| Item | Value |
|---|---|
| Repository | `omacom/omarchy` |
| Default branch (trunk) | `quattro`, about 300 commits a week |
| Release branches | `vX-Y-Z` (e.g. `v4-5-0`, `v4-5-1`). Releases are cut here and are **not** ancestors of trunk. Fixes reach them through `backport/*` branches. |
| Next patch release | the highest `vX-Y-Z` branch without a matching tag (today `v4-5-1`) |
| Tags | `vX.Y.Z`. Prereleases are `vX.Y.Z-rcN`, flagged `prerelease` on the GitHub release. |
| Stale branches | `master`, `dev` and `rc` are not channels |
| Package channels | `pkgs.omarchy.org/{stable,rc,edge}/x86_64/omarchy.db`. A fourth channel, `dev`, links a git checkout. |
| Relevant paths | `shell/shell.qml`, `shell/services/Plugin*Api.qml`, `shell/services/PluginRegistry.qml`, `shell/Ui/{PluginBarApi,KeyboardPanel}.qml`, `shell/{Ui,Commons}/qmldir`, `shell/Commons/{Color,Style,ShellIpc,IpcRegistry}.qml`, `shell/plugins/**/manifest.json`, `shell/plugins/bar/widgets/*.manifest.json`, `config/omarchy/shell.json`, `bin/omarchy-{bar,shell,shell-config,plugin-*}`, `default/hypr/bindings/*.lua`, `default/hypr/helpers.lua`, `default/hypr/monitor-workspaces.lua` |

Branch names are never hardcoded:

- Each run reads the default branch from the API.
- Release branches and tags come from `git ls-remote`.
- If discovery yields no default branch or no release branch, the run fails
  loudly instead of guessing.

The GitHub compare API returns at most 300 files (`v4.5.0...quattro` hit the
limit). Change detection therefore uses a blobless clone and a local
`git diff`.

The first findings are in [`upstream/quattro-findings.md`](upstream/quattro-findings.md).

## 2. Capability inventory

`docs/upstream/capabilities.json` maps each upstream capability to its
Floating Islands integration:

- every upstream manifest id;
- the platform contracts: host, facade, shortcuts, IPC, theme, Hyprland state
  and runtime.

Each entry holds:

| Field | Meaning |
|---|---|
| `id`, `title`, `kind` | stable identifier (`omarchy.<id>` for manifests, `<area>.<name>` otherwise) |
| `origin` | `baseline` (ships in the supported Omarchy) or `detected` (seen only upstream: a finding, never an approved feature) |
| `upstream.ids/paths/api` | source references and the public API relied on |
| `depends_on` | other capabilities whose breakage reaches this one |
| `integration.current/intended` | `native`, `hosted`, `partial`, `delegated`, `planned`, `blocked`, `pending-review`, `not-applicable` |
| `placement.current/proposed/approval/rfc` | where it lives today, any proposal, `approved`/`open`/`not-applicable`, and the Control Center RFC question it belongs to |
| `compat.baseline/trunk/evidence` | `ok`/`broken`/`unknown`; on trunk also `changed` and `absent` |
| `contract_areas`, `fi_files` | links into `tests/contract/contract.tsv` and this repository |
| `blockers[]` | upstream limitation, reference and the tokens a watcher looks for |
| `issue` | Floating Islands issue once filed |
| `reviewed` | full SHA of the upstream revision a person last reviewed it against |

The validator enforces these invariants:

- Fields are exact, enums are closed, ids are unique, and every
  `depends_on` target exists.
- Every `reviewed` SHA is a recorded revision.
- Files and contract areas exist.
- Every manifest in the pinned Omarchy tree is inventoried, and every baseline
  path exists there.
- `detected` entries cannot carry an approved placement or a committed
  strategy.
- Anything tied to an RFC question stays `open`.
- An `approved` placement names where it ships and proposes nothing.

A manifest is not necessarily a visible desktop control. `kind` separates
widgets, panels and overlays from services and the host, which have no
surface of their own. Four fields stay distinct: `origin` records detection,
`integration.current` what ships, `integration.intended` and
`placement.proposed` what is proposed, and only `placement.approval:
approved` an accepted product design.

Only people edit this file, through pull requests. The product rule is part of
the file: one unified system-control entry point. Placement and navigation of
each widget stay open to community feedback.

## 3. Watcher

Workflow `upstream-watch.yml`:

- triggers: `schedule` (`17 */12 * * *`, minute offset to avoid the
  top-of-hour queue) and `workflow_dispatch` (inputs: `dry_run`, `mode`);
- `mode` is `incremental` or `reconcile`, plus a `reset_state` used only for
  bootstrap.

| Job | Permissions | Does |
|---|---|---|
| `inspect` | `contents: read` | discovers refs; clones blobless with `--no-checkout`; materialises the needed files with `git show`; runs the detectors; writes `report.json`; renders a preview to the step summary |
| `report` (skipped on `dry_run`) | `issues: write`, `contents: read` | validates `report.json`; plans and applies issue upserts; advances state last |

Workflow-level `permissions: {}`. Concurrency:
`group: upstream-watch, cancel-in-progress: false`, so runs are serialised.

### 3.1 Detectors (deterministic)

| | Detector | Emits |
|---|---|---|
| D1 | `check-contract.sh` (grep only) against the old and new trees; `--advisory` downgrades opt-in rows | `regression`, `restored`; confirmed |
| D2 | API surface of the files in §1: `property`/`signal`/`function` names, `qmldir` types, IPC handler targets and functions | `api-added`/`api-removed`/`api-changed` |
| D3 | `jq -S` diff of every manifest | widget/panel/service added or removed; `kinds`, `entryPoints` or capability fields changed |
| D4 | `# omarchy:` header lines of the shell CLI scripts | CLI added/removed/changed |
| D5 | `o.bind(...)` calls in `default/hypr/bindings/*.lua` | shortcut added/removed/changed |
| D6 | `.bar` subtree of the default `shell.json` | option added/removed, layout order changed |
| D7 | changed paths matched against the inventory's `upstream.paths` | `touched` (low), `unmapped` (new `shell/plugins/*`) |
| D8 | inventory `blockers[].watch` tokens in *added* diff lines | `possible-blocker-resolution`, always flagged uncertain |
| D9 | new tag or prerelease, new or removed release branch | `release` |

Severity is computed. A finding is `breaking` only when D1 fails a required
row, or when D2 removes a symbol that a contract row or an inventory
`upstream.api` names. Everything else is `review` at most. Semantic
classification is best effort. Every finding carries source evidence: SHA,
path, line and detector. Anything not confirmed is marked for manual review.
Commit messages are shown as context only. They never classify.

### 3.2 State

- **Store:** one issue titled `Upstream watch state`, label `upstream-state`,
  pinned by a maintainer. Its body holds
  `<!-- fi-upstream-state v1 {json} -->`:

  ```json
  {"schema":1,"repo":"<owner>/<repo>",
   "refs":{"quattro":{"processed":"<sha>","first_seen":{"<fp>":"<sha>"}}, "v4-5-1":{...}},
   "tags_seen":["v4.5.0"],"last_success":{"run_id":0,"at":"…"},"last_reconcile":"…"}
  ```

  It uses no `contents: write` and no `actions/cache`.
- **Strict validation:**
  - exactly one open issue with that label and title;
  - authored by `github-actions[bot]`;
  - exactly one marker block, JSON within 64 KB, the exact schema;
  - SHAs match `^[0-9a-f]{40}$`, and `repo` equals the current repository.
- **Missing state:** none found, or deleted. The run does not start from HEAD,
  which would skip changes. It reports the cumulative range from the
  human-reviewed `revisions` in the inventory, then creates the state issue as
  its last step.
- **Corrupt or ambiguous state:**
  - covers bad JSON, a wrong author, two state issues or a foreign `repo`;
  - the run fails closed: no issue writes, an error in the step summary;
  - a maintainer re-runs with `reset_state: from-inventory`.
- **Atomic advancement:**
  1. `report` records the state issue's `updated_at` when it reads it.
  2. It applies all upserts.
  3. It re-reads the state issue. If `updated_at` changed, it aborts without
     writing.
  4. Otherwise it writes the new cursors.

  The cursor never moves if fetching, analysis or any upsert failed.
- **Partial failures and retries:**
  - The plan (create, edit or comment, per fingerprint) is computed from the
    current issues on every attempt.
  - Actions already applied before a crash become no-ops on retry, because
    their fingerprint is present.
  - Every created issue carries `run=<run_id>` next to its marker, so a rare
    duplicate from list-after-create lag is identifiable.
  - Network calls retry 3 times with backoff and honour `Retry-After` and
    `x-ratelimit-reset`.
- **Non-fast-forward upstream:** `git merge-base --is-ancestor processed head`
  fails, or `processed` cannot be fetched.
  - The diff runs from the merge-base, or from the inventory baseline when no
    merge-base exists.
  - The run is labelled `history-rewrite` and every finding is marked
    uncertain.
  - The cursor moves to the new head only after reporting.
  - A vanished release branch yields `release-branch-gone`. Its cursor is
    kept, and other refs are unaffected.
- **Scheduler limits:**
  - Late or skipped scheduled runs lose nothing, because the diff is
    cursor-based.
  - GitHub disables schedules after 60 days without repository activity, and
    issue edits do not count as activity.
  - The state issue shows `last_success`, and `docs/TESTING.md` documents
    re-enabling.
  - There are no keep-alive commits.

### 3.3 Grouping, fingerprints, recurrence

- **Group** = capability id (or `release:<tag>`). At most one *open* bot issue
  per group carries `<!-- fi-upstream:group=<id> -->`. Several independent
  changes to one capability become separate rows of that issue, each with its
  own fingerprint.
- **Fingerprint** =
  `sha256(group | detector | subject | before-digest | after-digest | introducing-commit)`,
  truncated to 16 hex characters.
  - `subject` is the contract row, symbol, manifest id, shortcut or path.
  - The digests hash the normalised old and new text of that subject, or
    `absent`.
  - `introducing-commit` is the first commit in the range that changed the
    subject, found with `git log -S`/`-G` on that path. If history was
    rewritten, the head where it was first seen is used, kept in
    `state.first_seen`.
  - A fingerprint is stable across reruns and later commits. A removal that
    is restored and later removed again has a different introducing commit,
    so it reports again.
- **Limits:**
  - Two different semantic changes that leave identical text in a subject
    cannot be told apart.
  - One semantic change spread over several subjects shows as several rows.
  - Both cases are bounded, flagged for review, and closable by people.
- **Upsert rules:**
  1. Open issue for the group: edit its evidence table. Comment once, only
     when a new fingerprint appears.
  2. Closed issue that already lists the fingerprint: do nothing. A
     maintainer decided.
  3. Closed issue for the group, new fingerprint: open a **new** issue that
     links the closed one. A previously closed capability stays reportable.
     The bot never reopens, closes, locks, assigns or relabels.
  4. Nothing yet: create one.
- **Bounds:**
  - at most 10 creates or edits per run, spaced at least 1 s apart (secondary
    rate limits);
  - overflow goes into one `Upstream digest <date>` issue, so everything is
    still reported and the cursor may advance;
  - lookups use the paginated issues list (`--state all --label upstream`,
    bot author only), not the lagging search API.

### 3.4 Periodic reconciliation

A weekly `mode: reconcile` run, also available on dispatch, ignores the
cursor. It analyses trunk HEAD and release-line HEAD against the inventory's
`revisions` and reports:

- `inventory-drift`, where the inventory's `compat` claims disagree with D1/D2;
- every manifest id at HEAD missing from the inventory (as a `detected`
  finding);
- every open bot fingerprint that no longer reproduces, as a comment. The
  issue is never closed.

This catches anything a cursor bug or a skipped run missed.

### 3.5 Untrusted input

All upstream content is data:

- source files, commit messages, PR titles, release notes;
- branch and tag names, paths.

Handling:

- The watcher never executes upstream files, scripts or package hooks. It
  reads them with `git show`, `grep -F/-E`, `jq` and its own Node parsers.
- Untrusted strings never reach `${{ }}` expressions or shell interpolation.
  They travel in files and `--body-file`.
- Issue titles and labels are built only from inventory ids and an allowlist.
- Untrusted text is rendered only inside fenced code blocks.
  - The fence is longer than any backtick run in the text.
  - Text is capped at 200 characters per subject and 2 KB per release
    excerpt.
  - Control characters and bidi overrides (U+202A–U+202E, U+2066–U+2069) are
    stripped.
  - `<!--` is broken, so upstream text cannot forge a watcher marker. Markers
    are parsed only from the issue's leading marker block.
- Links are built from validated parts only:
  - SHA `^[0-9a-f]{40}$`;
  - path `^[A-Za-z0-9._/+-]+$`, no `..`;
  - ref names `^[A-Za-z0-9._/-]+$`.

  Upstream URLs are never copied.
- Upstream issue and PR numbers are written as code spans (`` `#19879` ``),
  and `@` handles stay inside code. Our issues therefore never notify upstream
  people and never create cross-reference backlinks upstream.

### 3.6 Artifact and schema validation

`report.json` is the only channel from `inspect` to `report`. It is downloaded
from the same run (`needs: inspect`).

`report` refuses it unless all of these hold:

- file size ≤ 1 MB, ≤ 500 findings, ≤ 50 evidence items per finding;
- schema version 1 and no unknown keys;
- every SHA, path and ref matches its pattern;
- every string respects its length cap;
- every label is in the allowlist;
- every `group` is an inventory id, `release:<tag>` or `digest`.

When canary results are attached, they come from another workflow run, read
through the API. They are accepted only if all of these hold:

- the workflow file is `upstream-canary.yml`;
- the run was on `main`, with a completed conclusion;
- the target SHA matches;
- the artifact is ≤ 256 KB;
- the content validates against the canary schema.

## 4. Advisory compatibility canary

Workflow `upstream-canary.yml`:

- triggers: `workflow_dispatch` and a daily `schedule`;
- never `pull_request`, never a required check;
- `ci.yml` and its pins are unchanged.

Targets come from the watcher's discovery: trunk HEAD, release-line HEAD and
the newest tag. The matrix runs with `fail-fast: false`.

Three levels, kept distinct in every report:

| Level | What runs | What it can show |
|---|---|---|
| **Static source** | `check-contract.sh --advisory`, the inventory reference checks and D2/D3 on the upstream tree. No upstream code executes. | an upstream symbol the bar uses is gone or changed |
| **Upstream source on the pinned runtime** | upstream `shell/`, `bin/`, `config/` and `default/hypr/` overlaid on the pinned container (pinned Quickshell, Qt, Arch archive); `tests/imports.sh`, `tests/lint.sh`, `tests/qml/run.sh`; sandbox tests with the upstream CLI | the bar's QML against that upstream QML. **Not** a compatibility certificate for a future package, which brings its own Quickshell and Qt. |
| **Packaged runtime** | the newer `omarchy`/`quickshell` from the rc or edge DB, signature-checked by pacman. `pacman -U --noscriptlet`; trees extracted from `omarchy-settings` as `bootstrap.sh` does | the closest automated approximation of a release. Still not a desktop. |

Outcomes, per target and per check, are written to `canary.json` and the step
summary:

| Outcome | Meaning | Job result |
|---|---|---|
| `PASS` | ran; all checks green, with counts matched by `.github/ci/counts.sh` | success |
| `FAIL` | confirmed failure with a log excerpt | failure |
| `UNAVAILABLE` | no package newer than the pin in that channel, or the ref is absent | success, shown as UNAVAILABLE, never as passed |
| `UNSUPPORTED` | upstream needs a runtime the image lacks, e.g. `tests/imports.sh` reports a module *not installed* rather than *not allowlisted* | success with a warning |
| `INFRA` | download, checksum, signature, AppArmor/bwrap preflight or timeout | failure, tagged INFRA, never filed as an upstream break |
| `MANUAL` | always listed: live Wayland, theme contrast, multi-monitor, hardware toggles, assistive technology | not applicable |

On 2026-11-24, every channel shipped `omarchy 4.5.0-3`. The packaged level is
therefore `UNAVAILABLE` for Omarchy. Only edge's `quickshell …-11` is a newer
runtime to try.

Isolation follows `ci.yml`:

- container job, `contents: read`, `persist-credentials: false`, no secrets;
- tests run as an unprivileged user;
- the level that executes upstream QML runs its tests with no network;
- no job of the canary has `issues: write`.

Pin bumps stay manual pull requests to `.github/ci/bootstrap.sh`.

## 5. Security summary

| Job | Token | Secrets | Runs upstream code |
|---|---|---|---|
| watch `inspect` | `contents: read` | none | no |
| watch `report` | `issues: write`, `contents: read` | none | no; reads only the validated artifact |
| canary | `contents: read` | none | upstream QML only, unprivileged, no network |
| `ci.yml` | unchanged | none | only sha-verified pinned packages |

The project also commits to:

- SHA-pinned actions (Dependabot groups them);
- `zizmor.yml` audits `.github/**`;
- no `pull_request_target`, no self-hosted runners, no GitHub App.

Labels (`upstream`, `compatibility`, `breaking-change`, `design-review`,
`upstream-state`; `enhancement` exists) and the state issue are created by a
maintainer. The workflow never creates labels or changes settings.

## 6. Test plan

| Layer | Test |
|---|---|
| Contract | `tests/contract/self-test.sh`: each simulated removal fails its own row only; first-party rule holds through a rename; `--advisory` downgrades only conditional rows |
| Inventory | `tests/unit/upstream-inventory.test.mjs` (in `tests/run-all.sh` and CI) |
| Detectors | fixture tree pairs, one per detector, with exact expected findings |
| Fingerprints | stable across SHAs and orderings; new subject means new fingerprint; removal, restore and removal gives two fingerprints |
| Upsert plan | pure `plan(issues, findings)` table tests: rules 1–4, closed-issue respect, cap and digest, retry after partial apply |
| State | valid, missing, corrupt, foreign author, two state issues, changed `updated_at`, non-ancestor cursor |
| Rendering | backtick runs, `@handles`, `#123`, `<!--` markers, bidi characters, oversized text, odd paths |
| Artifact | size and count caps, unknown keys, bad SHA, bad label |
| Workflows | `zizmor`; a `dry_run` dispatch renders to the step summary with the `report` job skipped |
| Canary | dispatch against `v4.5.0` (PASS), `quattro` (FAIL), a bogus ref (UNAVAILABLE), channel `rc` (UNAVAILABLE), a corrupted download (INFRA) |

No test touches `~/.config/omarchy`, the running shell or hardware.

## 7. Implementation order

1. **Contract precision** (`test/upstream-contract-precision`): one symbol per
   row, conditional rows, `--advisory`.
2. **Capability inventory** (this document,
   `docs/upstream/capabilities.json`, validator).
3. **Watcher, read-only:** the `inspect` job, D1–D9 as pure Node modules with
   fixture tests, `dry_run` only.
4. **Reporting:**
   - the `report` job, state issue and upsert plan;
   - first, a maintainer creates the labels and the state issue;
   - then the schedule is enabled.
5. **Canary:** static and pinned-runtime levels, dispatch-only first, then
   daily.
6. **Later:** the packaged-runtime level; weekly reconciliation; attaching
   canary results to reports.
