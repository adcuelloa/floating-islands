# Architecture

## Where the bar sits

`omarchy-shell` is one long-running Quickshell process. It reads `bar.id`
from `~/.config/omarchy/shell.json`, loads that plugin's `Bar.qml` through an
asynchronous `Loader`, and injects six properties:

- `shell`: a capability-scoped `PluginShellApi`, not the shell itself;
- `manifest`;
- `barWidgetRegistry`: a detached snapshot of the bar-widget catalogue;
- `pluginRegistry`;
- `barConfig`: the `bar` subtree, re-injected whenever `shell.json` reloads;
- `omarchyPath`.

The shell then publishes the object as `shell.bar`. Notifications, panels and
IPC read the host-contract properties listed below. When the plugin fails to
load, the shell falls back to its stock bar. A hot reload of plugin code
destroys and rebuilds the bar, so the bar keeps no state in memory that
`shell.json` does not also hold.

This bar adds no process, service or daemon. It reads Hyprland state through
Quickshell, and acts through `hyprctl dispatch` with the same expressions the
stock widgets use. Menus and panels are reached through the scoped shell API.

## Components

```
Bar.qml ─ host contract, settings, trial mode, IPC
 ├─ Theme (theme/Theme.qml)       tokens bound to Commons.Color / Commons.Style
 ├─ WidgetHosting (core/)         facades, popout coordinator, panel lookups
 ├─ BarHiddenWatch (adapters/)    `omarchy toggle bar`
 └─ Variants over Quickshell.screens
     └─ BarSurface (core/)        one PanelWindow per output
         ├─ WorkspacesAdapter     Hyprland workspaces for this output
         ├─ ActiveWindowAdapter   the window this output shows
         ├─ LauncherIsland        launcher | workspaces (dots)
         ├─ TitleIsland           icon + elided title (the elastic island)
         ├─ ClockIsland           time, date, weekday by tier
         ├─ HostedIsland          registry widgets via PluginBarApi facades
         └─ HitArea × 4 → mask    input only where the islands are
```

Logic that can be pure is pure: `geometry/Layout.mjs` and the files in
`logic/` and `theme/` (`ClockFormat.mjs`, `Palette.js`, `Icons.js`). Native
`.mjs` modules are imported directly by both QML and Node unit tests (validated
with strict TypeScript `checkJs` in development); legacy `.pragma library` `.js`
modules are still loaded via `tests/unit/qmljs.mjs`. Views take a `theme` object
and adapters by injection, so the QML tests drive them with stubs. Only
`adapters/` and `core/BarSurface.qml` touch Quickshell's compositor types.

## Host contract

What `Bar.qml` exposes, and who reads it:

| Member | Reader |
|---|---|
| `barHidden`, `barSize`, `screenBarSizes`, `fontFamily`, `position` | `PluginBarStateApi` (plugins that place windows), notifications |
| `barSizeFor(screen)` | notification toasts, `KeyboardPanel` |
| `summonBarWidget`, `hideBarWidget`, `isBarWidgetOpen` | `omarchy-shell shell summon/hide/toggle` for hosted panels |
| `panelWidgetIdAt(section, n)` | `omarchy-shell shell togglePanelAt right N` hotkeys |
| `debugBarGeometry()` | `omarchy-shell shell debugBarGeometry` (also used by `activate.sh`) |

`barSize` is the full reserved thickness: gap 10 + island 40 = 50 at the
default scale. Hosted widgets instead see a `barSize` of 32 (the island's
inner height) through their facade, which is what they size their buttons
to. `barSizeFor()` still reports 50, so their panels open below the islands
(see DECISIONS.md, D6).

## Geometry

- **Surface.** Each output gets a layer-shell `PanelWindow` that spans its
  screen and is transparent, on the `Top` layer, under the `omarchy-bar`
  namespace (Omarchy's layer rules apply). It never takes keyboard focus,
  and reserves an explicit `exclusiveZone` of `gap + island height`. Spanning
  the screen is required: `KeyboardPanel` maps its anchor through the bar
  window and assumes the window covers the screen.
- **Input mask.** A union of one rectangle per visible island. Each extends
  to the anchored screen edge, 5 px past the island's inner edge, and 3 px
  sideways (`Layout.hitRect`). The rest of the surface passes clicks through.
  Each `IslandButton` stretches its own pointer area by the same amount, so a
  flick to the screen edge lands.
- **Tiers.** Computed per output from measured widths, never from fixed
  screen-width thresholds. Each side of the centred clock has a budget:
  `W/2 − clock/2 − 16 − 12`. Both the left fixed part plus the title's
  minimum and the right part must fit within it. The richest tier that fits
  wins. Returning to a richer tier needs 24 px of slack (hysteresis). The
  title takes what is left of its side, up to 480 px in full and 240 px in
  compact. The clock's width in each tier comes from `TextMetrics`, so a tier
  is measured before it is drawn.
- **Bottom placement.** Every position is derived from the edge
  (`Layout.islandY`, `hitRect`, `buttonReach`, anchors, margins). Setting
  `bar.position` to `bottom` flips the bar. This has not yet been checked
  on a live desktop.

## Theme

`Theme.qml` binds rather than copies. The design's roles map onto Omarchy's
palette:

| Design role | Source |
|---|---|
| foreground | `Color.bar.text` |
| muted | `Color.muted` |
| accent | `Color.accent` |
| danger | `Color.urgent` |
| background | `Color.background` |
| surface | `Color.bar.background` lifted 4.5 % toward the foreground |
| raised, faint | mixed from the roles above |
| hover, pressed, border, track | the foreground at 8 %, 14 %, 10 % and 16 % |
| accent-on text | whichever of background and foreground contrasts more with the accent |

Durations go through `Style.duration`, which returns 0 when animations are off.

## Widget hosting

For each id in `bar.layout.right`, or in `bar.islands.hosted` if that is set,
`HostedIsland` loads the widget's `Component` from the registry snapshot. It
injects `fixedEdge`, `bar`, `moduleName` and `settings`, as the stock bar does
for third-party widgets.

`bar` is a `HostedBarApi`: Omarchy's own `PluginBarApi` plus `barSizeFor()`.
Each facade gets a service-less entry shell from
`shell.pluginShellForBarEntry`, the same one the stock bar gives replacement
bars. `WidgetHosting` keeps one popout open at a time and tracks which plugin
owns each popout and click target, so no widget is handed another's objects.

Widgets the bar draws itself (menu, workspaces, clock, active window, spacer)
are never hosted. Custom `command` and `qml` modules are skipped.

## Experimental Control Center Adapters

While `bar.islands.controlCenter` is `false` (default), Control Center adapters remain inactive and run no commands or service watchers. When enabled:

- **First-party services** (`omarchy.nightlight`, `omarchy.idle`, `omarchy.notifications`): bound directly through `shell.firstPartyServiceFor(...)` with no local shadow state.
- **Audio** (`adapters/AudioOutput.qml`): tracks `Pipewire.defaultAudioSink` via `PwObjectTracker`; writes volume/mute directly and observes readback.
- **Connectivity** (`adapters/Connectivity.qml`): reads `Quickshell.Networking` and `Quickshell.Bluetooth` signals. Radio changes run serialized, fixed-argument `Quickshell.Io.Process` commands (`nmcli radio wifi on|off`, `omarchy-bluetooth-power on|off`) with 20 s command timeouts and read-only `rfkill --json --output TYPE,SOFT,HARD` fallback when platform switches remove adapters from BlueZ.
- **Power profiles** (`adapters/PowerProfileAdapter.qml`): observes `Quickshell.Services.UPower.PowerProfiles` reactively and persists selection through Omarchy's profile helper.
- **Built-in display brightness** (`adapters/BrightnessAdapter.qml`): uses separate read and watch `FileView` instances on sysfs `actual_brightness` (avoiding polling and Quickshell 0.3.2 watcher-rebuild pitfalls) and serializes bounded percent writes to `omarchy-brightness-display --no-osd --monitor <output> <N>%`, confirming via observed readback.

## Upstream Contract Map (`$OMARCHY_PATH`)

| Contract | Upstream Path |
|---|---|
| Bar selection, fallback, injection & scoped shell | `shell/shell.qml`, `shell/services/PluginShellApi.qml` |
| Bar state & widget catalogue | `shell/services/PluginBarStateApi.qml`, `shell/services/PluginBarWidgetRegistryApi.qml` |
| Widget facade & stock bar hosting | `shell/Ui/PluginBarApi.qml`, `shell/plugins/bar/Bar.qml` |
| Keyboard-interactive panels | `shell/Ui/KeyboardPanel.qml` |
| Theme tokens | `shell/Commons/Color.qml`, `shell/Commons/Style.qml` |
| CLI & atomic config writes | `bin/omarchy-bar`, `bin/omarchy-shell-config` |

## Trial mode

`scripts/activate.sh` records the current `HYPRLAND_INSTANCE_SIGNATURE` as
`bar.islands.trialInstance`. In any other Hyprland instance, the bar calls the
scoped `shell.mutateShellConfig` (allowed for bar plugins) to deselect itself
and drop the marker, then draws nothing, and the stock bar returns. A trial
therefore ends at the next login or compositor restart, even without
anyone running the rollback script. `--persistent` skips the marker.
