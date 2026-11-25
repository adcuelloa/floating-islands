import QtQuick
import "../components"
import "../theme/Icons.js" as Icons
import "../logic/ControlCenter.js" as Model

// A Wi-Fi or Bluetooth tile. It shows only what the provider observes
// (adapters/Connectivity.qml). A press asks for the opposite state and the
// tile reads "pending" until the observed state matches; if the command
// fails, or the state has not changed after confirmTimeout, it reads
// "failed" and keeps showing the observed state. Further presses are
// ignored while a request is pending. The radio's device may vanish and
// return while its command runs (rfkill, re-enumeration), so a request
// survives that until the command exits. The arrow button opens the full panel.
Item {
  id: root

  required property var theme
  required property var strings
  // "wifi" or "bluetooth".
  required property string kind
  // { available, blocked, on, connected, detail, count, request(on, done),
  // refresh() }, or null.
  property var provider: null
  property string panelId: ""
  // Longer than the adapter's command limit, so a hung command reports as
  // its own failure first.
  property int confirmTimeout: 25000
  property bool keyboardShown: false

  signal panelRequested(string id)

  readonly property bool available: !!provider && provider.available === true && provider.blocked !== true
  readonly property bool on: !!provider && provider.on === true
  // The state asked for and not yet observed (null when nothing is asked).
  property var pending: null
  // True while the provider's command runs.
  property bool asking: false
  property bool failed: false
  readonly property string status: Model.radioStatus(provider, pending !== null, failed)
  readonly property string label: strings.t("controlCenter." + kind)
  readonly property string statusText: status === "connected" && provider.detail ? provider.detail
    : strings.t("controlCenter." + (status === "pending" ? "switching" : status))
  readonly property real s: theme.m.scale

  // The focusable controls, in order, for the view's arrow keys.
  function controls() {
    var out = root.available ? [toggle] : []
    if (more.visible) out.push(more)
    return out
  }

  function activate() {
    if (!root.available || root.pending !== null) return
    var target = !root.on
    root.failed = false
    root.pending = target
    root.asking = true
    confirm.restart()
    // The callback can arrive after this tile is gone (the panel rebuilt).
    var life = root.life
    var asked = root.provider.request(target, function(ok) {
      if (!life.alive) return
      root.asking = false
      if (root.pending === null) return
      if (!ok) root.fail()
      else root.settle()
    })
    if (!asked) { root.asking = false; root.fail() }
  }

  function fail() {
    root.pending = null
    root.failed = true
    confirm.stop()
  }

  // Done once the state asked for is observed and the command has exited.
  function settle() {
    if (root.pending !== null && !root.asking && root.on === root.pending) {
      root.pending = null
      confirm.stop()
    }
  }

  readonly property var life: ({ alive: true })
  Component.onDestruction: root.life.alive = false

  onOnChanged: { root.settle(); if (root.pending === null) root.failed = false }
  // The radio went away or behind its hardware switch with no command
  // running: nothing asked still applies.
  onAvailableChanged: if (!root.available && !root.asking) { root.pending = null; root.failed = false; confirm.stop() }

  Timer {
    id: confirm
    interval: root.confirmTimeout
    onTriggered: if (root.pending !== null) root.fail()
  }

  implicitWidth: Math.round(150 * s)
  // From the content, so a large font grows the tile instead of clipping it.
  implicitHeight: Math.max(Math.round(56 * s), radioText.implicitHeight + 2 * Math.round(8 * s))

  Rectangle {
    id: toggle

    readonly property bool lit: root.status === "on" || root.status === "connected"
    readonly property color ink: lit ? root.theme.accentForeground : (root.available ? root.theme.foreground : root.theme.muted)

    anchors.fill: parent
    radius: Math.round(10 * root.s)
    color: lit ? root.theme.accent : (pointer.containsMouse && root.available ? root.theme.hover : root.theme.surface)
    border.width: activeFocus && root.keyboardShown ? Math.max(1, Math.round(1.5 * root.s)) : 1
    border.color: activeFocus && root.keyboardShown && !lit ? root.theme.accent : root.theme.border
    opacity: root.available ? 1 : 0.55
    // Disabled when unavailable: Qt then drops its focus and skips it on Tab.
    enabled: root.available
    activeFocusOnTab: true

    Accessible.role: Accessible.CheckBox
    Accessible.checkable: root.available
    Accessible.checked: root.on
    Accessible.name: root.label
    Accessible.description: root.statusText
    Accessible.onPressAction: root.activate()
    Accessible.onToggleAction: root.activate()

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.activate()
        event.accepted = true
      }
    }

    StrokeIcon {
      id: icon
      anchors.left: parent.left
      anchors.leftMargin: Math.round(10 * root.s)
      anchors.verticalCenter: parent.verticalCenter
      icon: Icons[root.kind]
      size: Math.round(20 * root.s)
      color: toggle.ink
    }

    Column {
      id: radioText

      anchors.left: icon.right
      anchors.right: parent.right
      anchors.leftMargin: Math.round(8 * root.s)
      // From the button's own condition, not `visible`: that reads false
      // while the page is hidden, and the reserved status height must not
      // change with the page.
      anchors.rightMargin: root.panelId !== "" ? more.width + Math.round(10 * root.s) : Math.round(6 * root.s)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Math.round(2 * root.s)

      Text {
        objectName: "radioLabel"
        width: parent.width
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: root.label
        color: toggle.ink
        font.family: root.theme.textFamily
        font.pixelSize: Math.round(13 * root.theme.fontScale)
        font.weight: Font.DemiBold
      }

      // A network's own name is no status: it keeps to one line and may
      // still be shortened, so connecting never changes the tile's height.
      ControlCenterStatus {
        objectName: "radioStatus"
        width: parent.width
        statuses: ["on", "off", "connected", "switching", "failed", "blocked", "unavailable"]
          .map(function(k) { return root.strings.t("controlCenter." + k) })
        maximumLineCount: root.provider && root.statusText === root.provider.detail ? 1 : 3
        elide: Text.ElideRight
        text: root.statusText
        color: toggle.lit ? root.theme.accentForeground : (root.status === "failed" ? root.theme.dangerText : root.theme.secondaryText)
        font.family: root.theme.textFamily
        font.pixelSize: Math.round(11 * root.theme.fontScale)
      }
    }

    // The focus ring on a lit tile: the accent ring would vanish into the
    // fill, and a dark one on the edge into the panel, so it is drawn inside.
    Rectangle {
      objectName: "litFocusRing"
      anchors.fill: parent
      anchors.margins: Math.round(3 * root.s)
      radius: Math.max(0, parent.radius - Math.round(3 * root.s))
      color: "transparent"
      border.width: Math.max(1, Math.round(1.5 * root.s))
      border.color: root.theme.accentForeground
      visible: toggle.activeFocus && root.keyboardShown && toggle.lit
    }

    MouseArea {
      id: pointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.activate()
    }
  }

  // Opens the full panel. A sibling of the toggle, so it stays usable
  // while the radio is unavailable.
  IslandButton {
    id: more

    anchors.right: parent.right
    anchors.rightMargin: Math.round(4 * root.s)
    anchors.verticalCenter: parent.verticalCenter
    visible: root.panelId !== ""
    theme: root.theme
    minimumWidth: Math.round(28 * root.s)
    horizontalPadding: 0
    implicitHeight: Math.round(28 * root.s)
    active: activeFocus && root.keyboardShown
    // Hidden when no panel is hosted; Qt skips invisible items on Tab.
    activeFocusOnTab: true
    accessibleName: root.strings.t("controlCenter.more." + root.kind)
    onClicked: function(button) { if (button === Qt.LeftButton) root.panelRequested(root.panelId) }
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.panelRequested(root.panelId)
        event.accepted = true
      }
    }

    StrokeIcon {
      icon: Icons.chevron
      size: Math.round(16 * root.s)
      color: toggle.ink
    }
  }
}
