import QtQuick

// The hairline between the launcher and the workspaces.
Item {
  id: root

  required property var theme

  implicitWidth: 1 + 2 * theme.m.dividerMargin
  implicitHeight: theme.m.dividerHeight

  Rectangle {
    anchors.centerIn: parent
    width: 1
    height: parent.height
    color: root.theme.borderStrong
  }
}
