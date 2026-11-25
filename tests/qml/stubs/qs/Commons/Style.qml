pragma Singleton
import QtQuick

// Test double of Omarchy's Commons.Style: the members the bar reads.
QtObject {
  id: root
  property bool reduceMotion: false
  property real fontScale: 1
  // Half of Hyprland gaps_out, as Omarchy derives it.
  property int gapsOut: 5
  readonly property var easeOut: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0]
  readonly property QtObject spacing: QtObject { property real scale: 1 }
  readonly property QtObject font: QtObject { property string family: "monospace" }
  function duration(ms) { return root.reduceMotion ? 0 : ms }
}
