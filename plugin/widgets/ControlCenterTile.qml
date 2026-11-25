import QtQuick
import "../components"
import "../theme/Icons.js" as Icons
import "../logic/ControlCenter.js" as Model

// One quick toggle. It shows only what its Omarchy service reports: a press
// asks the service and the tile reads "pending" until the service's state
// changes; if it has not changed after confirmTimeout, it reads "failed".
// No proxy (the bar was not given the service) reads "unavailable".
Rectangle {
  id: root

  required property var theme
  required property var strings
  required property string key
  // The service's first-party proxy, or null.
  property var proxy: null
  property int confirmTimeout: 3000
  property bool keyboardShown: false

  readonly property bool available: proxy !== null && proxy !== undefined
  readonly property bool on: Model.isOn(key, proxy)
  // The state asked for and not yet reported (null when nothing is asked).
  property var pending: null
  property bool failed: false
  readonly property string status: Model.status(available, on, pending !== null, failed)
  readonly property string label: strings.t("controlCenter." + key)
  readonly property string statusText: strings.t("controlCenter." + status)
  readonly property real s: theme.m.scale

  function activate() {
    if (!root.available || root.pending !== null) return
    var target = !root.on
    root.failed = false
    if (!Model.request(root.key, root.proxy, target)) {
      root.failed = true
      return
    }
    // A service that applies the change at once has already reported it.
    if (root.on === target) return
    root.pending = target
    confirm.restart()
  }

  onOnChanged: {
    if (root.pending !== null && root.on === root.pending) {
      root.pending = null
      confirm.stop()
    }
    root.failed = false
  }

  Timer {
    id: confirm
    interval: root.confirmTimeout
    onTriggered: if (root.pending !== null) { root.pending = null; root.failed = true }
  }

  implicitWidth: Math.round(96 * s)
  // From the content: the label may take two lines (long translations, a
  // large font); the view gives every tile in a row the tallest height.
  implicitHeight: Math.max(Math.round(72 * s), tileContent.implicitHeight + 2 * Math.round(10 * s))
  radius: Math.round(10 * s)
  color: root.status === "on" ? root.theme.accent : (pointer.containsMouse && root.available ? root.theme.hover : root.theme.surface)
  border.width: root.activeFocus && root.keyboardShown ? Math.max(1, Math.round(1.5 * s)) : 1
  border.color: root.activeFocus && root.keyboardShown && root.status !== "on" ? root.theme.accent : root.theme.border
  opacity: root.available ? 1 : 0.55
  activeFocusOnTab: root.available

  readonly property color ink: root.status === "on" ? root.theme.accentForeground : (root.available ? root.theme.foreground : root.theme.muted)

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

  Column {
    id: tileContent

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Math.round(10 * root.s)
    anchors.rightMargin: Math.round(10 * root.s)
    spacing: Math.round(4 * root.s)

    StrokeIcon {
      icon: Icons[root.key]
      size: Math.round(20 * root.s)
      color: root.ink
    }

    Text {
      objectName: "tileLabel"
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
      text: root.label
      color: root.ink
      font.family: root.theme.textFamily
      font.pixelSize: Math.round(13 * root.theme.fontScale)
      font.weight: Font.DemiBold
    }

    ControlCenterStatus {
      objectName: "tileStatus"
      width: parent.width
      statuses: ["on", "off", "pending", "failed", "unavailable"].map(function(k) { return root.strings.t("controlCenter." + k) })
      text: root.statusText
      color: root.status === "on" ? root.theme.accentForeground : (root.status === "failed" ? root.theme.dangerText : root.theme.secondaryText)
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
    visible: root.activeFocus && root.keyboardShown && root.status === "on"
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.activate()
  }
}
