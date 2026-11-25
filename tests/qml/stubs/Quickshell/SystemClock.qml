import QtQuick

// Test double of Quickshell's SystemClock: a fixed, settable date.
QtObject {
  enum Precision { Hours, Minutes, Seconds }
  property int precision: SystemClock.Minutes
  property date date: new Date(2026, 9, 28, 9, 5, 0)
}
