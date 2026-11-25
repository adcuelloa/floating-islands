import QtQuick
import QtTest
import qs.Commons as Commons
import "../../plugin/geometry/Layout.js" as Layout
import "../../plugin/theme"
import "../../plugin/widgets"

Item {
  id: harness

  width: 1536
  height: 80

  Theme { id: theme }

  QtObject {
    id: strings
    function t(key) { return key === "clock" ? "%1, %2" : key }
  }

  QtObject {
    id: windowStub
    property bool empty: false
    property string title: "A very long application window title that adapts cleanly beside the dynamic clock island"
    property string kind: "terminal"
    property string iconSource: ""
  }

  // Mini bar geometry harness exercising centering, hit area, tier stability,
  // and flexible TitleIsland adaptation alongside ClockIsland.
  readonly property real leftFixed: 280
  readonly property real rightFixed: 480
  readonly property var tierDemands: ({
    full: { center: clock.maxDemandFor("full"), leftFixed: leftFixed, titleMin: theme.m.titleMin, rightFixed: rightFixed },
    compact: { center: clock.maxDemandFor("compact"), leftFixed: leftFixed, titleMin: theme.m.titleMin, rightFixed: 360 },
    minimal: { center: clock.maxDemandFor("minimal"), leftFixed: leftFixed, titleMin: 0, rightFixed: 220 }
  })
  readonly property real activeClockWidth: Math.max(clock.demandFor(clock.tier), Math.ceil(clock.implicitWidth))
  readonly property real titleMaxWidth: Layout.titleWidth(clock.tier, harness.width, { center: activeClockWidth, leftFixed: leftFixed }, theme.m)

  TitleIsland {
    id: neighborTitle
    x: theme.m.sideMargin + harness.leftFixed
    y: 10
    theme: theme
    window: windowStub
    strings: strings
    maximumWidth: harness.titleMaxWidth
    iconStyle: "symbol"
  }

  ClockIsland {
    id: clock
    x: Math.round((harness.width - width) / 2)
    y: 10
    theme: theme
    strings: strings
    tier: "full"
  }

  TestCase {
    name: "Clock"
    when: windowShown

    function init() {
      Commons.Style.reduceMotion = true
      Commons.Style.fontScale = 1
      Commons.Style.spacing.scale = 1
      clock.tier = "full"
      clock.timeFormat = "HH:mm"
      clock.localeTag = "en-GB"
      clock.opened = false
      clock.detailed = false
      var sysClock = findChild(clock, "systemClock")
      if (sysClock) sysClock.date = new Date(2026, 9, 28, 9, 5, 0)
      mouseMove(harness, 10, 10)
      tryVerify(function() { return clock.timeSlot === clock.compactTimeSlot }, 1000)
      wait(32)
      Commons.Style.reduceMotion = false
    }

    function cleanup() {
      Commons.Style.reduceMotion = false
      Commons.Style.fontScale = 1
      Commons.Style.spacing.scale = 1
      clock.opened = false
      clock.detailed = false
      clock.timeFormat = "HH:mm"
      clock.localeTag = "en-GB"
      clock.tier = "full"
      var sysClock = findChild(clock, "systemClock")
      if (sysClock) sysClock.date = new Date(2026, 9, 28, 9, 5, 0)
    }

    function test_formats() {
      compare(clock.timeText, "09:05")
      compare(clock.weekdayText, "Wed")
      compare(clock.dateText, "28 Oct")
    }

    function test_tiersDropDateThenWeekdayAndExpandDynamically() {
      var full = clock.demandFor("full")
      var compact = clock.demandFor("compact")
      var minimal = clock.demandFor("minimal")
      verify(full > compact && compact > minimal, full + " > " + compact + " > " + minimal)
      // demandFor() tracks the current target width (idle vs expanded) and
      // never falls short of what is drawn; maxDemandFor() stays constant.
      var tiers = ["minimal", "compact", "full"]
      for (var i = 0; i < tiers.length; i++) {
        clock.tier = tiers[i]
        tryCompare(clock, "timeSlot", clock.compactTimeSlot, 1000)
        var idleDemand = clock.demandFor(tiers[i])
        var maxDemand = clock.maxDemandFor(tiers[i])
        verify(maxDemand > idleDemand, tiers[i] + " max " + maxDemand + " > idle " + idleDemand)
        tryVerify(function() { return idleDemand >= clock.implicitWidth && idleDemand - clock.implicitWidth < 2 }, 1000, tiers[i] + " idle " + idleDemand + " vs " + clock.implicitWidth)
        var idleWidth = clock.implicitWidth

        clock.detailed = true
        compare(clock.demandFor(tiers[i]), maxDemand, "expanded demand matches maxDemandFor")
        compare(clock.maxDemandFor(tiers[i]), maxDemand, "maxDemandFor is invariant")
        tryCompare(clock, "timeSlot", clock.detailTimeSlot, 1000)
        verify(clock.implicitWidth > idleWidth, tiers[i] + " expanded width > idle width")
        tryVerify(function() { return maxDemand >= clock.implicitWidth && maxDemand - clock.implicitWidth < 2 }, 1000, tiers[i] + " expanded " + maxDemand + " vs " + clock.implicitWidth)

        clock.detailed = false
        compare(clock.demandFor(tiers[i]), idleDemand, "returning to idle restores idle demand")
        tryCompare(clock, "timeSlot", clock.compactTimeSlot, 1000)
        compare(clock.implicitWidth, idleWidth, "returning to idle restores idle width")
      }
      clock.tier = "full"
    }

    // Seconds after the pointer rests, gone on leaving; the clock expands on
    // hover, stays centered, and ticks every second only while they show.
    function test_hoverRevealsSecondsAndExpands() {
      mouseMove(harness, 10, 10)
      compare(clock.timeText, "09:05")
      verify(!clock.secondsShown, "compact: minute ticks")
      var idleWidth = clock.implicitWidth
      var idleCenter = clock.x + clock.width / 2

      mouseMove(clock, clock.width / 2, clock.height / 2)
      wait(100)
      verify(!clock.detailed, "a passing pointer does not reveal them")
      compare(clock.implicitWidth, idleWidth, "no expansion before detailDelay")

      tryCompare(clock, "timeText", "09:05:00", 1000)
      verify(clock.secondsShown, "detailed: second ticks")
      verify(!clock.activeFocus)
      tryCompare(clock, "timeSlot", clock.detailTimeSlot, 1000)
      verify(clock.implicitWidth > idleWidth, "hover expands clock island")
      verify(Math.abs((clock.x + clock.width / 2) - idleCenter) <= 0.5, "remains horizontally centered when expanded")

      mouseMove(harness, 10, 10)
      tryCompare(clock, "timeText", "09:05")
      verify(!clock.secondsShown)
      tryCompare(clock, "timeSlot", clock.compactTimeSlot, 1000)
      compare(clock.implicitWidth, idleWidth, "leaving restores idle width")
    }

    // The calendar keeps the seconds and expanded width, pointer or not;
    // closing it away from the clock returns to idle width.
    function test_openCalendarKeepsSecondsAndExpandedWidth() {
      mouseMove(harness, 10, 10)
      var idleWidth = clock.implicitWidth

      clock.opened = true
      compare(clock.timeText, "09:05:00")
      verify(clock.secondsShown, "second ticks while open")
      tryCompare(clock, "timeSlot", clock.detailTimeSlot, 1000)
      var expandedWidth = clock.implicitWidth
      verify(expandedWidth > idleWidth, "calendar open expands the island")

      mouseMove(clock, clock.width / 2, clock.height / 2)
      tryCompare(clock, "detailed", true, 1000)
      mouseMove(harness, 10, 10)
      compare(clock.timeText, "09:05:00", "leaving the clock keeps them while open")
      compare(clock.implicitWidth, expandedWidth, "leaving while open keeps expanded width")

      clock.opened = false
      compare(clock.timeText, "09:05")
      verify(!clock.secondsShown, "back to minute ticks")
      tryCompare(clock, "timeSlot", clock.compactTimeSlot, 1000)
      compare(clock.implicitWidth, idleWidth, "closing restores idle width")
      verify(!clock.activeFocus)
    }

    // While open, the calendar's overlay hides the pointer from the clock
    // (here: the pointer moved away). Each case starts open, pointer hidden.
    function openWithOverlay() {
      mouseMove(clock, clock.width / 2, clock.height / 2)
      clock.opened = true
      mouseMove(harness, 10, 10)
      verify(!clock.detailed)
      compare(clock.timeText, "09:05:00", "seconds while open")
      tryCompare(clock, "timeSlot", clock.detailTimeSlot, 1000)
    }

    // Closing by clicking the clock keeps seconds and expanded width while the
    // pointer stays over the clock; leaving restores idle width.
    function test_clickCloseKeepsSecondsAndWidthWhileOver() {
      var idleWidth = clock.implicitWidth
      openWithOverlay()
      var expandedWidth = clock.implicitWidth
      clock.clickToggle()
      verify(!clock.opened)
      compare(clock.timeText, "09:05:00", "no flash of the compact time")
      compare(clock.targetTimeSlot, clock.detailTimeSlot, "no width dip on click close")
      mouseMove(clock, clock.width / 2, clock.height / 2)
      wait(clock.detailDelay + 200)
      compare(clock.timeText, "09:05:00", "still over the clock")
      compare(clock.implicitWidth, expandedWidth, "stays expanded while hovered")
      verify(clock.secondsShown)
      mouseMove(harness, 10, 10)
      compare(clock.timeText, "09:05", "leaving removes them")
      verify(!clock.secondsShown)
      tryVerify(function() { return clock.timeSlot === clock.compactTimeSlot }, 1000)
      tryCompare(clock, "implicitWidth", idleWidth, 1000, "leaving restores idle width")
    }

    // The pointer left as the calendar closed: seconds and expanded width go
    // after the delay.
    function test_clickCloseThenGoneDropsSecondsAndRestoresWidth() {
      var idleWidth = clock.implicitWidth
      openWithOverlay()
      clock.clickToggle()
      compare(clock.timeText, "09:05:00")
      tryCompare(clock, "timeText", "09:05", clock.detailDelay + 300)
      verify(!clock.secondsShown, "never left showing seconds")
      tryVerify(function() { return clock.timeSlot === clock.compactTimeSlot }, 1000)
      tryCompare(clock, "implicitWidth", idleWidth, 1000, "restores idle width after delay")
      wait(clock.detailDelay + 100)
      compare(clock.timeText, "09:05", "and no timer brings them back")
    }

    // Escape or an outside click with the pointer away: compact and idle width.
    function test_otherCloseWithPointerAway() {
      var idleWidth = clock.implicitWidth
      openWithOverlay()
      clock.close()
      compare(clock.timeText, "09:05")
      verify(!clock.secondsShown)
      tryVerify(function() { return clock.timeSlot === clock.compactTimeSlot }, 1000)
      tryCompare(clock, "implicitWidth", idleWidth, 1000, "restores idle width")
    }

    // Closing the calendar while hover detail is active keeps expanded width
    // until the pointer leaves.
    function test_otherCloseWithContinuedHoverKeepsExpandedWidth() {
      var idleWidth = clock.implicitWidth
      clock.opened = true
      tryCompare(clock, "timeSlot", clock.detailTimeSlot, 1000)
      var expandedWidth = clock.implicitWidth
      mouseMove(clock, clock.width / 2, clock.height / 2)
      tryCompare(clock, "detailed", true, 1000)
      clock.close()
      compare(clock.timeText, "09:05:00", "continued hover keeps seconds")
      compare(clock.implicitWidth, expandedWidth, "continued hover keeps expanded width")
      mouseMove(harness, 10, 10)
      tryVerify(function() { return clock.timeSlot === clock.compactTimeSlot }, 1000)
      tryCompare(clock, "implicitWidth", idleWidth, 1000, "leaving restores idle width")
    }

    // Reopening after a click-close shows the seconds again.
    function test_reopenAfterClickClose() {
      openWithOverlay()
      clock.clickToggle()
      clock.opened = true
      compare(clock.timeText, "09:05:00")
      mouseMove(harness, 10, 10)
      wait(clock.detailDelay + 100)
      compare(clock.timeText, "09:05:00", "open keeps them whatever the timer says")
      clock.close()
      compare(clock.timeText, "09:05")
    }

    function test_explicitSecondsFormatKeepsConstantWidth() {
      clock.timeFormat = "h:mm AP"
      compare(clock.timeText, "9:05 AM")
      compare(clock.detailTimeText, "9:05:00 AM")
      verify(clock.detailTimeSlot > clock.compactTimeSlot, "12h without seconds still expands")

      clock.timeFormat = "HH:mm:ss"
      tryCompare(clock, "timeSlot", clock.detailTimeSlot, 1000)
      verify(clock.secondsShown, "a format with seconds keeps second ticks")
      compare(clock.detailTimeText, "09:05:00")
      compare(clock.compactTimeSlot, clock.detailTimeSlot, "no idle/expanded delta")
      compare(clock.demandFor("full"), clock.maxDemandFor("full"), "demand matches maxDemandFor")
      var steadyWidth = clock.implicitWidth
      clock.detailed = true
      compare(clock.implicitWidth, steadyWidth, "hover does not resize explicit-seconds format")
      clock.opened = true
      compare(clock.implicitWidth, steadyWidth, "calendar open does not resize explicit-seconds format")
      clock.opened = false
      clock.detailed = false
      compare(clock.implicitWidth, steadyWidth, "idle keeps same width")
    }

    function test_secondTicksDoNotChangeWidth() {
      var sysClock = findChild(clock, "systemClock")
      verify(sysClock !== null, "systemClock accessible for tick testing")
      clock.opened = true
      tryCompare(clock, "timeSlot", clock.detailTimeSlot, 1000)
      var expectedSlot = clock.timeSlot
      var expectedWidth = clock.implicitWidth
      var expectedDemand = clock.demandFor("full")
      var seconds = [1, 11, 23, 37, 48, 59]
      for (var i = 0; i < seconds.length; i++) {
        sysClock.date = new Date(2026, 9, 28, 9, 5, seconds[i])
        compare(clock.timeSlot, expectedSlot, "timeSlot stable at :" + seconds[i])
        compare(clock.implicitWidth, expectedWidth, "implicitWidth stable at :" + seconds[i])
        compare(clock.demandFor("full"), expectedDemand, "demand stable at :" + seconds[i])
      }
      var timeLabel = findChild(clock, "clockTime")
      verify(timeLabel !== null)
      verify(timeLabel.implicitWidth <= timeLabel.width + 0.5, "time text not clipped at settled detail width")
    }

    function test_responsiveGeometryWithNeighboringTitleIsland() {
      var initialTier = Layout.chooseTier(harness.width, harness.tierDemands, theme.m, "full")
      compare(initialTier, "full")
      var idleTitleWidth = neighborTitle.width
      var idleGap = clock.x - (neighborTitle.x + neighborTitle.width)
      verify(idleGap >= theme.m.centerClearance, "idle clearance " + idleGap + " >= " + theme.m.centerClearance)

      clock.opened = true
      compare(Layout.chooseTier(harness.width, harness.tierDemands, theme.m, initialTier), "full", "expanding clock does not flip tier")
      tryCompare(clock, "timeSlot", clock.detailTimeSlot, 1000)
      var expandedTitleWidth = neighborTitle.width
      var expandedGap = clock.x - (neighborTitle.x + neighborTitle.width)
      verify(expandedTitleWidth <= idleTitleWidth, "title yields or stays within cap when clock expands")
      verify(expandedGap >= theme.m.centerClearance, "expanded clearance " + expandedGap + " >= " + theme.m.centerClearance)

      // Hit area reconciles with live visual geometry.
      var expandedHit = Layout.hitRect({ x: clock.x, y: clock.y, width: clock.width, height: clock.height }, "top", harness.height, theme.m)
      compare(expandedHit.width, clock.width + 2 * theme.m.hitSide)

      clock.opened = false
      tryCompare(clock, "timeSlot", clock.compactTimeSlot, 1000)
      compare(neighborTitle.width, idleTitleWidth, "title reclaims idle space")
    }

    function test_reducedMotionSnapsWithoutDelay() {
      Commons.Style.reduceMotion = true
      compare(theme.widget, 0, "reduced motion sets widget duration to 0")
      var idleWidth = clock.implicitWidth
      clock.opened = true
      // Synchronous slot snap (0 ms animation); Row polishes on the next frame.
      compare(clock.timeSlot, clock.detailTimeSlot, "expanded synchronously under reduced motion")
      tryVerify(function() { return clock.implicitWidth > idleWidth }, 50, "width expanded within one polish frame")
      clock.opened = false
      compare(clock.timeSlot, clock.compactTimeSlot, "collapsed synchronously under reduced motion")
      tryCompare(clock, "implicitWidth", idleWidth, 50, "width restored within one polish frame")
    }

    function test_localeAndFontScalingBehavior() {
      clock.localeTag = "ja-JP"
      compare(clock.dateText, "10月28日")
      clock.localeTag = "es-ES"
      compare(clock.dateText, "28 oct")
      clock.localeTag = "en-GB"

      var baseIdle = clock.implicitWidth
      Commons.Style.reduceMotion = true
      Commons.Style.fontScale = 1.25
      Commons.Style.spacing.scale = 1.25
      tryVerify(function() { return clock.implicitWidth > baseIdle }, 100, "font/spacing scaling widens idle clock")
      var scaledIdle = clock.implicitWidth
      clock.opened = true
      tryVerify(function() { return clock.implicitWidth > scaledIdle }, 100, "scaled clock still expands for seconds")
      var timeLabel = findChild(clock, "clockTime")
      verify(timeLabel.implicitWidth <= timeLabel.width + 0.5, "scaled time text not clipped")
    }

    function test_animatedExpansionKeepsPrefixReadableAndShiftsLeft() {
      verify(theme.widget > 0, "animations enabled for intermediate-frame verification")
      var prefix = findChild(clock, "clockTimePrefix")
      var secondsClip = findChild(clock, "clockTimeSecondsClip")
      var secondsLabel = findChild(clock, "clockTimeSeconds")
      verify(prefix !== null && secondsClip !== null && secondsLabel !== null)

      compare(prefix.text, "09:05")
      verify(!prefix.clip, "prefix text is never clipped")
      verify(prefix.implicitWidth <= prefix.width + 0.5, "idle prefix fits without clipping")
      compare(secondsClip.width, 0)
      verify(!secondsClip.visible, "seconds clip hidden at idle")

      var idlePrefixX = prefix.mapToItem(harness, 0, 0).x
      var idleCenter = clock.x + clock.width / 2
      var expandIntermediates = 0
      var prevSlot = clock.timeSlot
      var prevPrefixX = idlePrefixX

      clock.opened = true
      for (var step = 0; step < 60 && clock.timeSlot < clock.detailTimeSlot; step++) {
        wait(12)
        if (clock.timeSlot > clock.compactTimeSlot + 0.5 && clock.timeSlot < clock.detailTimeSlot - 0.5) {
          expandIntermediates++
          verify(prefix.implicitWidth <= prefix.width + 0.5, "prefix unclipped on expand frame " + step)
          verify(secondsClip.visible, "seconds clip visible on expand frame " + step)
          verify(secondsClip.width > 0 && secondsClip.width < clock.secondsSlot, "seconds width progressive on expand frame " + step)
          compare(secondsLabel.x, 0, "seconds reveal from left edge")
          verify(clock.timeSlot >= prevSlot - 0.01, "timeSlot grows monotonically")
          var curPrefixX = prefix.mapToItem(harness, 0, 0).x
          verify(curPrefixX <= prevPrefixX + 1.0, "prefix shifts smoothly left on expand frame " + step)
          verify(Math.abs((clock.x + clock.width / 2) - idleCenter) <= 1.0, "island stays centered on expand frame " + step)
          prevSlot = clock.timeSlot
          prevPrefixX = curPrefixX
        }
      }
      tryCompare(clock, "timeSlot", clock.detailTimeSlot, 1000)
      verify(expandIntermediates > 0, "observed intermediate expansion frames")
      var expandedPrefixX = prefix.mapToItem(harness, 0, 0).x
      verify(expandedPrefixX < idlePrefixX, "prefix moved left when expanded: " + expandedPrefixX + " < " + idlePrefixX)
      compare(secondsClip.width, clock.secondsSlot)
      compare(secondsLabel.opacity, 1)
      verify(secondsLabel.implicitWidth <= secondsClip.width + 0.5, "settled seconds fit without clipping")

      var collapseIntermediates = 0
      prevSlot = clock.timeSlot
      prevPrefixX = expandedPrefixX
      clock.opened = false
      for (var cStep = 0; cStep < 60 && clock.timeSlot > clock.compactTimeSlot; cStep++) {
        wait(12)
        if (clock.timeSlot > clock.compactTimeSlot + 0.5 && clock.timeSlot < clock.detailTimeSlot - 0.5) {
          collapseIntermediates++
          verify(prefix.implicitWidth <= prefix.width + 0.5, "prefix unclipped on collapse frame " + cStep)
          verify(secondsClip.width > 0 && secondsClip.width < clock.secondsSlot, "seconds retract progressively on collapse frame " + cStep)
          verify(clock.timeSlot <= prevSlot + 0.01, "timeSlot shrinks monotonically")
          var colPrefixX = prefix.mapToItem(harness, 0, 0).x
          verify(colPrefixX >= prevPrefixX - 1.0, "prefix shifts smoothly right on collapse frame " + cStep)
          verify(Math.abs((clock.x + clock.width / 2) - idleCenter) <= 1.0, "island stays centered on collapse frame " + cStep)
          prevSlot = clock.timeSlot
          prevPrefixX = colPrefixX
        }
      }
      tryVerify(function() { return clock.timeSlot === clock.compactTimeSlot }, 1000)
      verify(collapseIntermediates > 0, "observed intermediate collapse frames")
      compare(secondsClip.width, 0)
      verify(!secondsClip.visible, "seconds clip hidden after collapse")
      verify(Math.abs(prefix.mapToItem(harness, 0, 0).x - idlePrefixX) <= 1.0, "prefix returns to idle x")
    }

    function test_animatedAmPmFormatShiftsSuffixRightWithoutClipping() {
      verify(theme.widget > 0, "animations enabled")
      var sysClock = findChild(clock, "systemClock")
      if (sysClock) sysClock.date = new Date(2026, 9, 28, 15, 55, 42)
      clock.timeFormat = "h:mm AP"
      tryVerify(function() { return clock.timeSlot === clock.compactTimeSlot }, 1000)

      var prefix = findChild(clock, "clockTimePrefix")
      var secondsClip = findChild(clock, "clockTimeSecondsClip")
      var secondsLabel = findChild(clock, "clockTimeSeconds")
      var suffix = findChild(clock, "clockTimeSuffix")
      verify(prefix !== null && secondsClip !== null && secondsLabel !== null && suffix !== null)

      compare(prefix.text, "3:55")
      compare(suffix.text, " PM")
      verify(suffix.visible)
      verify(prefix.implicitWidth <= prefix.width + 0.5, "12h prefix unclipped at idle")
      verify(suffix.implicitWidth <= suffix.width + 0.5, "AM/PM suffix unclipped at idle")

      var idlePrefixX = prefix.mapToItem(harness, 0, 0).x
      var idleSuffixX = suffix.mapToItem(harness, 0, 0).x
      var intermediates = 0

      clock.opened = true
      for (var step = 0; step < 60 && clock.timeSlot < clock.detailTimeSlot; step++) {
        wait(12)
        if (clock.timeSlot > clock.compactTimeSlot + 0.5 && clock.timeSlot < clock.detailTimeSlot - 0.5) {
          intermediates++
          verify(prefix.implicitWidth <= prefix.width + 0.5, "12h prefix unclipped mid-transition")
          verify(suffix.implicitWidth <= suffix.width + 0.5, "AM/PM suffix unclipped mid-transition")
          verify(prefix.mapToItem(harness, 0, 0).x <= idlePrefixX + 1.0, "12h prefix moves left")
          verify(suffix.mapToItem(harness, 0, 0).x >= idleSuffixX - 1.0, "AM/PM suffix moves right")
        }
      }
      tryCompare(clock, "timeSlot", clock.detailTimeSlot, 1000)
      verify(intermediates > 0, "observed intermediate 12h expansion frames")
      verify(prefix.mapToItem(harness, 0, 0).x < idlePrefixX, "12h prefix shifted left")
      verify(suffix.mapToItem(harness, 0, 0).x > idleSuffixX, "AM/PM suffix shifted right")
      compare(secondsLabel.text, ":42")
      compare(secondsClip.width, clock.secondsSlot)
    }

    function test_interruptedAndReversedHoverTransitionRecoversCleanly() {
      verify(theme.widget > 0, "animations enabled")
      var prefix = findChild(clock, "clockTimePrefix")
      var secondsClip = findChild(clock, "clockTimeSecondsClip")
      var secondsLabel = findChild(clock, "clockTimeSeconds")
      verify(prefix !== null && secondsClip !== null && secondsLabel !== null)

      // Expand halfway, then immediately reverse to collapse.
      clock.detailed = true
      tryVerify(function() {
        return clock.timeSlot > clock.compactTimeSlot + 1 && clock.timeSlot < clock.detailTimeSlot - 1
      }, 500, "reached mid-expansion before interruption")
      verify(prefix.implicitWidth <= prefix.width + 0.5, "prefix unclipped at expansion interruption")

      clock.detailed = false
      tryCompare(clock, "timeSlot", clock.compactTimeSlot, 1000)
      compare(secondsClip.width, 0)
      verify(!secondsClip.visible, "reversed expansion settles cleanly to idle")

      // Expand to full, start collapsing, then re-expand mid-collapse.
      clock.detailed = true
      tryCompare(clock, "timeSlot", clock.detailTimeSlot, 1000)
      clock.detailed = false
      tryVerify(function() {
        return clock.timeSlot > clock.compactTimeSlot + 1 && clock.timeSlot < clock.detailTimeSlot - 1
      }, 500, "reached mid-collapse before re-expansion")
      verify(prefix.implicitWidth <= prefix.width + 0.5, "prefix unclipped at collapse interruption")

      clock.detailed = true
      tryCompare(clock, "timeSlot", clock.detailTimeSlot, 1000)
      compare(secondsClip.width, clock.secondsSlot)
      compare(secondsLabel.opacity, 1)
      verify(prefix.implicitWidth <= prefix.width + 0.5, "prefix unclipped after re-expansion")
    }

    function test_islandHeight() {
      compare(clock.implicitHeight, 40)
    }
  }
}
