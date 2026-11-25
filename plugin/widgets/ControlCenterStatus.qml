pragma ComponentBehavior: Bound
import QtQuick

// A control's status line, read in full: it wraps instead of cutting a word,
// and it is as tall as the tallest of `statuses` (every text it can show)
// would be at this width and font, so its height never follows the state.
// `widest` is the natural width of the widest one, for a caller that sizes
// the line to its content.
Text {
  id: root

  // Every text this line can show.
  property var statuses: []

  readonly property real widest: {
    var w = 0
    for (var i = 0; i < probes.count; i++) {
      var probe = probes.itemAt(i)
      if (probe) w = Math.max(w, probe.implicitWidth)
    }
    return Math.ceil(w)
  }
  readonly property real tallest: {
    var h = 0
    for (var i = 0; i < probes.count; i++) {
      var probe = probes.itemAt(i)
      if (probe) h = Math.max(h, probe.height)
    }
    return h
  }

  height: Math.max(implicitHeight, tallest)
  textFormat: Text.PlainText
  wrapMode: Text.Wrap

  // Laid out like this line, never drawn.
  Repeater {
    id: probes
    model: root.statuses

    Text {
      required property string modelData
      visible: false
      width: Math.min(implicitWidth, root.width)
      height: implicitHeight
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      font: root.font
      lineHeight: root.lineHeight
      text: modelData
    }
  }
}
