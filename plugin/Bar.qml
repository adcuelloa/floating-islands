pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons as Commons
import "core/Identity.js" as Identity
import "geometry/Layout.js" as Layout
import "logic/Settings.js" as Settings
import "logic/Trial.js" as Trial
import "logic/Calendar.js" as Calendar
import "logic/Routes.js" as Routes
import "logic/ControlCenter.js" as ControlCenter
import Quickshell.Hyprland
import "core"
import "theme"
import "adapters"

// Entry point of the Floating Islands bar, an Omarchy `kind: "bar"` plugin.
//
// omarchy-shell loads this file when shell.json's `bar.id` names this plugin,
// sets the injected properties below (shell.qml configureBar), and publishes
// the object as its active bar: notifications, panels and the shell's IPC read
// the host-contract properties further down. Selecting another bar, or a load
// error, unloads it and the stock bar returns.
Item {
  id: root

  // --------------------------------------------- injected by omarchy-shell
  property string omarchyPath: ""
  // A capability-scoped PluginShellApi, not the shell itself.
  property var shell: null
  property var manifest: null
  // A detached snapshot of the bar-widget catalogue.
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  // shell.json's `bar` subtree, replaced on every reload.
  property var barConfig: ({})

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : Identity.fallbackPluginId
  readonly property var settings: Settings.read(barConfig, Identity.settingsKey)
  readonly property var hostedEntries: Settings.hostedEntries(barConfig, settings)
  readonly property var publicLayout: JSON.parse(JSON.stringify(barConfig && barConfig.layout ? barConfig.layout : {}))
  // The `locale` setting, or the Omarchy language.
  readonly property string localeTag: Calendar.resolveLocale(settings.locale, Commons.I18n.formatLocale)

  // Omarchy's media service proxy. The shell offers it to bar plugins; null
  // when the media service is disabled.
  readonly property var mediaService: settings.showMedia && shell && typeof shell.firstPartyServiceFor === "function"
    ? shell.firstPartyServiceFor("omarchy.media") : null

  // The Control Center's services: the first-party proxies the shell offers
  // bar plugins (null where it offers none), read only while it is enabled.
  readonly property var controlCenterServices: {
    var out = ({})
    if (!settings.controlCenter || !shell || typeof shell.firstPartyServiceFor !== "function") return out
    for (var i = 0; i < ControlCenter.TILES.length; i++) {
      var tile = ControlCenter.TILES[i]
      out[tile.key] = shell.firstPartyServiceFor(tile.service) || null
    }
    return out
  }
  // Links to the full panels of the hosted widgets that have one.
  readonly property var controlCenterLinks: settings.controlCenter
    ? ControlCenter.links(root.hosting.panelIds(false), barWidgetRegistry) : []
  // The default audio output, followed while the Control Center is enabled.
  readonly property AudioOutput audioOutput: AudioOutput { active: root.settings.controlCenter }
  readonly property string controlCenterAudioPanelId: settings.controlCenter
    ? ControlCenter.audioPanelId(root.hosting.panelIds(false), barWidgetRegistry) : ""
  // Wi-Fi and Bluetooth, read while the Control Center is enabled.
  readonly property Connectivity connectivity: Connectivity { active: root.settings.controlCenter }
  // The power profile, read while the Control Center is enabled.
  readonly property PowerProfileAdapter powerProfile: PowerProfileAdapter { active: root.settings.controlCenter }
  readonly property string controlCenterWifiPanelId: settings.controlCenter
    ? ControlCenter.panelId("wifi", root.hosting.panelIds(false)) : ""
  readonly property string controlCenterBluetoothPanelId: settings.controlCenter
    ? ControlCenter.panelId("bluetooth", root.hosting.panelIds(false)) : ""
  // Opens a hosted widget's panel through the same routing as the shell's summon.
  readonly property var summonPanel: function(id) { return Routes.summon(id, root.focusedSurface(), root.hosting) }

  // The facade this bar's own panels (the calendar) coordinate through, so
  // they take part in the one-panel-at-a-time rule with hosted widgets.
  property var nativeBar: null
  Component.onCompleted: root.nativeBar = root.hosting.facadeFor(root.pluginId)

  property Theme theme: Theme {
    density: root.settings.density
    edge: root.position
  }

  readonly property Commons.Translations strings: Commons.Translations {
    directory: Qt.resolvedUrl("i18n")
  }

  // ---------------------------------------------------------- trial mode
  // A trial started by scripts/activate.sh is bound to the Hyprland instance
  // it began in. Loaded in any other instance, the bar deselects itself and
  // the stock bar comes back (logic/Trial.js).

  readonly property bool staleTrial: Trial.isStale(settings.trialInstance, Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE"))
  property bool trialEnded: false

  function endStaleTrial() {
    if (!root.staleTrial || root.trialEnded || !root.shell || typeof root.shell.mutateShellConfig !== "function") return
    root.trialEnded = true
    console.warn(root.pluginId + ": trial belongs to another session; returning to the stock bar")
    var id = root.pluginId
    root.shell.mutateShellConfig(function(config) { Trial.endTrial(config.bar, id, Identity.settingsKey) })
  }

  onStaleTrialChanged: Qt.callLater(root.endStaleTrial)
  onShellChanged: Qt.callLater(root.endStaleTrial)

  // ------------------------------------------------------- host contract
  // Read by omarchy-shell and its plugins through PluginBarStateApi and
  // shell.bar: toasts and panels clear the bar by barSizeFor().

  readonly property string position: Layout.normalizeEdge(barConfig ? barConfig.position : "top")
  readonly property bool vertical: false
  readonly property bool barHidden: hiddenWatch.hidden
  // What Hyprland reserves: the screen edge to the islands' far edge.
  readonly property int barSize: Layout.exclusiveZone(theme.m)
  // What panels and toasts are told the bar measures. They add Style.gapsOut,
  // which follows Hyprland's gaps, so this keeps them panelGap from the islands
  // with gaps on or off (geometry/Layout.js panelBarSize).
  readonly property int panelBarSize: Layout.panelBarSize(theme.m, Commons.Style.gapsOut)
  readonly property string fontFamily: Commons.Style.font.family
  readonly property var screenBarSizes: {
    var sizes = ({})
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) sizes[screens[i].name] = root.panelBarSize
    return sizes
  }

  function barSizeFor(screenName) {
    return root.panelBarSize
  }

  function summonBarWidget(pluginId) { return Routes.summon(pluginId, root.focusedSurface(), root.hosting) }
  function hideBarWidget(pluginId) { return Routes.hide(pluginId, root.surfaces, root.hosting) }
  function isBarWidgetOpen(pluginId) { return Routes.isOpen(pluginId, root.surfaces, root.hosting) }
  function panelWidgetIdAt(section, index) { return root.hosting.panelIdAt(section, index) }

  // `omarchy-shell shell debugBarGeometry`
  function focusedSurface() {
    var focused = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    for (var i = 0; i < root.surfaces.length; i++) if (root.surfaces[i].screenName === focused) return root.surfaces[i]
    return root.surfaces.length > 0 ? root.surfaces[0] : null
  }

  function debugBarGeometry() {
    return root.surfaces.map(function(surface) { return surface.describe() })
  }

  // ------------------------------------------------------------ actions

  // Left: the Omarchy menu. Right: a terminal, as the stock launcher does.
  function launcherClicked(button) {
    if (button === Qt.RightButton) {
      Commons.Util.execArgv(["xdg-terminal-exec"])
      return
    }
    var payload = JSON.stringify({ menu: "root" })
    var toggled = root.shell && typeof root.shell.toggle === "function" && root.shell.toggle("omarchy.menu", payload)
    if (!toggled) Commons.Util.execArgv(["omarchy-shell", "shell", "toggle", "omarchy.menu", payload])
  }

  // ------------------------------------------------------------ tooltips
  // Hosted widgets ask through their facade; the surface the target is on
  // draws it. Shown after the pointer rests 400 ms, as on the stock bar.

  property var tooltipTarget: null
  property string tooltipText: ""
  property bool tooltipShown: false

  function showTooltip(target, text) {
    var clean = String(text || "").replace(/[\u0000-\u001f\u007f]+/g, " ").trim().slice(0, 300)
    if (!target || !clean) return root.hideTooltip(root.tooltipTarget)
    if (target !== root.tooltipTarget) console.info(root.pluginId + ": tooltip requested")
    root.tooltipTarget = target
    root.tooltipText = clean
    if (!root.tooltipShown) tooltipDelay.restart()
  }

  function hideTooltip(target) {
    if (target && target !== root.tooltipTarget) return
    tooltipDelay.stop()
    root.tooltipShown = false
    root.tooltipTarget = null
  }

  Timer {
    id: tooltipDelay
    interval: 400
    onTriggered: root.tooltipShown = root.tooltipTarget !== null
  }

  // ------------------------------------------------------------ surfaces

  property var surfaces: []

  function registerSurface(surface) {
    if (root.surfaces.indexOf(surface) === -1) root.surfaces = root.surfaces.concat([surface])
  }

  function unregisterSurface(surface) {
    root.surfaces = root.surfaces.filter(function(item) { return item !== surface })
  }

  BarHiddenWatch {
    id: hiddenWatch
  }

  readonly property WidgetHosting hosting: WidgetHosting {
    bar: root
    unnumbered: Settings.unnumberedIds(root.hostedEntries)
  }

  Variants {
    // Nothing is drawn once a stale trial has handed back to the stock bar.
    model: root.trialEnded ? [] : Quickshell.screens

    delegate: Component {
      BarSurface {
        required property var modelData

        screen: modelData
        bar: root
      }
    }
  }

  // `omarchy toggle bar` nudges whichever bar is active after flipping the flag.
  Commons.ShellIpc {
    target: "omarchy.bar"

    function syncHidden(): void {
      hiddenWatch.probe()
    }
  }

  Commons.ShellIpc {
    target: Identity.ipcTarget

    function ping(): string {
      return "ok"
    }

    function geometry(): string {
      return JSON.stringify(root.debugBarGeometry())
    }

    // Each hosted slot's registry entry and Loader state, for diagnostics.
    function slots(): string {
      return JSON.stringify(root.surfaces.map(function(surface) { return surface.describeSlots() }))
    }

    // The last tooltip request from a hosted widget, for diagnostics.
    function tooltip(): string {
      return JSON.stringify({ requested: root.tooltipTarget !== null, shown: root.tooltipShown, text: root.tooltipText })
    }

    // The calendar on the focused output (for a hotkey).
    function toggleCalendar(): string {
      var target = root.focusedSurface()
      if (!target) return "no-surface"
      target.toggleCalendar()
      return target.screenName
    }

    // The Control Center on the focused output (for a hotkey); "disabled"
    // while bar.islands.controlCenter is off.
    function toggleControlCenter(): string {
      return ControlCenter.ipcToggle(root.settings.controlCenter, root.focusedSurface())
    }

    // Pins or unpins the media controls on the focused output (for a hotkey).
    function toggleMedia(): string {
      var target = root.focusedSurface()
      if (!target) return "no-surface"
      return target.toggleMedia()
    }
  }
}
