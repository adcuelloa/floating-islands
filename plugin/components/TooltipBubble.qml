import QtQuick

// A tooltip under a bar item, drawn on the bar's own full-screen surface
// (no extra window, and it takes no input). Colours are the theme's tooltip
// roles. The text comes from widgets and is shown as plain text.
Item {
  id: root

  required property var theme
  property string text: ""
  // The item's bottom-centre in surface coordinates, and the surface width
  // to stay within.
  property point anchorPoint: Qt.point(0, 0)
  property real surfaceWidth: 0
  property bool shown: false

  readonly property real s: theme.m.scale
  readonly property real margin: Math.round(8 * s)

  x: Math.max(margin, Math.min(surfaceWidth - width - margin, anchorPoint.x - width / 2))
  y: anchorPoint.y + theme.m.panelGap
  width: Math.min(label.implicitWidth + 2 * Math.round(10 * s), Math.round(360 * s))
  height: label.implicitHeight + 2 * Math.round(6 * s)
  opacity: shown && text !== "" ? 1 : 0
  visible: opacity > 0

  Behavior on opacity { NumberAnimation { duration: root.shown ? root.theme.fast : 0 } }

  Rectangle {
    anchors.fill: parent
    radius: Math.round(8 * root.s)
    color: root.theme.tooltipBackground
    border.width: 1
    border.color: root.theme.tooltipBorder
  }

  Text {
    id: label

    anchors.centerIn: parent
    width: Math.min(implicitWidth, Math.round(340 * root.s))
    textFormat: Text.PlainText
    text: root.text
    wrapMode: Text.Wrap
    maximumLineCount: 3
    elide: Text.ElideRight
    color: root.theme.tooltipText
    font.family: root.theme.textFamily
    font.pixelSize: Math.round(12 * root.theme.fontScale)
  }
}
