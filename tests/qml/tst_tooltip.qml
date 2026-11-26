import QtQuick
import QtTest
import "../../plugin/theme"
import "../../plugin/components"

Item {
  width: 600
  height: 200

  Theme { id: theme }

  TooltipBubble {
    id: tip
    theme: theme
    text: "Wi-Fi: Haven-5G"
    surfaceWidth: 600
    anchorPoint: Qt.point(300, 50)
    shown: true
  }

  TestCase {
    name: "Tooltip"
    when: windowShown

    function test_centredUnderItsTarget() {
      tryCompare(tip, "opacity", 1)
      verify(Math.abs(tip.x + tip.width / 2 - 300) <= 1)
      compare(tip.y, 50 + theme.m.panelGap, "panelGap below its target, like every panel")
    }

    function test_staysOnScreen() {
      tip.anchorPoint = Qt.point(595, 50)
      verify(tip.x + tip.width <= 600 - tip.margin + 0.5)
      tip.anchorPoint = Qt.point(2, 50)
      compare(tip.x, tip.margin)
    }

    function test_plainTextAndHidden() {
      tip.text = "<b>x</b>"
      compare(tip.children[1].textFormat, Text.PlainText)
      tip.shown = false
      compare(tip.visible, false, "tooltip hides synchronously on leave before any anchor invalidation")
      tryCompare(tip, "opacity", 0)
      tip.shown = true
    }

    function test_hideBeforeAnchorResetDoesNotJumpVisibly() {
      tip.anchorPoint = Qt.point(480, 50)
      tip.shown = true
      tryCompare(tip, "opacity", 1)
      var shownX = tip.x
      verify(shownX > tip.margin + 100)

      // Hide synchronously; even if anchorPoint later resets, tooltip is already hidden.
      tip.shown = false
      compare(tip.visible, false)
      compare(tip.x, shownX, "last valid x preserved when anchorPoint is kept")
      tip.shown = true
    }
  }
}
