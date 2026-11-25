pragma Singleton
import QtQuick

// Test double of Omarchy's Commons.Color: the members the bar reads.
QtObject {
  property color foreground: "#efe8dc"
  property color background: "#171614"
  property color accent: "#e8b868"
  property color urgent: "#e79a86"
  property color muted: "#b3a99a"
  readonly property QtObject bar: QtObject {
    property color background: "#171614"
    property color text: "#efe8dc"
    property color active: "#e79a86"
  }
  // The Control Center card (KeyboardPanel) is drawn in this.
  readonly property QtObject popups: QtObject {
    property color background: "#171614"
  }
  readonly property QtObject tooltip: QtObject {
    property color background: "#22201d"
    property color text: "#efe8dc"
    property color border: "#efe8dc"
  }
}
