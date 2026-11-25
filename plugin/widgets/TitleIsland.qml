import QtQuick
import "../components"
import "../theme/Icons.js" as Icons

// The active window's title, after the application's own icon (or, when none
// resolves or bar.islands.titleIcon is "symbol", a monochrome symbol for its
// kind). It is the
// one island that gives way: the layout hands it `maximumWidth` and the title
// elides to fit.
Island {
  id: root

  required property var window
  required property var strings
  property real maximumWidth: 0
  // "app": the application's icon when one resolves; "symbol": always the design's.
  property string iconStyle: "app"

  readonly property bool appIconShown: iconStyle === "app" && !window.empty
    && String(window.iconSource || "") !== "" && appIcon.status !== Image.Error

  readonly property string text: window.empty ? strings.t("window.none") : window.title
  readonly property real iconSize: Math.round(18 * theme.m.scale)
  readonly property real naturalWidth: borderWidth * 2 + paddingLeft + paddingRight + iconSize + spacing + label.implicitWidth

  paddingLeft: Math.round(12 * theme.m.scale)
  paddingRight: Math.round(14 * theme.m.scale)
  spacing: Math.round(10 * theme.m.scale)
  width: Math.min(naturalWidth, maximumWidth)
  visible: maximumWidth >= theme.m.titleMin && text !== ""
  clip: false

  Accessible.role: Accessible.StaticText
  Accessible.name: text

  Item {
    anchors.verticalCenter: parent.verticalCenter
    width: root.iconSize
    height: root.iconSize

    Image {
      id: appIcon

      objectName: "titleAppIcon"
      anchors.fill: parent
      visible: root.appIconShown && status === Image.Ready
      source: root.iconStyle === "app" && !root.window.empty ? String(root.window.iconSource || "") : ""
      sourceSize: Qt.size(Math.ceil(root.iconSize * 2), Math.ceil(root.iconSize * 2))
      fillMode: Image.PreserveAspectFit
      smooth: true
      asynchronous: true
    }

    StrokeIcon {
      objectName: "titleSymbol"
      anchors.centerIn: parent
      visible: !appIcon.visible
      icon: Icons.forKind(root.window.kind)
      size: root.iconSize
      color: root.theme.islandSecondaryText
    }
  }

  Text {
    id: label

    objectName: "titleLabel"
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(0, root.width - (root.naturalWidth - implicitWidth))
    textFormat: Text.PlainText
    text: root.text
    elide: Text.ElideRight
    maximumLineCount: 1
    color: root.window.empty ? root.theme.islandSecondaryText : root.theme.foreground
    font.family: root.theme.textFamily
    font.pixelSize: root.theme.textSize
  }
}
