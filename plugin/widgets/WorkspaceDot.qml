import QtQuick

// The design's "dots" workspace marker: an 8 px dot for a workspace with
// windows, a ring for an empty one, and a 24 px accent pill for the one shown.
Item {
  id: root

  required property var theme
  property bool active: false
  property bool occupied: false

  readonly property real dot: Math.round(8 * theme.m.scale)
  readonly property real pill: Math.round(24 * theme.m.scale)

  implicitWidth: pill
  implicitHeight: dot

  Rectangle {
    anchors.centerIn: parent
    width: root.active ? root.pill : root.dot
    height: root.dot
    radius: height / 2
    color: root.active ? root.theme.accent : (root.occupied ? root.theme.muted : "transparent")
    border.width: root.active || root.occupied ? 0 : 1.5
    border.color: root.theme.faint

    Behavior on width {
      NumberAnimation { duration: root.theme.widget; easing.type: Easing.Bezier; easing.bezierCurve: root.theme.easeOut }
    }
    Behavior on color { ColorAnimation { duration: root.theme.widget; easing.type: Easing.OutCubic } }
  }
}
