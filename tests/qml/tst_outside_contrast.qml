import QtQuick
import QtTest
import qs.Commons as Commons
import "../../plugin/theme"
import "../../plugin/widgets"
import "../../plugin/theme/Palette.js" as Palette

// Secondary text outside the Control Center, in every palette
// (tests/unit/fixtures/omarchy-themes.json): the clock's date and weekday,
// the empty-title placeholder and its icon, the media artist (bar islands:
// on the island surface, and on a hovered or pressed button there), and
// the calendar's headings and other-month days (on the card, and on a
// hovered day). Text reaches 4.5:1, the title icon 3:1, and secondary text
// stays weaker than ordinary text. Presses are released outside: nothing
// opens, pins or plays.
Item {
  id: scene
  width: 1200
  height: 700

  Theme { id: theme }

  QtObject {
    id: strings
    function t(key) { return key === "clock" ? "%1, %2" : (key === "media.show" || key === "media.hide" ? key + " %1" : key) }
  }

  ClockIsland { id: clock; theme: theme; strings: strings; tier: "full" }

  QtObject {
    id: emptyWindow
    property bool empty: true
    property string title: ""
    property string kind: ""
    property string iconSource: ""
  }
  TitleIsland { id: title; y: 60; theme: theme; window: emptyWindow; strings: strings; maximumWidth: 240 }

  QtObject {
    id: player
    property string trackTitle: "Slow Tide"
    property string trackArtist: "Hikari Ensemble"
    property bool isPlaying: true
    property bool canGoNext: true
    property bool canGoPrevious: true
    property bool canTogglePlaying: true
    property real position: 30
    property real length: 120
  }
  QtObject {
    id: service
    property var activePlayer: player
    property var actions: []
    function runAction(action, feedback, key) { actions = actions.concat([action]) }
    function playerKey(p) { return p ? "mpris:test" : "" }
  }
  MediaIsland { id: media; y: 120; theme: theme; strings: strings; service: service; tier: "full" }

  CalendarView {
    id: calendar
    y: 180
    theme: theme
    strings: strings
    localeTag: "en-GB"
    now: new Date(2026, 9, 28, 9, 5)
    width: 308
  }

  TestCase {
    name: "OutsideContrast"
    when: windowShown

    function init() {
      failOnWarning(/TypeError|ReferenceError|Binding loop/)
    }

    function find(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var found = find(item.children[i], name)
        if (found) return found
      }
      return null
    }
    function findAll(item, name, out) {
      out = out || []
      if (item.objectName === name) out.push(item)
      for (var i = 0; i < item.children.length; i++) findAll(item.children[i], name, out)
      return out
    }
    function over(top, under) {
      return Qt.rgba(under.r + (top.r - under.r) * top.a, under.g + (top.g - under.g) * top.a,
                     under.b + (top.b - under.b) * top.a, 1)
    }
    // A colour as drawn: 8 bits per channel.
    function drawn(c) { return Qt.color(c.toString()) }

    function palettes() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../unit/fixtures/omarchy-themes.json"), false)
      xhr.send()
      return JSON.parse(xhr.responseText)
    }
    function apply(t) {
      Commons.Color.foreground = t.foreground; Commons.Color.bar.text = t.foreground
      Commons.Color.background = t.background; Commons.Color.bar.background = t.background
      Commons.Color.popups.background = t.background
      Commons.Color.muted = t.muted; Commons.Color.urgent = t.urgent; Commons.Color.accent = t.accent
      wait(0)
    }
    function cleanup() {
      Commons.Color.foreground = "#efe8dc"; Commons.Color.bar.text = "#efe8dc"
      Commons.Color.background = "#171614"; Commons.Color.bar.background = "#171614"
      Commons.Color.popups.background = "#171614"
      Commons.Color.muted = "#b3a99a"; Commons.Color.urgent = "#e79a86"; Commons.Color.accent = "#e8b868"
      Commons.Style.fontScale = 1
      mouseRelease(scene, 1199, 699); mouseMove(scene, 1199, 699)
    }

    // The island surface, and a button's fill on it (hovered, pressed).
    function islandGround(fill) {
      var surface = over(theme.surface, Commons.Color.background)
      return fill ? over(fill, surface) : surface
    }
    function checkText(label, grounds, what, n, scale) {
      verify(label && label.visible, what + " shown")
      for (var g of grounds) {
        var ratio = Palette.contrast(drawn(label.color), g)
        verify(ratio >= 4.5, n + " x" + scale + ": " + what + " " + JSON.stringify(label.text) + " " + ratio.toFixed(2) + ":1")
        // The weekday is the accent used as text, not secondary text.
        if (what.indexOf("clockWeekday") !== 0)
          verify(ratio < Palette.contrast(drawn(theme.foreground), g), n + ": " + what + " stays below ordinary text")
      }
    }

    function test_islandSecondaryText() {
      var themes = palettes()
      var mainButton = find(media, "mediaMain")
      var clockButton = clock.children[clock.children.length - 1]
      while (clockButton && clockButton.hovered === undefined) clockButton = clockButton.children[0]
      verify(clockButton, "clock button")
      var low = 99, worst = ""
      for (var n in themes) {
        apply(themes[n])
        for (var scale of [1, 1.4]) {
          Commons.Style.fontScale = scale
          wait(0)
          var date = find(clock, "clockDate"), weekday = find(clock, "clockWeekday")
          var placeholder = find(title, "titleLabel"), symbol = find(title, "titleSymbol")
          var artist = find(media, "mediaArtist")
          compare(placeholder.text, strings.t("window.none"))
          // At rest, on the surface.
          for (var x of [date, weekday, placeholder, artist]) checkText(x, [islandGround(null)], x.objectName, n, scale)
          var iconRatio = Palette.contrast(drawn(symbol.color), islandGround(null))
          verify(iconRatio >= 3, n + ": title icon " + iconRatio.toFixed(2) + ":1")
          // Hovered and pressed buttons (clock, media), released outside.
          for (var pair of [[clockButton, [date, weekday]], [mainButton, [artist]]]) {
            var b = pair[0]
            mouseMove(b, b.width / 2, b.height / 2); wait(0)
            verify(b.hovered, n + ": " + b.objectName + " hovered")
            for (var y of pair[1]) checkText(y, [islandGround(theme.hover)], y.objectName + " (hover)", n, scale)
            mousePress(b, b.width / 2, b.height / 2); wait(0)
            for (var z of pair[1]) checkText(z, [islandGround(theme.pressed)], z.objectName + " (pressed)", n, scale)
            mouseRelease(scene, 1199, 699); mouseMove(scene, 1199, 699); wait(0)
            for (var w of pair[1]) {
              var r = Palette.contrast(drawn(w.color), islandGround(theme.pressed))
              if (r < low) { low = r; worst = n + " " + w.objectName }
            }
          }
        }
        Commons.Style.fontScale = 1
      }
      verify(!media.pinned, "nothing pinned")
      compare(service.actions, [], "no media command")
      console.log("island secondary text: lowest", low.toFixed(2) + ":1 (" + worst + ") across", Object.keys(themes).length, "palettes")
    }

    function test_calendarSecondaryText() {
      var themes = palettes()
      // The day grid is rebuilt when the locale changes: look the labels up
      // again each time.
      function labels() {
        var out = { outside: null, today: null }
        for (var c of findAll(calendar, "calendarDay")) {
          if (c.parent.modelData.outside && !out.outside) out.outside = c
          if (c.parent.modelData.today) out.today = c
        }
        out.headings = findAll(calendar, "calendarHeading").concat([find(calendar, "calendarWeekday")])
        return out
      }
      // As on opening: the month of `now`, with today in it.
      calendar.reset()
      for (var tag of ["en-GB", "es-ES", "ja-JP"]) {
        calendar.localeTag = tag
        tryVerify(function() { var t = labels(); return t.today !== null && t.outside !== null && t.headings.length === 8 }, 1000,
                  tag + ": the grid is rebuilt")
        var l = labels()
        verify(l.outside, tag + ": an other-month day is shown")
        verify(l.today, tag + ": today is shown")
        compare(l.headings.length, 8, tag + ": seven weekday headings and today's weekday")
        for (var n in themes) {
          apply(themes[n])
          for (var scale of [1, 1.4]) {
            Commons.Style.fontScale = scale
            wait(0)
            var card = over(Commons.Color.popups.background, Commons.Color.background)
            for (var h of l.headings) checkText(h, [card], "heading", n + " " + tag, scale)
            checkText(l.outside, [card], "other-month day", n + " " + tag, scale)
            verify(!Qt.colorEqual(l.outside.color, l.today.color), "today stays distinct")
            verify(!Qt.colorEqual(l.outside.color, theme.foreground), "other-month days stay distinct from this month's")
          }
        }
        Commons.Style.fontScale = 1
      }
      // A hovered other-month day: the hover fill under it.
      calendar.localeTag = "en-GB"
      tryVerify(function() { var t = labels(); return t.today !== null && t.outside !== null }, 1000, "en-GB grid rebuilt")
      var en = labels()
      for (var m in themes) {
        apply(themes[m])
        var cell = en.outside.parent
        mouseMove(cell, cell.width / 2, cell.height / 2); wait(0)
        verify(Qt.colorEqual(cell.color, theme.hover), m + ": hover fill")
        var cardM = over(Commons.Color.popups.background, Commons.Color.background)
        checkText(en.outside, [over(theme.hover, cardM)], "other-month day (hover)", m, 1)
        mouseMove(scene, 1199, 699)
      }
      compare(en.today.color.toString(), theme.accentForeground.toString(), "today keeps the M7.4 ink")
      // Month navigation (PageDown / PageUp, as the keys do): the next
      // month's other-month days and headings keep the readable colour.
      var month = calendar.selected.month
      calendar.command("nextMonth")
      tryVerify(function() { return calendar.selected.month === (month + 1) % 12 && labels().outside !== null }, 1000, "next month shown")
      var next = labels()
      var cardN = over(Commons.Color.popups.background, Commons.Color.background)
      checkText(next.outside, [cardN], "other-month day (next month)", "last palette", 1)
      for (var hn of next.headings) checkText(hn, [cardN], "heading (next month)", "last palette", 1)
      calendar.command("previousMonth")
      tryVerify(function() { return calendar.selected.month === month }, 1000, "back to this month")
      calendar.reset()
    }
  }
}
