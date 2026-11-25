import QtQuick
import Quickshell
import qs.Commons as Commons
import "../components"
import "../logic/ClockFormat.js" as ClockFormat
import "../logic/Calendar.js" as Calendar

// The centre island: the time in the mono face, then the date, whose weekday
// takes the accent. What shows depends on the tier; demandFor() measures each
// tier's width without drawing it, so the layout can choose before it draws.
// Clicking it opens the calendar (CalendarPanel), which follows the shell's
// summon/hide contract through open(), close() and `opened`.
Island {
  id: root

  required property var strings
  property string tier: "full"
  property string timeFormat: "HH:mm"
  property var reach: ({ top: 0, bottom: 0 })
  // The bar facade panels coordinate through; without one (tests) the
  // calendar is not built.
  property var bar: null
  // A locale tag (logic/Calendar.js resolveLocale): the bar's `locale`
  // setting, or the Omarchy language.
  property string localeTag: Commons.I18n.formatLocale

  readonly property var parts: ClockFormat.partsFor(tier)
  readonly property var locale: Qt.locale(localeTag)

  // ------------------------------------------------------------ calendar
  property bool opened: false
  property bool popoutSwitchClosing: false

  function open() { if (calendar.status === Loader.Ready) root.opened = true }
  function close() { root.opened = false }
  function toggle() { root.opened ? root.close() : root.open() }
  // A click on the clock. While the calendar is open its overlay covers the
  // bar, so the hover handler reads "not hovered" though the pointer is on
  // the clock. Closing with that click keeps the seconds and lets the delay
  // timer confirm the hover once the overlay is gone: they stay only if the
  // pointer is still there.
  function clickToggle() {
    if (root.opened) {
      root.detailed = true
      detailTimer.restart()
    }
    root.toggle()
  }
  function closeForPopoutSwitch() {
    root.popoutSwitchClosing = true
    root.close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  // Loaded by URL with its required properties (KeyboardPanel's anchorItem
  // and bar) given at construction, once there is a bar to coordinate with.
  // Loading by URL also keeps KeyboardPanel, a window type, out of this
  // file's own dependencies.
  readonly property Loader calendar: Loader {
    // By name: the loaded type is only known at run time.
    onLoaded: {
      var panel = item
      var bindings = {
        now: function() { return root.now },
        localeTag: function() { return root.localeTag },
        open: function() { return root.opened }
      }
      for (var name in bindings) panel[name] = Qt.binding(bindings[name])
    }
  }

  function loadCalendar() {
    if (!root.bar || calendar.status !== Loader.Null) return
    calendar.setSource(Qt.resolvedUrl("CalendarPanel.qml"), {
      anchorItem: clockButton,
      bar: root.bar,
      island: root,
      theme: root.theme,
      strings: root.strings
    })
  }

  onBarChanged: {
    if (!root.bar) return
    root.bar.registerClickTarget(clockButton)
    root.loadCalendar()
  }
  readonly property date now: clock.date
  // Seconds show in the island after the pointer rests on the clock, and
  // for as long as the calendar is open (whether or not the pointer stays);
  // only then does the clock tick every second.
  readonly property int detailDelay: 400
  property bool detailed: false
  readonly property bool secondsShown: detailed || opened || timeFormat.indexOf("s") !== -1
  readonly property string detailFormat: ClockFormat.withSeconds(timeFormat)
  readonly property string detailTimeText: now.toLocaleString(locale, detailFormat)
  readonly property string compactTimeText: now.toLocaleString(locale, timeFormat)
  readonly property string timeText: detailed || opened ? detailTimeText : compactTimeText
  readonly property string weekdayText: now.toLocaleString(locale, ClockFormat.WEEKDAY_FORMAT)
  // The day and month in the language's own order ("29 Oct", "10月29日").
  readonly property string dateText: now.toLocaleString(locale, Calendar.patterns(localeTag).shortDate)

  // The time's slot: fits the idle time format by default, and expands to fit
  // seconds while hovered (after detailDelay), while the calendar is open, or
  // when timeFormat explicitly includes seconds.
  readonly property real compactTimeSlot: Math.ceil(timeMetrics.advanceWidth)
  readonly property real detailTimeSlot: Math.ceil(Math.max(timeMetrics.advanceWidth, detailMetrics.advanceWidth))
  readonly property real targetTimeSlot: secondsShown ? detailTimeSlot : compactTimeSlot
  property real timeSlot: targetTimeSlot

  Behavior on timeSlot {
    enabled: root.theme.widget > 0
    NumberAnimation {
      duration: root.theme.widget
      easing.type: Easing.Bezier
      easing.bezierCurve: root.theme.easeOut
    }
  }

  readonly property real buttonPadding: Math.round(14 * theme.m.scale)
  readonly property real partGap: Math.round(12 * theme.m.scale)
  readonly property real wordGap: Math.round(5 * theme.m.scale)

  paddingLeft: Math.round(6 * theme.m.scale)
  paddingRight: Math.round(6 * theme.m.scale)

  function demandForSlot(forTier, slot) {
    var p = ClockFormat.partsFor(forTier)
    var inner = slot
    if (p.date) inner += partGap + dateMetrics.advanceWidth
    if (p.weekday) inner += wordGap + weekdayMetrics.advanceWidth
    // TextMetrics and the drawn Text can differ by a fraction of a pixel;
    // the reservation must never come out short.
    return Math.ceil(inner + 2 * buttonPadding + paddingLeft + paddingRight + 2 * borderWidth) + 1
  }

  // Current target width for this tier (compact while idle, detailed while
  // seconds are shown), used so flexible neighbours can adapt.
  function demandFor(forTier) {
    return demandForSlot(forTier, targetTimeSlot)
  }

  // Maximum width for this tier (with seconds shown), used for responsive
  // tier selection so hovering the clock or opening the calendar never flips
  // the tier under the pointer.
  function maxDemandFor(forTier) {
    return demandForSlot(forTier, detailTimeSlot)
  }

  SystemClock {
    id: clock
    objectName: "systemClock"
    precision: root.secondsShown ? SystemClock.Seconds : SystemClock.Minutes
  }

  // No keyboard focus: hovering only changes what the clock shows.
  HoverHandler {
    id: hover
    onHoveredChanged: {
      if (hovered) detailTimer.restart()
      else { detailTimer.stop(); root.detailed = false }
    }
  }

  Timer {
    id: detailTimer
    interval: root.detailDelay
    onTriggered: root.detailed = hover.hovered
  }

  TextMetrics { id: timeMetrics; font: timeLabel.font; text: ClockFormat.stableDigits(root.compactTimeText) }
  TextMetrics { id: detailMetrics; font: timeLabel.font; text: ClockFormat.stableDigits(root.detailTimeText) }
  TextMetrics { id: weekdayMetrics; font: weekdayLabel.font; text: root.weekdayText }
  TextMetrics { id: dateMetrics; font: dateLabel.font; text: root.dateText }

  IslandButton {
    id: clockButton

    // KeyboardPanel forwards a click on this button while the calendar is
    // open, so the click toggles it rather than closing and reopening.
    function triggerPress(button) { if (button === Qt.LeftButton) root.clickToggle() }

    theme: root.theme
    active: root.opened
    onClicked: function(button) { if (button === Qt.LeftButton) root.clickToggle() }
    horizontalPadding: root.buttonPadding
    contentSpacing: 0
    reachTop: root.reach.top
    reachBottom: root.reach.bottom
    accessibleName: root.strings.t("clock").arg(root.now.toLocaleString(root.locale, "dddd d MMMM yyyy")).arg(root.timeText)

    // Flat on purpose: each part shows or hides on its own, so the row
    // re-measures as the tier changes (a hidden nested Row did not).
    Text {
      id: timeLabel

      objectName: "clockTime"
      anchors.verticalCenter: parent.verticalCenter
      width: root.timeSlot
      clip: true
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: root.timeText
      color: root.theme.foreground
      font.family: root.theme.monoFamily
      font.pixelSize: root.theme.timeSize
      font.weight: Font.DemiBold
      font.letterSpacing: root.theme.timeSize * 0.02
    }

    Text {
      id: weekdayLabel

      objectName: "clockWeekday"
      anchors.verticalCenter: parent.verticalCenter
      visible: root.parts.weekday
      leftPadding: root.partGap
      textFormat: Text.PlainText
      text: root.weekdayText
      color: root.theme.islandAccentText
      font.family: root.theme.textFamily
      font.pixelSize: root.theme.textSize
      font.weight: Font.Medium
    }

    Text {
      id: dateLabel

      objectName: "clockDate"
      anchors.verticalCenter: parent.verticalCenter
      visible: root.parts.date
      leftPadding: root.parts.weekday ? root.wordGap : root.partGap
      textFormat: Text.PlainText
      text: root.dateText
      color: root.theme.islandSecondaryText
      font.family: root.theme.textFamily
      font.pixelSize: root.theme.textSize
    }
  }
}
