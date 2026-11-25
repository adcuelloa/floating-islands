import QtQuick
import QtTest
import "../../plugin/theme"
import "../../plugin/widgets"

Item {
  width: 600
  height: 80

  Theme { id: theme }

  QtObject {
    id: strings
    function t(key) { return key === "clock" ? "%1, %2" : key }
  }

  ClockIsland { id: clock; theme: theme; strings: strings; tier: "full" }

  TestCase {
    name: "Clock"
    when: windowShown

    function test_formats() {
      compare(clock.timeText, "09:05")
      compare(clock.weekdayText, "Wed")
      compare(clock.dateText, "28 Oct")
    }

    function test_tiersDropDateThenWeekday() {
      var full = clock.demandFor("full")
      var compact = clock.demandFor("compact")
      var minimal = clock.demandFor("minimal")
      verify(full > compact && compact > minimal, full + " > " + compact + " > " + minimal)
      // demandFor() is what the layout reserves: never less than what is
      // drawn, and not meaningfully more.
      var tiers = ["minimal", "compact", "full"]
      for (var i = 0; i < tiers.length; i++) {
        clock.tier = tiers[i]
        var demand = clock.demandFor(tiers[i])
        tryVerify(function() { return demand >= clock.implicitWidth && demand - clock.implicitWidth < 2 }, 1000, tiers[i] + " " + demand + " vs " + clock.implicitWidth)
        var width = clock.implicitWidth
        clock.detailed = true
        compare(clock.demandFor(tiers[i]), demand, "revealing seconds does not change the reservation")
        compare(clock.implicitWidth, width, "nor the island's width")
        clock.detailed = false
      }
      clock.tier = "full"
    }

    // Seconds after the pointer rests, gone on leaving; the clock ticks every
    // second only while they show. No keyboard focus is taken.
    function test_hoverRevealsSeconds() {
      mouseMove(clock, -50, 40)
      compare(clock.timeText, "09:05")
      verify(!clock.secondsShown, "compact: minute ticks")
      mouseMove(clock, clock.width / 2, clock.height / 2)
      wait(100)
      verify(!clock.detailed, "a passing pointer does not reveal them")
      tryCompare(clock, "timeText", "09:05:00", 1000)
      verify(clock.secondsShown, "detailed: second ticks")
      verify(!clock.activeFocus)
      mouseMove(clock, -50, 40)
      tryCompare(clock, "timeText", "09:05")
      verify(!clock.secondsShown)
    }

    // The calendar keeps the seconds in the island, pointer or not; closing
    // it away from the clock returns to the compact time.
    function test_openCalendarKeepsSecondsInTheIsland() {
      mouseMove(clock, -50, 40)
      var width = clock.implicitWidth
      clock.opened = true
      compare(clock.timeText, "09:05:00")
      verify(clock.secondsShown, "second ticks while open")
      compare(clock.implicitWidth, width, "the island keeps its width")
      mouseMove(clock, clock.width / 2, clock.height / 2)
      tryCompare(clock, "detailed", true, 1000)
      mouseMove(clock, -50, 40)
      compare(clock.timeText, "09:05:00", "leaving the clock keeps them while open")
      clock.opened = false
      compare(clock.timeText, "09:05")
      verify(!clock.secondsShown, "back to minute ticks")
      verify(!clock.activeFocus)
    }

    // While open, the calendar's overlay hides the pointer from the clock
    // (here: the pointer moved away). Each case starts open, pointer hidden.
    function openWithOverlay() {
      mouseMove(clock, clock.width / 2, clock.height / 2)
      clock.opened = true
      mouseMove(clock, -50, 40)
      verify(!clock.detailed)
      compare(clock.timeText, "09:05:00", "seconds while open")
    }

    // Closing by clicking the clock keeps the seconds; the pointer is seen
    // on the clock again once the overlay is gone, and they stay.
    function test_clickCloseKeepsSecondsWhileOver() {
      openWithOverlay()
      clock.clickToggle()
      verify(!clock.opened)
      compare(clock.timeText, "09:05:00", "no flash of the compact time")
      mouseMove(clock, clock.width / 2, clock.height / 2)
      wait(clock.detailDelay + 200)
      compare(clock.timeText, "09:05:00", "still over the clock")
      verify(clock.secondsShown)
      mouseMove(clock, -50, 40)
      compare(clock.timeText, "09:05", "leaving removes them")
      verify(!clock.secondsShown)
    }

    // The pointer left as the calendar closed: the seconds go after the delay.
    function test_clickCloseThenGoneDropsSeconds() {
      openWithOverlay()
      clock.clickToggle()
      compare(clock.timeText, "09:05:00")
      tryCompare(clock, "timeText", "09:05", clock.detailDelay + 300)
      verify(!clock.secondsShown, "never left showing seconds")
      wait(clock.detailDelay + 100)
      compare(clock.timeText, "09:05", "and no timer brings them back")
    }

    // Escape or an outside click with the pointer away: compact at once.
    function test_otherCloseWithPointerAway() {
      openWithOverlay()
      clock.close()
      compare(clock.timeText, "09:05")
      verify(!clock.secondsShown)
    }

    // Reopening after a click-close shows the seconds again.
    function test_reopenAfterClickClose() {
      openWithOverlay()
      clock.clickToggle()
      clock.opened = true
      compare(clock.timeText, "09:05:00")
      mouseMove(clock, -50, 40)
      wait(clock.detailDelay + 100)
      compare(clock.timeText, "09:05:00", "open keeps them whatever the timer says")
      clock.close()
      compare(clock.timeText, "09:05")
    }

    function test_detailKeepsTheTimeFormat() {
      clock.timeFormat = "h:mm AP"
      compare(clock.timeText, "9:05 AM")
      compare(clock.detailTimeText, "9:05:00 AM")
      clock.timeFormat = "HH:mm:ss"
      verify(clock.secondsShown, "a format with seconds keeps second ticks")
      compare(clock.detailTimeText, "09:05:00")
      clock.timeFormat = "HH:mm"
    }

    function test_japaneseDateOrder() {
      clock.localeTag = "ja-JP"
      compare(clock.dateText, "10月28日")
      clock.localeTag = "es-ES"
      compare(clock.dateText, "28 oct")
      clock.localeTag = "en-GB"
    }

    function test_islandHeight() {
      compare(clock.implicitHeight, 40)
    }
  }
}
