pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Ui
import "Identity.js" as Identity
import "../geometry/Layout.mjs" as Layout
import "../adapters"
import "../widgets"
import "../components"

// The bar on one output. Like the stock bar's surface it spans its whole
// screen, transparent, reserving only `exclusiveZone` along its edge: Omarchy's
// KeyboardPanel maps its anchor through this window and assumes it covers the
// screen. Only the islands (and their reach to the screen edge) take input;
// every other pixel passes clicks through to what is below.
PanelWindow {
  id: surface

  required property var bar

  readonly property var theme: bar.theme
  readonly property var m: theme.m
  readonly property string edge: bar.position
  readonly property string screenName: screen ? String(screen.name || "") : ""
  // This output's backlight, read while the Control Center is enabled
  // (nothing for an output without one).
  readonly property BrightnessAdapter brightness: BrightnessAdapter {
    active: surface.bar.settings.controlCenter
    output: surface.screenName
  }
  readonly property real screenWidth: screen ? screen.width : 0
  readonly property real islandY: Layout.islandY(edge, height, m)
  readonly property var reach: Layout.buttonReach(edge, m)

  ScreenMoveRemap {
    id: remapGuard
    window: surface
  }

  visible: !remapGuard.remapping
  color: "transparent"
  surfaceFormat.opaque: false

  WlrLayershell.namespace: Identity.layerNamespace
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  exclusionMode: bar.barHidden ? ExclusionMode.Ignore : ExclusionMode.Normal
  exclusiveZone: bar.barSize

  anchors {
    top: surface.edge === "top"
    bottom: surface.edge === "bottom"
    left: true
    right: true
  }

  implicitHeight: screen ? screen.height : bar.barSize

  // Hidden (`omarchy toggle bar`) parks the surface past its edge rather than
  // unmapping it, so showing it again is only a margin change.
  margins {
    top: surface.bar.barHidden && surface.edge === "top" ? -surface.implicitHeight : 0
    bottom: surface.bar.barHidden && surface.edge === "bottom" ? -surface.implicitHeight : 0
  }

  WorkspacesAdapter {
    id: workspaceState
    screen: surface.screen
  }

  ActiveWindowAdapter {
    id: windowState
    screen: surface.screen
  }

  // ------------------------------------------------------------ tiers
  //
  // Measured, not looked up: each tier's fixed islands must fit beside the
  // clock (geometry/Layout.mjs). The hosted island and the left island do not
  // change between tiers; the clock does, and the title takes what is left.

  readonly property real leftWidth: launcher.implicitWidth
  readonly property real hostedWidth: hosted.empty ? 0 : hosted.implicitWidth
  // The media island is reserved at its expanded width whether or not
  // anything plays, so starting playback never changes the tier.
  function rightFor(forTier) {
    var media = bar.settings.showMedia ? mediaIsland.demandFor(forTier) : 0
    return hostedWidth + (media > 0 && hostedWidth > 0 ? m.groupGap : 0) + media
  }
  readonly property bool titleWanted: bar.settings.showTitle

  // Tier selection reserves the clock's expanded width (maxDemandFor) so
  // hovering the clock or opening the calendar never flips the tier under the
  // pointer, while titleMaxWidth uses the active width so the title island
  // reclaims idle space and yields cleanly when the clock expands.
  readonly property var demands: ({
    full: { center: clock.maxDemandFor("full"), leftFixed: leftWidth + m.groupGap, titleMin: titleWanted ? m.titleMin : 0, rightFixed: rightFor("full") },
    compact: { center: clock.maxDemandFor("compact"), leftFixed: leftWidth + m.groupGap, titleMin: titleWanted ? m.titleMin : 0, rightFixed: rightFor("compact") },
    minimal: { center: clock.maxDemandFor("minimal"), leftFixed: leftWidth, titleMin: 0, rightFixed: rightFor("minimal") }
  })

  property string autoTier: "full"
  readonly property string tier: bar.settings.tier === "auto" ? autoTier : bar.settings.tier

  function updateTier() {
    if (surface.screenWidth > 0) surface.autoTier = Layout.chooseTier(surface.screenWidth, surface.demands, surface.m, surface.autoTier)
  }

  onDemandsChanged: Qt.callLater(surface.updateTier)
  onScreenWidthChanged: Qt.callLater(surface.updateTier)

  readonly property real activeClockWidth: Math.max(clock.demandFor(tier), Math.ceil(clock.implicitWidth))
  readonly property real titleMaxWidth: titleWanted
    ? Layout.titleWidth(tier, screenWidth, { center: activeClockWidth, leftFixed: demands[tier].leftFixed }, m)
    : 0

  // -------------------------------------------------------------- islands

  Row {
    id: leftGroup

    x: surface.m.sideMargin
    y: surface.islandY
    spacing: surface.m.groupGap

    LauncherIsland {
      id: launcher

      theme: surface.theme
      workspaces: workspaceState
      strings: surface.bar.strings
      reach: surface.reach
      iconStyle: surface.bar.settings.launcherIcon
      onLauncherClicked: function(button) { surface.bar.launcherClicked(button) }
    }

    TitleIsland {
      id: title

      theme: surface.theme
      window: windowState
      strings: surface.bar.strings
      maximumWidth: surface.titleMaxWidth
      iconStyle: surface.bar.settings.titleIcon
    }
  }

  ClockIsland {
    id: clock

    theme: surface.theme
    strings: surface.bar.strings
    tier: surface.tier
    timeFormat: surface.bar.clockFormat
    bar: surface.bar.nativeBar
    localeTag: surface.bar.localeTag
    reach: surface.reach
    x: Math.round((surface.width - width) / 2)
    y: surface.islandY
    onCycleFormatRequested: surface.bar.cycleClockFormat()
    onTimezoneRequested: surface.bar.openTimezoneSelector()
  }

  // Anchored to the right edge: the media island grows toward the clock and
  // the hosted island never moves.
  Row {
    id: rightGroup

    x: surface.width - surface.m.sideMargin - width
    y: surface.islandY
    spacing: surface.m.groupGap

    MediaIsland {
      id: mediaIsland

      theme: surface.theme
      service: surface.bar.mediaService
      strings: surface.bar.strings
      tier: surface.tier
      equalizer: surface.bar.settings.mediaEqualizer
      reach: surface.reach
      // Hyprland's focused workspace, read without taking focus.
      focusKey: Hyprland.focusedWorkspace ? String(Hyprland.focusedWorkspace.id) : ""
    }

    HostedIsland {
      id: hosted

      theme: surface.theme
      entries: surface.bar.hostedEntries
      hosting: surface.bar.hosting
      registry: surface.bar.barWidgetRegistry
      screenName: surface.screenName
      leading: surface.bar.settings.controlCenter ? controlCenterEntry : null
    }
  }

  Component {
    id: controlCenterEntry

    ControlCenterButton {
      theme: surface.theme
      strings: surface.bar.strings
      bar: surface.bar.nativeBar
      services: surface.bar.controlCenterServices
      links: surface.bar.controlCenterLinks
      audioSink: surface.bar.audioOutput.sink
      audioPanelId: surface.bar.controlCenterAudioPanelId
      wifi: surface.bar.connectivity.wifi
      bluetooth: surface.bar.connectivity.bluetooth
      wifiPanelId: surface.bar.controlCenterWifiPanelId
      bluetoothPanelId: surface.bar.controlCenterBluetoothPanelId
      powerProfile: surface.bar.powerProfile
      brightness: surface.brightness
      summon: surface.bar.summonPanel
      reach: surface.reach
    }
  }

  // `floating-islands toggleControlCenter` (logic/ControlCenter.js ipcToggle).
  function toggleControlCenter() {
    var entry = hosted.leadingItem as ControlCenterButton
    if (!entry) return "disabled"
    entry.toggle()
    return surface.screenName
  }

  function toggleCalendar() {
    clock.toggle()
  }

  // The shell's summon/hide of omarchy.clock (logic/Routes.js).
  readonly property bool calendarOpened: clock.opened
  function openCalendar() {
    clock.open()
    return clock.opened
  }
  function closeCalendar() {
    clock.close()
  }

  function refreshClock() {
    clock.refresh()
  }

  function toggleMedia() {
    if (!mediaIsland.visible) return "no-media"
    mediaIsland.togglePinned()
    return mediaIsland.pinned ? "pinned" : "closed"
  }

  // A hosted widget's tooltip, when its target is on this surface.
  TooltipBubble {
    id: tooltip

    readonly property var target: surface.bar.tooltipTarget
    // QsWindow.window is Quickshell's window interface, not the PanelWindow
    // object; like the stock bar's sameWindow(), match by screen.
    readonly property var targetWindow: target && target.QsWindow ? target.QsWindow.window : null
    readonly property bool here: !!targetWindow && !!targetWindow.screen && String(targetWindow.screen.name || "") === surface.screenName

    theme: surface.theme
    text: surface.bar.tooltipText
    shown: surface.bar.tooltipShown && here
    surfaceWidth: surface.width
    anchorPoint: here ? target.mapToItem(null, target.width / 2, 0) : Qt.point(0, 0)
    // The same distance from the islands as every panel.
    y: surface.edge === "bottom"
      ? surface.islandY - height - surface.m.panelGap
      : surface.islandY + surface.m.islandHeight + surface.m.panelGap
  }

  // ------------------------------------------------------------ input mask

  component HitArea: Item {
    required property var island
    property real offsetX: 0

    readonly property var rect: island.visible && island.empty !== true
      ? Layout.hitRect({ x: offsetX + island.x, y: surface.islandY, width: island.width, height: island.height }, surface.edge, surface.height, surface.m)
      : ({ x: 0, y: 0, width: 0, height: 0 })

    x: rect.x
    y: rect.y
    width: rect.width
    height: rect.height
  }

  HitArea { id: launcherHit; island: launcher; offsetX: leftGroup.x }
  HitArea { id: titleHit; island: title; offsetX: leftGroup.x }
  HitArea { id: clockHit; island: clock }
  HitArea { id: mediaHit; island: mediaIsland; offsetX: rightGroup.x }
  HitArea { id: hostedHit; island: hosted; offsetX: rightGroup.x }

  mask: Region {
    Region { item: launcherHit }
    Region { item: titleHit }
    Region { item: clockHit }
    Region { item: mediaHit }
    Region { item: hostedHit }
  }

  // ------------------------------------------------------------ diagnostics

  // Per-slot state of the hosted island, for `floating-islands slots`.
  function describeSlots() { return hosted.describeSlots() }

  function describe() {
    function box(item) { return item.visible && item.empty !== true ? { x: item.x, y: item.y, width: item.width, height: item.height } : null }
    return {
      screen: surface.screenName,
      logicalWidth: surface.screenWidth,
      logicalHeight: surface.screen ? surface.screen.height : 0,
      tier: surface.tier,
      autoTier: surface.autoTier,
      exclusiveZone: surface.exclusiveZone,
      hidden: surface.bar.barHidden,
      titleMaxWidth: surface.titleMaxWidth,
      islands: {
        launcher: { x: leftGroup.x + launcher.x, y: launcher.y + surface.islandY, width: launcher.width, height: launcher.height },
        title: title.visible ? { x: leftGroup.x + title.x, y: surface.islandY, width: title.width, height: title.height } : null,
        clock: box(clock),
        media: mediaIsland.visible ? { x: rightGroup.x + mediaIsland.x, y: surface.islandY, width: mediaIsland.width, height: mediaIsland.height, state: mediaIsland.mediaState, expanded: mediaIsland.expanded, pinned: mediaIsland.pinned, previewing: mediaIsland.previewing } : null,
        hosted: hosted.empty ? null : { x: rightGroup.x + hosted.x, y: surface.islandY, width: hosted.width, height: hosted.height }
      },
      mediaState: mediaIsland.mediaState,
      calendarOpen: clock.opened,
      hitAreas: [launcherHit.rect, titleHit.rect, clockHit.rect, mediaHit.rect, hostedHit.rect]
    }
  }

  Component.onCompleted: {
    surface.bar.registerSurface(surface)
    surface.updateTier()
  }
  Component.onDestruction: surface.bar.unregisterSurface(surface)
}
