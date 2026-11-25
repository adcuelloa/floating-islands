import QtQuick

// One group of the Control Center's dashboard: a heading, then its controls
// stacked below it. The heading also names the group for assistive
// technology. Its visual style waits for the design prototype
// (docs/CONTROL_CENTER_LAYOUT.md, section 6).
Column {
  id: root

  required property var theme
  property string title: ""
  default property alias content: body.data

  spacing: Math.round(6 * theme.m.scale)

  Accessible.role: Accessible.Grouping
  Accessible.name: root.title

  Text {
    objectName: "groupTitle"
    width: root.width
    textFormat: Text.PlainText
    elide: Text.ElideRight
    text: root.title
    color: root.theme.secondaryText
    font.family: root.theme.textFamily
    font.pixelSize: Math.round(11 * root.theme.fontScale)
    font.weight: Font.DemiBold
    Accessible.role: Accessible.Heading
    Accessible.name: root.title
  }

  Column {
    id: body
    width: root.width
    spacing: Math.round(8 * root.theme.m.scale)
  }
}
