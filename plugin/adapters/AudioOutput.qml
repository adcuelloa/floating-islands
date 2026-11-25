import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// The default audio output, as Pipewire reports it: `sink` follows
// Pipewire.defaultAudioSink, so a change of default device (another panel,
// wpctl, a headset plugged in) moves the controls to the new device instead
// of keeping the old one. The tracker binds the node so its volume and mute
// stay live, as Omarchy's audio panel does. Nothing is tracked while inactive.
Scope {
  id: root

  property bool active: false
  readonly property var sink: root.active ? Pipewire.defaultAudioSink : null

  PwObjectTracker { objects: root.sink ? [root.sink] : [] }
}
