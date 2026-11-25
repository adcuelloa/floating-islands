import QtQuick
import QtTest
import qs.Commons as Commons
import "../../plugin/theme"

// Theme tokens bind to Commons.Color/Style rather than copying them, so a
// live Omarchy theme switch and `omarchy toggle animations` reach the bar.
TestCase {
  name: "Theme"

  Theme { id: theme }

  function test_followsThemeColors() {
    compare(theme.accent, Commons.Color.accent)
    Commons.Color.accent = "#a3cdea"
    compare(theme.accent.toString(), "#a3cdea")
    Commons.Color.bar.text = "#e4eaf3"
    compare(theme.foreground.toString(), "#e4eaf3")
    // Derived roles move with their sources.
    verify(Math.abs(theme.hover.a - 0.08) < 0.01)
    compare(Qt.rgba(theme.hover.r, theme.hover.g, theme.hover.b, 1).toString(), "#e4eaf3")
  }

  function test_accentForegroundIsReadable() {
    Commons.Color.accent = "#e8b868"
    compare(theme.accentForeground, Commons.Color.background)
  }

  function test_reducedMotionZeroesDurations() {
    verify(theme.widget > 0)
    Commons.Style.reduceMotion = true
    compare(theme.fast, 0)
    compare(theme.widget, 0)
    compare(theme.colorChange, 0)
    Commons.Style.reduceMotion = false
    compare(theme.widget, 200)
  }

  function test_metricsFollowDensityAndScale() {
    compare(theme.m.islandHeight, 40)
    theme.density = "comfortable"
    compare(theme.m.islandHeight, 46)
    theme.density = "compact"
    Commons.Style.spacing.scale = 1.25
    compare(theme.m.islandHeight, 50)
    Commons.Style.spacing.scale = 1
  }
}
