# Upstream trunk findings: `quattro` @ 65d3982b

> Issue drafts for the Floating Islands backlog. Not filed. Each one is
> self-contained so it can be copied into the public tracker as is.

| | |
|---|---|
| Upstream trunk | `omacom/omarchy` `quattro` @ `65d3982b3c435351d7d013674165c7c14b530226` (2026-11-24, unchanged at the time of writing) |
| Release line | `v4-5-1` @ `9fca57897c453bc248de207eeb4fbd0047b9c48b` (untagged) |
| Supported baseline | tag `v4.5.0` → `ac2690cd7be4f47e4a255f5e2e78d904d436b068`, package `omarchy 4.5.0-3`, `quickshell 0.3.2.r7.g2b4501a-1`, Qt 6.12.0 |
| Packages | stable, rc and edge all ship `omarchy 4.5.0-3`: none of this is released yet |

Compatibility matrix (static contract, `tests/contract/check-contract.sh` with
`OMARCHY_PATH` at each source tree; Quickshell rows use the pinned Quickshell):

| Target | Contract before (one row, many symbols) | Contract after (one symbol per row) |
|---|---|---|
| Installed baseline `omarchy 4.5.0-3` | 212 / 212 | 241 / 241 |
| `v4.5.0` (`ac2690cd…`) | 212 / 212 | 241 / 241 |
| `v4-5-1` (`9fca5789…`) | 212 / 212 | 241 / 241 |
| `quattro` (`65d3982b…`) | 208 / 212 | 237 / 241 |

The 4 trunk failures differ between the two contracts:

- The old contract missed `_setCenterHoverRevealSuppressed`. It also flagged
  the `__isFirstParty` rename, which was only a textual change.
- The revised contract catches the former and accepts the latter.

These results are static only. Nothing below was run against a live trunk
shell.

Priorities: **P1** breaks the bar or a hard invariant once released; **P2**
degrades a feature silently; **P3** contract bookkeeping.

---

## 1. `ScreenMoveRemap` removed from `qs.Ui`

**Priority:** P1 · **Labels:** `upstream`, `compatibility`, `breaking-change`

**Upstream evidence**

- Commit `796e169ab4deb64016ae73069c7d558b6007d710` (2026-11-01), "Stop the bar
  blinking after a monitor move, and polish the display panel" (`#17229`).
- `shell/Ui/ScreenMoveRemap.qml` deleted, its `shell/Ui/qmldir` line removed,
  and its uses dropped from `shell/plugins/bar/Bar.qml`,
  `shell/plugins/background/Background.qml` and `shell/plugins/dock/DockWindow.qml`.
- Rationale in the commit: Hyprland 0.57 moves layer surfaces with their
  monitor, so the unmap/remap only made the bar blink.

**Affected Floating Islands code:** `plugin/core/BarSurface.qml:37`
(`ScreenMoveRemap { … }`).

**Confirmed (static):** contract row `commons` "output-move guard" fails on
trunk; the type is gone from `qs.Ui`.

**Inferred (runtime, not run):**

- `BarSurface.qml` would fail to compile with "ScreenMoveRemap is not a type".
  The bar would not load, and the shell's load-error fallback would show the
  stock bar.
- Hard invariants hold: the stock bar comes back. But Floating Islands would be
  unusable on that Omarchy.

**Backward-compatible adaptation (not implemented):**

- The remap is only needed on Hyprland < 0.57, and the supported baseline ships
  0.56.2.
- Options:
  - (a) Load the remap through a `Loader` whose `source` is resolved only when
    `qs.Ui` still exports it. Qt has no static check for an optional import,
    so this needs a small probe component.
  - (b) Copy the 43-line remap into `plugin/core/`. It only uses Quickshell
    and Hyprland types, both already allowlisted. Check the licence first, see
    `docs/LICENSING.md`.
  - (c) Drop it once the supported baseline requires Hyprland ≥ 0.57.
- (b) is the smallest change that works on both.

**Timing:** must land before the first Omarchy release that contains
`796e169a`. Watch `v4-5-1` and new `vX-Y-Z` branches: it is not in `v4-5-1`
today.

---

## 2. Monitor-workspaces state moved to `omarchy/monitors/workspaces`

**Priority:** P2 · **Labels:** `upstream`, `compatibility`

**Upstream evidence**

- Commit `9dbd12dd2062bb0a1d9bcc776057a338c4f91add` (2026-10-31), "Show one
  display at a time in the display panel, with a layout map" (`#17159`).
- `default/hypr/monitor-workspaces.lua`: `STATE_DIR` moves from
  `state_home .. "/omarchy"` to `state_home .. "/omarchy/monitors"`, and
  `STATE_FILE` becomes `/workspaces` (was `/monitor-workspaces`).
- Migration `migrations/1793461630.sh` **moves** `monitor-workspaces` and
  `monitor-workspaces-merged` into `monitors/`. After the update the old path
  no longer exists.

**Affected Floating Islands code:**

- `plugin/adapters/WorkspacesAdapter.qml:57`: the `FileView` path is
  `…/omarchy/monitor-workspaces`.
- `plugin/logic/Workspaces.js`: `parseBlocks`.

**Confirmed (static):** contract row `hyprland` "per-monitor workspace blocks"
fails on trunk.

**Inferred (runtime, not run):**

- `onLoadFailed` sets `blocks = {}`. Per-monitor workspace numbering silently
  falls back to the single-monitor layout.
- Single-monitor users see no difference.
- Multi-monitor users see the wrong dots and a wrong click target. Clicks go
  through `o.workspaces.focus`, which still exists.

**Backward-compatible adaptation (not implemented):** read the new path first
and fall back to the old one. Both can be watched with two `FileView`s, or with
one `FileView` whose path flips on `onLoadFailed`. The parser does not change
if the block format is unchanged: confirm this from `monitor-workspaces.lua` at
adoption. Add a contract row for the new path in the same change.

**Timing:** together with finding 1, before the release that ships `9dbd12dd`.

---

## 3. Numbered bar shortcuts moved to `panel_at` global shortcuts

**Priority:** P3 · **Labels:** `upstream`, `compatibility`, `design-review`

**Upstream evidence**

- Commit `c455e521` (2026-11-23), "Move remaining shell hotkeys onto Hyprland
  global shortcuts" (`#19879`).
- `default/hypr/bindings/utilities.lua` now binds `SUPER + CTRL + code:10..18`
  to `{ panel_at = "right:N" }` instead of the
  `"omarchy-shell -q shell togglePanelAt right " .. panel` command.
- `default/hypr/helpers.lua:123-125` maps `panel_at` to the global shortcut
  `omarchy:panelAt.right:N`. If that shortcut is not registered, it falls back
  to the same `togglePanelAt` command.
- `shell/shell.qml` `runShortcut` (`kind === "panelAt"`) and
  `togglePanelAt` (line 2084) both still resolve the widget through
  `shell.bar.panelWidgetIdAt(section, index)`.

**Affected Floating Islands code:**

- `plugin/core/WidgetHosting.qml` (`panelWidgetIdAt`, right-section numbering).
- `plugin/Bar.qml` host members.

**Confirmed (static):** contract row `routes` "SUPER+CTRL+1..9 count the right
section" fails on trunk. The fixed string in `utilities.lua` is gone.

**Semantic review:** the dependency survives.

- Both trunk paths end in `Bar.panelWidgetIdAt`, which the `host` row still
  checks.
- The change is a moved dispatch path, not a removed capability. Expected
  runtime impact: none.
- Not verified live: the `GlobalShortcut` path needs a Hyprland with global
  shortcut support.

**Related upstream change:** the default `config/omarchy/shell.json` swaps
`omarchy.audio` and `omarchy.network` in `bar.layout.right`. With the stock
layout, `SUPER+CTRL+3` and `SUPER+CTRL+4` swap targets. This is upstream
behaviour, and the bar follows it.

**Adaptation (not implemented):** none in code. When a release ships it,
replace the row with rows that follow the new chain. These rows can only exist
once the baseline contains it:

- `{ panel_at = "right:" .. panel }` in `utilities.lua`;
- `value.panel_at` → `togglePanelAt` in `helpers.lua`;
- `entry.kind === "panelAt"` → `panelWidgetIdAt` in `shell.qml`.

The row is kept failing on trunk on purpose: it records that the chain the
contract verifies has moved.

**Timing:** contract update at baseline adoption. No user-facing change.

---

## 4. `PluginBarApi._setCenterHoverRevealSuppressed` removed

**Priority:** P2 · **Labels:** `upstream`, `compatibility`, `breaking-change`

**Upstream evidence:** `shell/Ui/PluginBarApi.qml`, `v4.5.0..quattro`.

- Removed: `property bool centerSectionRevealHeld`,
  `_centerHoverRevealSuppressed`, `centerHoverRevealSuppressed`,
  `property var _setCenterHoverRevealSuppressed` and
  `function setCenterHoverRevealSuppressed(value)`.
- Introducing commit: `c149addc2e32512a18d627ba7c183b24a04374a2` (2026-11-12),
  "Reveal hidden indicators only when hovering their own block" (`#18524`).
  It is not in `v4.5.0`.

**Affected Floating Islands code:** `plugin/core/WidgetHosting.qml`.

- Line 62: passes `_setCenterHoverRevealSuppressed` as an initial property in
  `createObject`.
- Lines 84-88: `callbackNames`.
- Line 96: `retire()` assigns `null` to every name in `callbackNames`.

**Confirmed (static):** with the revised contract, row `widgets` "facade
callback _setCenterHoverRevealSuppressed" fails on trunk. The previous
contract passed it, because its one alternation row matched any of the 13
callbacks.

**Confirmed (Qt 6.12.0 probe, offscreen, not the bar itself):**

- `createObject` with an unknown initial property creates the object and
  silently ignores that key.
- Assigning an unknown property from JavaScript throws
  `Error: Cannot assign to non-existent property "…"`.

**Inferred (runtime, not run):**

- Hosting works.
- On bar teardown (a hot reload, a bar swap or a shell restart), `retire()`
  throws on the last callback name.
- After the throw, `activePopout = null` and `clickTargets = []` are skipped
  for that facade. The `Component.onDestruction` loop stops, so the remaining
  facades are not retired.
- Hosted widgets that outlive the bar may then call back into it, and the
  thrown error is logged.

**Backward-compatible adaptation (not implemented):** in `retire()`, assign
only when `name in api`. Optionally build `callbackNames` from the facade's
own properties. Both work on both versions. Add a QML test with a facade stub
that lacks the property.

**Timing:** P2, but cheap and version-independent. It can land as soon as it
is accepted.

---

## 5. First-party identification (`__isFirstParty`): no issue

Reviewed, not semantically relevant.

- Commit `0810fdb9` (2026-11-24, `#19961`) reframes the manifest scan stream.
- `manifest.__isFirstParty` is still set only from the scan's
  `===firstparty::…===` header: `kind === "firstparty"`, local renamed from
  `currentKind`.
- Trunk additionally rejects first-party manifests outside `firstPartyDir`.
  That makes the first-party flag stricter, not looser.
- The contract row now accepts either local name and still fails if the flag
  is taken from anything else, for example from a plugin's own manifest
  (self-test case).
