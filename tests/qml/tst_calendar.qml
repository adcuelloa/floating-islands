import QtQuick
import QtTest
import qs.Commons as Commons
import "../../plugin/theme/Palette.js" as Palette
import "../../plugin/theme"
import "../../plugin/widgets"

// The calendar content with real Qt locales: week starts, headers and the
// design's date shapes per language, keyboard movement, Escape, and two
// instances (two outputs) keeping separate state.
Item {
  id: scene
  width: 800
  height: 520

  Theme { id: theme }

  QtObject {
    id: strings
    function t(key) { return key }
  }

  CalendarView {
    id: en
    theme: theme
    strings: strings
    localeTag: "en-GB"
    now: new Date(2026, 9, 28, 9, 5)
    width: 308
  }

  CalendarView {
    id: other
    x: 400
    theme: theme
    strings: strings
    localeTag: "ja-JP"
    now: new Date(2026, 9, 28, 9, 5)
    width: 308
  }

  SignalSpy { id: closeSpy; target: en; signalName: "closeRequested" }

  // Inside a Component, `theme: theme` resolves to the new view's own
  // (still unset) property, not the scene's Theme: name them through the
  // scene instead.
  readonly property var fixtureTheme: theme
  readonly property var fixtureStrings: strings

  Component {
    id: freshCalendar
    CalendarView {
      theme: scene.fixtureTheme
      strings: scene.fixtureStrings
      localeTag: "en-GB"
      now: new Date(2026, 9, 28, 9, 5)
      width: 308
    }
  }

  TestCase {
    name: "Calendar"
    when: windowShown

    // Today's number sits on the accent fill: at least 4.5:1 there in every
    // palette (tests/unit/fixtures). It is also DemiBold, not colour alone.
    function test_todayContrast() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../unit/fixtures/omarchy-themes.json"), false)
      xhr.send()
      var themes = JSON.parse(xhr.responseText)
      var saved = [Commons.Color.foreground, Commons.Color.background, Commons.Color.accent,
                   Commons.Color.bar.text, Commons.Color.bar.background]
      var cell = null
      function walk(item) {
        if (item.modelData && item.modelData.today === true && item.color !== undefined) cell = cell || item
        for (var i = 0; i < item.children.length; i++) walk(item.children[i])
      }
      walk(en)
      verify(cell, "today's cell")
      var number = cell.children[0]
      compare(number.font.weight, Font.DemiBold)
      for (var n in themes) {
        var t = themes[n]
        Commons.Color.foreground = t.foreground; Commons.Color.bar.text = t.foreground
        Commons.Color.background = t.background; Commons.Color.bar.background = t.background
        Commons.Color.accent = t.accent
        wait(0)
        verify(Qt.colorEqual(cell.color, theme.accent), n + ": the accent fill is kept")
        var ratio = Palette.contrast(number.color, cell.color)
        verify(ratio >= 4.5, n + ": today " + ratio.toFixed(2) + ":1")
      }
      Commons.Color.foreground = saved[0]; Commons.Color.background = saved[1]; Commons.Color.accent = saved[2]
      Commons.Color.bar.text = saved[3]; Commons.Color.bar.background = saved[4]
    }

    // Trial 4 log: "Binding loop detected for property font.letterSpacing".
    // A fresh view also builds without a runtime error, with the scene's
    // theme and strings, and shows its dates.
    function test_noBindingLoops() {
      failOnWarning(/Binding loop|TypeError|ReferenceError/)
      var view = createTemporaryObject(freshCalendar, scene)
      verify(view !== null)
      wait(50)
      verify(view.theme === theme, "the scene's theme")
      verify(view.strings === strings, "the scene's strings")
      // As on opening (init() does the same for `en`): the month of `now`.
      view.reset()
      var shown = texts(view)
      verify(shown.indexOf("Wednesday") !== -1, shown)
      verify(shown.indexOf("28 October") !== -1, shown)
      verify(shown.indexOf("October 2026") !== -1, shown)
    }

    function init() {
      en.localeTag = "en-GB"
      en.weekStartDay = null
      other.weekStartDay = null
      en.reset()
      other.reset()
      en.forceActiveFocus()
      closeSpy.clear()
    }

    function texts(item, out) {
      out = out || []
      for (var i = 0; i < item.children.length; i++) {
        var child = item.children[i]
        if (child.text !== undefined && child.visible) out.push(String(child.text))
        texts(child, out)
      }
      return out
    }

    function test_weekStartsFollowTheLocale() {
      compare(en.weekStart, 1, "en-GB weeks start on Monday")
      en.localeTag = "es-ES"
      compare(en.weekStart, 1, "es-ES weeks start on Monday")
      en.localeTag = "ja-JP"
      compare(en.weekStart, 0, "ja-JP weeks start on Sunday")
    }

    function test_designDateShapes() {
      var shown = texts(en)
      verify(shown.indexOf("Wednesday") !== -1, shown)
      verify(shown.indexOf("28 October") !== -1, shown)
      verify(shown.indexOf("October 2026") !== -1, shown)
      en.localeTag = "es-ES"
      shown = texts(en)
      verify(shown.indexOf("28 de octubre") !== -1, shown)
      verify(shown.indexOf("octubre de 2026") !== -1, shown)
      shown = texts(other)
      verify(shown.indexOf("10月28日") !== -1, shown)
      verify(shown.indexOf("2026年10月") !== -1, shown)
    }

    function test_gridStartsOnTheRightDay() {
      // October 2026, Monday first: Mon 28 Sep ... the 1st is the fourth cell.
      compare(en.cells[3].day, 1)
      compare(en.cells[3].outside, false)
      // Sunday first (ja): the 1st is the fifth cell.
      compare(other.cells[4].day, 1)
      compare(en.cells.filter(function(c) { return c.today }).length, 1)
    }

    function test_keyboardNavigation() {
      keyClick(Qt.Key_Right)
      compare(en.selected.day, 29)
      verify(en.cursorShown)
      keyClick(Qt.Key_Down)
      compare(en.selected.month, 10)
      compare(en.selected.day, 5)
      keyClick(Qt.Key_PageUp)
      compare(en.selected.month, 9)
      keyClick(Qt.Key_PageDown)
      keyClick(Qt.Key_PageDown)
      compare(en.selected.month, 11)
      verify(texts(en).indexOf("December 2026") !== -1)
      keyClick(Qt.Key_Home)
      compare(en.selected.month, 9)
      compare(en.selected.day, 28)
    }

    function test_escapeAsksToClose() {
      keyClick(Qt.Key_Escape)
      compare(closeSpy.count, 1)
    }

    function test_outputsKeepTheirOwnMonth() {
      keyClick(Qt.Key_PageDown)
      compare(en.selected.month, 10)
      compare(other.selected.month, 9, "the other output's calendar did not move")
    }

    function test_resetReturnsToToday() {
      keyClick(Qt.Key_PageDown)
      en.reset()
      compare(en.selected.month, 9)
      verify(!en.cursorShown)
    }

    function test_configuredWeekStartOverridesLocaleAndPropagates() {
      // Locale fallback when weekStartDay is unset or invalid.
      compare(en.weekStart, 1, "en-GB defaults to Monday")
      compare(other.weekStart, 0, "ja-JP defaults to Sunday")
      en.weekStartDay = "invalid-day"
      compare(en.weekStart, 1, "invalid weekStartDay falls back to locale")

      // Explicit weekStartDay overrides locale and updates grid alignment.
      en.weekStartDay = "sunday"
      other.weekStartDay = "sunday"
      compare(en.weekStart, 0)
      compare(en.cells[4].day, 1, "October 1 2026 moves to fifth cell under Sunday start")
      compare(other.weekStart, 0)

      en.weekStartDay = "monday"
      other.weekStartDay = "monday"
      compare(en.weekStart, 1)
      compare(en.cells[3].day, 1, "October 1 2026 moves back to fourth cell under Monday start")
      compare(other.weekStart, 1, "explicit Monday propagates to ja-JP calendar instance too")
      compare(other.cells[3].day, 1)

      // Arbitrary valid weekday (e.g. Saturday = 6) renders as configured.
      en.weekStartDay = "saturday"
      compare(en.weekStart, 6)
    }
  }
}
