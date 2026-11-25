import QtQuick
import "../components"
import "../theme/Icons.js" as Icons
import "../logic/ControlCenter.js" as Model

// The default output's volume and mute. Everything shown is read from the
// Pipewire node (`sink`, which follows the default device); a change asked
// here is written to the node and shows once the node reports it. It reads
// "pending" until then and "did not change" if the node has not reported it
// after confirmTimeout. A change of default device drops anything pending.
Column {
  id: root

  required property var theme
  required property var strings
  property var sink: null
  property bool hasPanel: false
  property int confirmTimeout: 3000
  property bool keyboardShown: false

  signal panelRequested()

  readonly property real s: theme.m.scale
  readonly property bool available: Model.outputAvailable(sink)
  readonly property real volume: available ? sink.audio.volume : 0
  readonly property bool muted: available ? sink.audio.muted === true : false
  property var pendingVolume: null
  property var pendingMute: null
  property bool failed: false
  readonly property bool pending: pendingVolume !== null || pendingMute !== null

  readonly property string statusText: !available ? strings.t("controlCenter.noOutput")
    : (failed ? strings.t("controlCenter.failed")
    : (muted ? strings.t("controlCenter.muted") : Model.percent(volume) + " %"))

  // The focusable controls, in order, for the view's arrow keys.
  function controls() {
    // From `available`, not activeFocusOnTab: Qt keeps that set on the item
    // holding focus when the device goes away.
    var out = root.available ? [muteButton, slider] : []
    if (moreButton.visible) out.push(moreButton)
    return out
  }

  function setVolume(value) {
    if (!root.available) return
    var target = Model.clampVolume(value)
    root.failed = false
    root.sink.audio.volume = target
    if (Math.abs(root.volume - target) < 0.005) { root.pendingVolume = null; return }
    root.pendingVolume = target
    confirm.restart()
  }

  function toggleMute() {
    if (!root.available || root.pendingMute !== null) return
    var target = !root.muted
    root.failed = false
    root.sink.audio.muted = target
    if (root.muted === target) return
    root.pendingMute = target
    confirm.restart()
  }

  function settle() {
    if (root.pendingVolume !== null && Math.abs(root.volume - root.pendingVolume) < 0.005) root.pendingVolume = null
    if (root.pendingMute !== null && root.muted === root.pendingMute) root.pendingMute = null
    if (!root.pending) confirm.stop()
  }

  onVolumeChanged: { root.settle(); if (!root.pending) root.failed = false }
  onMutedChanged: { root.settle(); if (!root.pending) root.failed = false }
  // A new default device: nothing asked of the old one still applies.
  onSinkChanged: {
    root.pendingVolume = null
    root.pendingMute = null
    root.failed = false
    confirm.stop()
  }

  Timer {
    id: confirm
    interval: root.confirmTimeout
    onTriggered: if (root.pending) { root.pendingVolume = null; root.pendingMute = null; root.failed = true }
  }

  spacing: Math.round(4 * s)

  // The level beside the slider while it fits in 40 % of the row; otherwise
  // (a long translation, a large font) on its own line under the slider, as
  // the brightness level does. Its slot is as wide as the longest status
  // this language can show, so a result is read in full and the row never
  // changes size with the state.
  Item {
    id: levelRow

    readonly property real gap: Math.round(8 * root.s)
    readonly property real lineHeight: Math.max(muteButton.implicitHeight, Math.round(28 * root.s))
    readonly property real needed: Math.max(Math.round(76 * root.s),
      Math.ceil(Math.max(longest0.advanceWidth, longest1.advanceWidth, longest2.advanceWidth, longest3.advanceWidth)) + 2)
    readonly property bool stacked: needed > Math.round(0.4 * width)

    objectName: "audioLevelRow"
    width: parent.width
    height: (stacked ? 2 : 1) * lineHeight

    TextMetrics { id: longest0; font: percentLabel.font; text: "100 %" }
    TextMetrics { id: longest1; font: percentLabel.font; text: root.strings.t("controlCenter.muted") }
    TextMetrics { id: longest2; font: percentLabel.font; text: root.strings.t("controlCenter.failed") }
    TextMetrics { id: longest3; font: percentLabel.font; text: root.strings.t("controlCenter.noOutput") }

    IslandButton {
      id: muteButton

      y: Math.round((levelRow.lineHeight - height) / 2)

      theme: root.theme
      minimumWidth: Math.round(36 * root.s)
      horizontalPadding: 0
      // The fill shows the state, the ring the keyboard focus: one fill for
      // both left focus invisible while muted (live review, 2026-11-02).
      active: root.muted
      showFocus: activeFocus && root.keyboardShown
      // Disabled without a device: Qt then drops its focus and skips it on Tab.
      enabled: root.available
      activeFocusOnTab: true
      opacity: root.available ? 1 : 0.55
      accessibleName: root.strings.t("controlCenter.mute")
      Accessible.role: Accessible.CheckBox
      Accessible.checkable: root.available
      Accessible.checked: root.muted
      onClicked: function(button) { if (button === Qt.LeftButton) root.toggleMute() }
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.toggleMute()
          event.accepted = true
        }
      }

      StrokeIcon {
        icon: root.muted ? Icons.speakerMuted : Icons.speaker
        size: Math.round(18 * root.s)
        color: root.available ? root.theme.foreground : root.theme.muted
      }
    }

    ControlCenterSlider {
      id: slider

      x: muteButton.width + levelRow.gap
      y: Math.round((levelRow.lineHeight - height) / 2)
      width: levelRow.width - x - (levelRow.stacked ? 0 : percentLabel.width + levelRow.gap)
      theme: root.theme
      value: root.pendingVolume !== null ? root.pendingVolume : root.volume
      enabled: root.available
      keyboardShown: root.keyboardShown
      accessibleName: root.strings.t("controlCenter.volume")
      valueText: root.statusText
      onMoved: function(value) { root.setVolume(value) }
    }

    Text {
      id: percentLabel

      objectName: "audioStatus"
      x: levelRow.stacked ? slider.x : levelRow.width - width
      y: levelRow.stacked ? levelRow.lineHeight : 0
      width: levelRow.stacked ? levelRow.width - slider.x : levelRow.needed
      height: levelRow.lineHeight
      verticalAlignment: Text.AlignVCenter
      horizontalAlignment: levelRow.stacked ? Text.AlignLeft : Text.AlignRight
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: root.statusText
      // Ordinary text on the card: muted is a decorative tone in most themes
      // (2.31:1 here); it stays for the unavailable state only.
      color: root.failed ? root.theme.dangerText : (root.available ? root.theme.foreground : root.theme.muted)
      font.family: root.theme.monoFamily
      font.pixelSize: Math.round(12 * root.theme.fontScale)
    }
  }

  Item {
    width: parent.width
    height: Math.round(28 * root.s)

    Text {
      objectName: "audioDevice"
      anchors.left: parent.left
      anchors.right: moreButton.visible ? moreButton.left : parent.right
      anchors.rightMargin: Math.round(8 * root.s)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: Model.outputName(root.sink)
      color: root.theme.secondaryText
      font.family: root.theme.textFamily
      font.pixelSize: Math.round(12 * root.theme.fontScale)
    }

    IslandButton {
      id: moreButton

      objectName: "moreAudio"

      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: root.hasPanel
      theme: root.theme
      implicitHeight: Math.round(28 * root.s)
      active: activeFocus && root.keyboardShown
      activeFocusOnTab: visible
      accessibleName: root.strings.t("controlCenter.moreAudio")
      onClicked: function(button) { if (button === Qt.LeftButton) root.panelRequested() }
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.panelRequested()
          event.accepted = true
        }
      }

      Text {
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        textFormat: Text.PlainText
        text: root.strings.t("controlCenter.moreAudio")
        color: root.theme.foreground
        font.family: root.theme.textFamily
        font.pixelSize: Math.round(12 * root.theme.fontScale)
      }
    }
  }
}
