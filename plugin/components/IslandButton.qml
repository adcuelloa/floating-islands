import QtQuick

// A pressable target inside an island: hover and pressed fills, a slight give
// when pressed, and a pointer area that reaches past the island toward the
// screen edge (reachTop/reachBottom), so a flick to the edge still lands.
Item {
  id: root

  required property var theme

  property bool active: false
  // A keyboard focus ring, independent of `active`, for buttons whose fill
  // already shows a state (the Control Center's mute button).
  property bool showFocus: false
  // Fill when neither hovered nor pressed (the media island's play button).
  property color restColor: "transparent"
  property real minimumWidth: theme.m.buttonMinWidth
  property real horizontalPadding: theme.m.buttonPaddingX
  property real reachTop: 0
  property real reachBottom: 0
  property real reachSide: theme.m.hitSide
  property string accessibleName: ""
  property alias contentSpacing: contentRow.spacing
  default property alias content: contentRow.data

  readonly property bool hovered: pointer.containsMouse
  readonly property bool pressed: pointer.pressed

  signal clicked(int button)
  signal wheelMoved(real delta)

  implicitWidth: Math.max(minimumWidth, contentRow.implicitWidth + 2 * horizontalPadding)
  implicitHeight: theme.m.islandHeight - 2 * theme.m.buttonInset

  Accessible.role: Accessible.Button
  Accessible.name: accessibleName

  scale: pressed ? 0.97 : 1
  Behavior on scale { NumberAnimation { duration: root.theme.fast; easing.type: Easing.OutCubic } }

  Rectangle {
    anchors.fill: parent
    radius: root.theme.m.buttonRadius
    color: root.pressed || root.active ? root.theme.pressed : (root.hovered ? root.theme.hover : root.restColor)

    Behavior on color { ColorAnimation { duration: root.theme.fast; easing.type: Easing.OutCubic } }
  }

  Rectangle {
    objectName: "focusRing"
    anchors.fill: parent
    radius: root.theme.m.buttonRadius
    color: "transparent"
    border.width: Math.max(1, Math.round(1.5 * root.theme.m.scale))
    border.color: root.theme.accent
    visible: root.showFocus
  }

  Row {
    id: contentRow

    anchors.centerIn: parent
    spacing: root.theme.m.contentGap
  }

  MouseArea {
    id: pointer

    anchors.fill: parent
    anchors.topMargin: -root.reachTop
    anchors.bottomMargin: -root.reachBottom
    anchors.leftMargin: -root.reachSide
    anchors.rightMargin: -root.reachSide
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor

    onClicked: function(mouse) { root.clicked(mouse.button) }
    onWheel: function(wheel) { root.wheelMoved(wheel.angleDelta.y) }
  }
}
