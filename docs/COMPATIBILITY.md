# Compatibility

## Verified environment

| Component | Version | How it was checked |
|---|---|---|
| Omarchy | 4.5.0-3 (CI pin; initially developed on 4.5.0rc2/rc3) | `pacman -Q`, `omarchy version`, CI `qa` & `sandbox` |
| Shell host | `omarchy-shell`, a single Quickshell process running `$OMARCHY_PATH/shell/shell.qml` | source |
| Quickshell | 0.3.2.r7.g2b4501a-1 | `quickshell --version`, CI `qa` |
| Qt | qt6-base 6.12.0, qt6-declarative 6.12.0 | `pacman -Q`, `qmltestrunner` banner, CI `qa` |
| Hyprland | 0.56.2, Lua configuration | `pacman -Q`, `default/hypr/*.lua` |
| Reference output | 1920×1080 at scale 1.25 → 1536×864 logical | `hyprctl monitors -j` |

These are the versions the contract was verified against. A different
version is not an error: the symbol checks below decide compatibility.

**Omarchy 4.5.0-3** (CI pin; previously checked on `4.5.0rc2`/`rc3`, Quickshell `0.3.2.r7.g2b4501a-1`): the full contract, isolated suite, and `activate.sh --check` pass. Shortcut bindings this bar relies on (`panel = "omarchy.clock"` and `"omarchy.elsewhen"`, `togglePanelAt right`, `shell toggle omarchy.weather`) are pinned in `tests/contract/contract.tsv`.

The experimental Control Center adds `Quickshell.Services.Pipewire`, `Quickshell.Networking`, `Quickshell.Bluetooth`, and `Quickshell.Services.UPower` to the allowlisted imports (`tests/imports.sh`). Wi-Fi and Bluetooth toggles invoke `nmcli radio wifi on|off` and `omarchy-bluetooth-power on|off` (fixed argument arrays, no shell) rather than writing properties directly because Quickshell 0.3.2's `setWifiEnabled` updates local state optimistically even on polkit refusal and BlueZ `Powered` does not persist across rfkill soft blocks.

## Around an Omarchy update

Nothing runs by itself. Use these steps with a persistent selection.

1. **Before updating**, note `omarchy version`, `quickshell --version` and
   `pacman -Q qt6-base`.
2. **After updating**, if any of them changed, run from the repository:
   - `scripts/activate.sh --check` (validate, contract, qmllint; changes
     nothing);
   - `tests/run-all.sh` (isolated).
3. **If either fails, or the bar misbehaves**, run `scripts/rollback.sh`
   (from a TTY if needed). It returns to the stock bar. Re-select later
   with `install.sh` and `activate.sh --confirm --persistent` once the
   contract passes again.

If the bar fails to load after an update, the shell itself falls back to
the stock bar (the load-error fallback in the contract). The selection stays
in `shell.json` until rollback.

## The upstream contract

`tests/contract/contract.tsv` lists every upstream symbol this bar uses, one
per line, with what breaks without it. `tests/contract/check-contract.sh`
checks them against the installed tree. They fall into these areas:

| Area | Covers |
|---|---|
| manifest, selection | `kind: "bar"`, `entryPoints.bar`, `bar.id`, `omarchy bar use/reset`, the validator's rules |
| settings | shell-side edits deep-copy the whole config (unknown keys survive); the scoped `mutateShellConfig`; the CLI's `NORMALIZE` |
| lifecycle | the plugin-bar `Loader`, the load-error fallback, rebuild on hot reload, publication as `shell.bar` |
| inject | `shell`, `manifest`, `barWidgetRegistry` and `barConfig` injection, and re-injection on reload |
| host | the bar members that the shell, notifications and IPC read |
| service | toggling `omarchy.menu`; entry facades for hosted widgets |
| widgets | `PluginBarApi` members and callbacks; registry snapshot shape; `KeyboardPanel`'s use of `barSizeFor` and click targets |
| theme | `Commons.Color` roles, `bar`, `popups` and `tooltip` groups; `Style.duration`, `easeOut`, `spacing.scale`, `fontScale`, `font.family`; live theme push |
| commons | `Util.execArgv`, `execDetached` and `wheelSteps`; `I18n.formatLocale`; `Translations`; `ShellIpc`; `ScreenMoveRemap` |
| hyprland | `o.workspaces.focus`, the `monitor-workspaces` state file, the `omarchy-bar` layer rules, the `bar-off` toggle and its IPC nudge |
| quickshell | `Region` with nested regions, `SystemClock`, `Scope`, `Variants`, `screens`, exclusive zone, layer-shell properties, Hyprland IPC types, `FileView` and `Process` |

The check is symbol-level on purpose. A checksum of the upstream sources would
fail on every unrelated edit. Each row checks one symbol: a regex alternation
may spell one dependency two ways, but never lists several symbols, because
such a row passes while one of them is gone.

Rows marked `F?`/`E?` are conditional: only an opt-in feature (the
experimental Control Center) uses them. They fail the check like any other
row. `check-contract.sh --advisory` reports them as `WARN` instead, for
checking newer upstream revisions; the supported baseline is never checked in
advisory mode.

`tests/contract/self-test.sh` proves both sides: unrelated upstream edits
pass, and simulated removals of symbols the bar uses each fail their own row
and only that row (including one facade callback, one palette role and one
Quickshell property on their own).

**QML imports** are checked separately. `tests/imports.sh` resolves every
import against what is installed, and limits imports to a declared supported
set:

- `QtQuick`, `QtQuick.Shapes`, `QtQuick.Effects`;
- `Quickshell`, `Quickshell.Wayland`, `Quickshell.Hyprland`, `Quickshell.Io`;
- `qs.Commons`, `qs.Ui`.

qmllint does not report an unknown module that contributes no used types,
so it cannot serve as the gate.

**qmllint** runs with `qs` mapped to the shell directory, as Quickshell does.
Its only findings are seven environment false positives, documented in
`tests/lint-allowlist.txt`. Omarchy's own sources produce the same ones:

- Quickshell registers `PanelWindow`'s concrete type at runtime, so qmllint
  reports a file whose root is a `PanelWindow` as "not creatable". It then
  cannot resolve that file's `margins` group.
- `Commons.Color` and `Commons.Style` hold their groups in `QtObject`
  properties whose members qmllint cannot see.

## Upstream capability inventory

`docs/upstream/capabilities.json` maps every Omarchy manifest and platform
contract to how this bar integrates it today, what is intended, where it is
placed, and its compatibility on the supported baseline and on upstream
trunk. `tests/unit/upstream-inventory.test.mjs` validates it. Findings against
newer upstream revisions are in `docs/upstream/`. The planned watcher and
canary are described in [UPSTREAM_WATCH.md](UPSTREAM_WATCH.md).

## Responsive tiers

Logical width decides the tier, not the physical panel. The prototype's 1700 px
threshold assumed CSS pixels. It would have placed a 1920 px panel at
1.25 scale, which is 1536 logical px, in the compact tier.

Tiers are measured at runtime (ARCHITECTURE.md, Geometry). The table below is
the unit-test fixture. Its widths are estimated from the prototype at the
default font size, assuming the planned right-hand islands with media
expanded:

| Output | Logical width | Tier | Title cap |
|---|---|---|---|
| 1920×1080 @1.0 | 1920 | full | 480 |
| 1920×1080 @1.25 | 1536 | full | 372 |
| 1920×1080 @1.5 | 1280 | compact | 240 |
| 1366×768 @1.0 | 1366 | compact | 240 |
| 1366×768 @1.25 | 1093 | compact | 171 |
| 2560×1440 @1.0 | 2560 | full | 480 |
| 2560×1440 @1.25 | 2048 | full | 480 |
| 2560×1440 @1.5 | 1707 | full | 458 |
| 2560×1440 @2.0 | 1280 | compact | 240 |
| 1024 logical | 1024 | minimal | — |

In this MVP the right side holds the hosted widgets, so live tiers will
differ from the fixture according to what the user hosts. The rule is the
same.

## Platform and Control Center Constraints

1. **Replacement bars are less trusted than the stock bar.** Hosted widgets
   get a service-less entry facade. They can update their own settings and
   summon their own panel, but a stock widget cannot summon another
   plugin's overlay. As a result:
   - `omarchy.network` loses its speed-test and Wi-Fi QR overlays;
   - `omarchy.monitor` loses its brightness OSD.

   Clones of `omarchy.audio`, `omarchy.media`, `omarchy.monitor` and
   `omarchy.network` keep the OSD they are allowed by `pluginCloneMaySummon`.
2. **No notification history API** for bar plugins; this blocks a native
   notification center (only Do Not Disturb is exposed).
3. **No panel-anchor redirection hook in `PluginBarApi`.** Stock widgets set
   `anchorItem: button` directly on their own `KeyboardPanel`, and `PluginBarApi`
   provides no hook (such as `bar.panelAnchorFor(owner)`) to relocate that anchor
   to a unified Control Center button. Invisible stacked buttons or pointer masks
   are forbidden because they break assistive technology and input boundaries.
4. **External monitors (DDC/CI):** Built-in display brightness uses kernel sysfs
   (`actual_brightness`) and `omarchy-brightness-display`; external monitor
   brightness is not currently supported.
5. **The shell's load-error fallback only catches load errors.** A bar that
   loads but misbehaves stays selected. `activate.sh` verifies the bar over
   IPC after activation, and rolls back if it does not report its surfaces.
6. **`omarchy bar move` and `omarchy bar set` go through the running shell**
   (`moveBarWidget`), not through `jq`. They keep `bar.islands` because the
   shell deep-copies the whole configuration. The contract checks that code;
   the sandbox cannot run it.
7. **Drag-to-reorder** exists in the stock bar only; layout changes go through
   `omarchy bar`. Tooltips are drawn on the bar surface by Floating Islands.
8. **Registry widget components can only be used through a `Loader`.**
   `createObject` on them fails from plugin JavaScript, so hosted widgets are
   injected after construction, as on the stock bar.
9. **IPC targets and hosted widgets after a hot reload:** IPC targets stay
   with the previous registration until the shell restarts, and switching the
   selected bar identity via hot reload (for example, from `omarchy.bar` or
   legacy `islands.bar` to `floating-islands`) can leave hosted status-island
   widgets inactive. `scripts/activate.sh` emits a concise advisory when the
   selected bar identity changes rather than forcing an automatic restart; run
   `omarchy restart shell` explicitly if hosted widgets do not appear or
   respond.
10. **Open upstream questions:** mixed-scale multi-monitor `KeyboardPanel`
    ordering, notification history API for bar plugins, and `PluginBarApi`
    anchor redirection for icon folding.

## Status island parity (hosted widgets)

| Widget | Under this bar | Gap and cause |
|---|---|---|
| Wi-Fi/network (`omarchy.network`) | Icon and panel work | Its speed-test and Wi-Fi QR overlays do not open. Replacement bars give widgets a service-less entry facade, and only *clones* of `omarchy.network` may summon `omarchy.speedtest` and `omarchy.wifiqr` (`pluginCloneMaySummon`). Upstream issue #13289 covers the facade |
| Display (`omarchy.monitor`) | Icon and panel work | Its brightness OSD does not appear; same cause (`omarchy.osd` is allowed only for clones) |
| Cloned audio widget | Works, including its volume OSD | A clone of `omarchy.audio` may summon `omarchy.osd` |
| Bluetooth, power, agents, keyboard layout, tray | Work | Tooltips are drawn by this bar (not yet verified live) |

**Supported remedy, not applied here.** Omarchy's own
`omarchy plugin clone omarchy.network` (and `omarchy.monitor`) makes a
user-owned clone. Clones are allowed those overlays under any bar, so this
restores them through a public command with no private interface. It changes
the user's plugin set, so it is left to the user. Otherwise the gaps stay
until #13289 is resolved upstream.

## Stock widgets outside the right section

The stock layout also places widgets in the centre. This bar draws the clock
and media itself and hosts the right section; the rest are not shown unless
asked for. The shell routes a named panel shortcut for a bar widget to the
active bar (`shell.bar.summonBarWidget`, `hideBarWidget`, `isBarWidgetOpen`;
toggle is `isOpen ? hide : summon`), so a widget that is not on this bar
cannot be summoned. `tests/contract/contract.tsv` (area `routes`) pins that
routing and the shortcuts below.

| Widget | Under this bar | Shortcut |
|---|---|---|
| Calendar (`omarchy.clock`) | Native calendar. `logic/Routes.js` maps the id to it: summon opens it on the focused output, hide closes it on every output, open while any output shows it | SUPER+CTRL+ALT+D works |
| World clock (`omarchy.elsewhen`) | Not shown by default. `extraHosted: ["omarchy.elsewhen"]` hosts the stock widget itself (one icon button) | SUPER+CTRL+ALT+E works once hosted |
| Weather (`omarchy.weather`) | Not shown by default. `extraHosted: ["omarchy.weather"]` hosts the stock widget (a short label) | SUPER+CTRL+ALT+W (`omarchy-notification-weather`) works once hosted |
| Indicators (`omarchy.indicators`) | Not shown | None depends on it; the states still change from menus and hotkeys |
| System update (`omarchy.system-update`) | Not shown | None depends on it; `omarchy update` stays in the menu |

**Visual constraints of `extraHosted`.** The widgets join the status island
after the right section, so the island grows by their width and the title
gets less room (the responsive tiers absorb it). The weather widget hides
itself until a forecast has loaded; until then it takes no room, and whether
its panel can open from a hidden button has not been checked live. Neither
widget has been looked at live in the islands yet.

**Not shown yet: design direction.** No replacement is built; both may later
live in compact indicators or the Control Center.

- *Indicators.* Only active states matter: Do Not Disturb, Night Light,
  stay-awake (idle inhibition) and screen recording, plus remote session and
  reminders. A small glyph row that takes no room while nothing is active,
  read from the first-party services a bar plugin may use (`omarchy.idle`,
  `omarchy.nightlight`, `omarchy.notifications`, `omarchy.remote-session`);
  states with no service (screen recording, passwordless sudo) need the
  stock widget hosted instead. A click opens the matching toggle.
- *System update.* A single dot or glyph that appears only while an update
  is available, with the version in its tooltip and `omarchy update` on a
  click. The stock widget already shows only while an update is available,
  so `extraHosted: ["omarchy.system-update"]` is close to this today (not
  checked live).
