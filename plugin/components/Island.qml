import QtQuick
import QtQuick.Effects

// One floating island: a rounded surface with a hairline border and a soft
// shadow. Children are laid out in a row and centred vertically.
Item {
  id: root

  required property var theme

  property real paddingLeft: theme.m.islandPaddingX
  property real paddingRight: theme.m.islandPaddingX
  property alias spacing: row.spacing
  default property alias content: row.data

  readonly property real borderWidth: 1

  implicitWidth: row.implicitWidth + paddingLeft + paddingRight + 2 * borderWidth
  implicitHeight: theme.m.islandHeight

  // 0 4px 14px -6px rgba(0,0,0,.55) in the design.
  RectangularShadow {
    anchors.fill: surface
    radius: surface.radius
    offset.y: 4
    blur: 14
    spread: -6
    color: root.theme.shadow
  }

  Rectangle {
    id: surface

    anchors.fill: parent
    radius: root.theme.m.islandRadius
    color: root.theme.surface
    border.width: root.borderWidth
    border.color: root.theme.border

    Behavior on color { ColorAnimation { duration: root.theme.colorChange; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: root.theme.colorChange; easing.type: Easing.OutCubic } }
  }

  Row {
    id: row

    x: root.borderWidth + root.paddingLeft
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.theme.m.itemGap
  }
}
