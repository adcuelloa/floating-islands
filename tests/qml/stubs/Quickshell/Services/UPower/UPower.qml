pragma Singleton
import QtQuick

// Stands in for Quickshell's UPower singleton: tests set the power source.
QtObject {
  property bool onBattery: false
}
