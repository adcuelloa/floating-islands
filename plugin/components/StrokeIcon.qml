import QtQuick
import QtQuick.Shapes

// A 24 x 24 stroke icon from theme/Icons.js, drawn natively and scaled to
// `size` (stroke included, as the design's SVGs scale).
Item {
  id: root

  property var icon: null
  property color color: "white"
  property real size: 18
  property real strokeWidth: icon && icon.strokeWidth ? icon.strokeWidth : 1.8

  implicitWidth: size
  implicitHeight: size

  Shape {
    width: 24
    height: 24
    anchors.centerIn: parent
    scale: root.size / 24
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: root.color
      strokeWidth: root.strokeWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin

      PathSvg { path: root.icon ? root.icon.stroke : "" }
    }

    ShapePath {
      strokeWidth: -1
      strokeColor: "transparent"
      fillColor: root.icon && root.icon.fill ? root.color : "transparent"

      PathSvg { path: root.icon && root.icon.fill ? root.icon.fill : "M0 0" }
    }
  }
}
