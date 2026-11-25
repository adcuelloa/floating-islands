pragma Singleton
import QtQuick

// Stands in for Quickshell's PowerProfiles singleton: tests set the profile
// (0 power-saver, 1 balanced, 2 performance), as the daemon's signal would.
QtObject {
  property int profile: 1
}
