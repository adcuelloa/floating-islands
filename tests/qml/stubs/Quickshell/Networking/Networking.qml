pragma Singleton
import QtQuick

// Stands in for Quickshell's Networking singleton: tests set the backend,
// the devices and the radio state.
QtObject {
  property int backend: 1
  property QtObject devices: QtObject { property var values: [] }
  property bool wifiEnabled: true
  property bool wifiHardwareEnabled: true
}
