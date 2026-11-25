import QtQuick
import "../components"
import "../theme/Icons.js" as Icons

// The built-in display's brightness: a slider and its level. The slider
// shows the observed level, or the level asked for while a request is
// pending, as a plain "N %" that follows the handle (no pending mark: a
// step is applied within about 20 ms); the accessible description adds
// "applying" while pending. The label says how the last request ended
// when it did not take ("did not change", "not confirmed"). Without a supported output or device it is disabled
// and reads "unavailable". Left/Right, Page, Home/End and the pointer ask;
// Up/Down are left to the view.
Item {
  id: root

  // A fixed line each: a CJK fallback font must not change the height.
  implicitHeight: (stacked ? 2 : 1) * lineHeight

  required property var theme
  required property var strings
  // adapters/BrightnessAdapter.qml, or an object shaped like it; null reads
  // as unavailable.
  property var provider: null
  property bool keyboardShown: false

  readonly property real s: theme.m.scale
  readonly property bool available: !!provider && provider.available === true && provider.percent >= 0
  readonly property bool pending: available && provider.pending === true && provider.desired >= 0
  readonly property int observed: available ? provider.percent : -1
  readonly property int shown: pending ? provider.desired : observed
  readonly property string outcome: available ? String(provider.outcome || "") : ""

  readonly property string statusText: !available ? strings.t("controlCenter.unavailable")
    : (pending ? shown + " %"
    : (outcome === "failed" ? strings.t("controlCenter.failed")
    : (outcome === "unconfirmed" ? strings.t("controlCenter.unconfirmed")
    : observed + " %")))

  // Wide enough for the longest status this language can show, so a result
  // is read in full and the width never changes with the state (the panel's
  // footprint depends on strings, font and width only).
  readonly property real needed: Math.max(Math.round(76 * s),
    Math.ceil(Math.max(longest0.advanceWidth, longest1.advanceWidth,
                       longest2.advanceWidth, longest3.advanceWidth)) + 2)
  // Beside the slider while that fits in 40 % of the row; otherwise (a large
  // font, a narrow panel) on its own line under the slider, not cut.
  readonly property bool stacked: needed > Math.round(0.4 * width)
  readonly property real labelWidth: stacked ? width - slider.x : needed
  readonly property real gap: Math.round(8 * s)
  readonly property real lineHeight: Math.round(28 * s)

  TextMetrics { id: longest0; font: label.font; text: "100 %" }
  TextMetrics { id: longest1; font: label.font; text: root.strings.t("controlCenter.failed") }
  TextMetrics { id: longest2; font: label.font; text: root.strings.t("controlCenter.unconfirmed") }
  TextMetrics { id: longest3; font: label.font; text: root.strings.t("controlCenter.unavailable") }

  // The focusable controls, in order, for the view's arrow keys.
  function controls() { return root.available ? [slider] : [] }

  function ask(value) {
    if (root.available) root.provider.setPercent(Math.round(100 * value))
  }

  // Lines the slider up with the audio slider above (the mute button's width).
  Item {
    id: iconBox
    width: Math.round(36 * root.s)
    height: root.lineHeight

    StrokeIcon {
      anchors.centerIn: parent
      icon: Icons.brightness
      size: Math.round(18 * root.s)
      color: root.available ? root.theme.foreground : root.theme.muted
    }
  }

  ControlCenterSlider {
    id: slider

    objectName: "brightnessSlider"
    x: iconBox.width + root.gap
    y: Math.round((root.lineHeight - height) / 2)
    width: root.width - x - (root.stacked ? 0 : label.width + root.gap)
    theme: root.theme
    value: root.shown >= 0 ? root.shown / 100 : 0
    enabled: root.available
    keyboardShown: root.keyboardShown
    accessibleName: root.strings.t("controlCenter.brightness")
    valueText: root.pending ? root.statusText + ", " + root.strings.t("controlCenter.applying") : root.statusText
    onMoved: function(value) { root.ask(value) }
  }

  // Beside the slider, or on the next line under the slider's start.
  Text {
    id: label

    objectName: "brightnessStatus"
    x: root.stacked ? slider.x : root.width - width
    y: root.stacked ? root.lineHeight : 0
    height: root.lineHeight
    verticalAlignment: Text.AlignVCenter
    width: root.labelWidth
    horizontalAlignment: root.stacked ? Text.AlignLeft : Text.AlignRight
    textFormat: Text.PlainText
    elide: Text.ElideRight
    text: root.statusText
    // As the audio level: foreground for ordinary text, muted only when unavailable.
    color: root.outcome === "failed" ? root.theme.dangerText : (root.available ? root.theme.foreground : root.theme.muted)
    font.family: root.theme.monoFamily
    font.pixelSize: Math.round(12 * root.theme.fontScale)
  }
}
