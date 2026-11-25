pragma Singleton
import QtQuick

// Stands in for Quickshell's Pipewire singleton: tests set the default sink.
QtObject {
  property var defaultAudioSink: null
}
