pragma Singleton
import QtQuick

// Stands in for Quickshell's Bluetooth singleton: tests set the adapters.
QtObject {
  property QtObject adapters: QtObject { property var values: [] }
}
