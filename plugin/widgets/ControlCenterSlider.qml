import QtQuick
import "../logic/ControlCenter.js" as Model

// A horizontal 0-1 slider in the islands' style. It shows `value` (set from
// outside, never kept here) and emits moved() with the value asked for:
// pointer drag or click, Left/Down and Right/Up by a step, Page keys by two,
// Home and End to the ends.
Item {
  id: root

  required property var theme
  property real value: 0
  property bool keyboardShown: false
  property string accessibleName: ""
  property string valueText: ""

  signal moved(real value)

  readonly property real s: theme.m.scale
  readonly property real shown: Model.clampVolume(value)

  function ask(v) { if (root.enabled) root.moved(Model.clampVolume(v)) }

  implicitHeight: Math.round(28 * s)
  // Disabled (no device), Qt drops its focus and skips it on Tab.
  activeFocusOnTab: true
  opacity: root.enabled ? 1 : 0.55

  Accessible.role: Accessible.Slider
  Accessible.name: root.accessibleName
  Accessible.description: root.valueText
  Accessible.onIncreaseAction: root.ask(root.shown + Model.VOLUME_STEP)
  Accessible.onDecreaseAction: root.ask(root.shown - Model.VOLUME_STEP)

  Keys.onPressed: function(event) {
    var mirrored = LayoutMirroring.enabled
    var step = Model.VOLUME_STEP
    var delta = 0
    if (event.key === Qt.Key_Right) delta = mirrored ? -step : step
    else if (event.key === Qt.Key_Left) delta = mirrored ? step : -step
    else if (event.key === Qt.Key_PageUp) delta = 2 * step
    else if (event.key === Qt.Key_PageDown) delta = -2 * step
    else if (event.key === Qt.Key_Home) { root.ask(0); event.accepted = true; return }
    else if (event.key === Qt.Key_End) { root.ask(1); event.accepted = true; return }
    if (delta === 0) return
    root.ask(root.shown + delta)
    event.accepted = true
  }

  Rectangle {
    id: track

    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: Math.round(6 * root.s)
    radius: height / 2
    color: root.theme.hover
    border.width: root.activeFocus && root.keyboardShown ? 1 : 0
    border.color: root.theme.accent

    Rectangle {
      width: Math.max(track.height, track.width * root.shown)
      height: parent.height
      radius: parent.radius
      color: root.theme.accent
    }
  }

  // The keyboard focus halo: the handle's own accent border sat next to the
  // accent track and read as barely there (live review, 2026-11-02); a ring
  // around the handle shows against the panel above and below the track.
  Rectangle {
    objectName: "sliderFocusRing"
    anchors.centerIn: handle
    width: handle.width + 2 * Math.round(4 * root.s)
    height: width
    radius: width / 2
    color: "transparent"
    border.width: Math.max(1, Math.round(2 * root.s))
    border.color: root.theme.accent
    visible: root.activeFocus && root.keyboardShown
  }

  Rectangle {
    id: handle

    objectName: "sliderHandle"
    x: Math.round(root.shown * (root.width - width))
    anchors.verticalCenter: parent.verticalCenter
    width: Math.round(16 * root.s)
    height: width
    radius: width / 2
    color: root.theme.foreground
    border.width: root.activeFocus && root.keyboardShown ? Math.max(1, Math.round(2 * root.s)) : 0
    border.color: root.theme.accent
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.enabled
    cursorShape: Qt.PointingHandCursor
    preventStealing: true
    function at(x) { return root.width > 0 ? x / root.width : 0 }
    onPressed: function(mouse) { root.ask(at(mouse.x)) }
    onPositionChanged: function(mouse) { if (pressed) root.ask(at(mouse.x)) }
  }
}
