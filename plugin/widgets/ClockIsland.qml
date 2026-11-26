import QtQuick
import Quickshell
import qs.Commons as Commons
import "../components"
import "../logic/ClockFormat.mjs" as ClockFormat
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
  property var weekStartDay: null
  // Maximum centred width available between fixed side groups (< 0 = unconstrained).
  property real maximumWidth: -1
  property var reach: ({ top: 0, bottom: 0 })
  // The bar facade panels coordinate through; without one (tests) the
  // calendar is not built.
  property var bar: null
  // A locale tag (logic/Calendar.js resolveLocale): the bar's `locale`
  // setting, or the Omarchy language.
  property string localeTag: Commons.I18n.formatLocale

  readonly property var parts: ClockFormat.partsFor(tier, timeFormat)
  readonly property var locale: Qt.locale(localeTag)

  signal cycleFormatRequested()
  signal timezoneRequested()

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
        weekStartDay: function() { return root.weekStartDay },
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
  property date displayDate: clock.date
  readonly property date now: displayDate

  function refresh() {
    root.displayDate = new Date()
  }

  function formatDateTime(fmt) {
    var formatDigit = typeof Commons.I18n.formatNumber === "function"
      ? function(digit) { return Commons.I18n.formatNumber(digit) }
      : null
    var resolved = ClockFormat.expandIsoWeek(fmt, root.now, formatDigit)
    return root.now.toLocaleString(root.locale, resolved)
  }

  // Seconds show in the island after the pointer rests on the clock, and
  // for as long as the calendar is open (whether or not the pointer stays);
  // only then does the clock tick every second.
  readonly property int detailDelay: 400
  property bool detailed: false
  readonly property bool hasExplicitSeconds: ClockFormat.hasSecondsToken(timeFormat)
  readonly property bool secondsShown: detailed || opened || hasExplicitSeconds
  readonly property string detailFormat: ClockFormat.withSeconds(timeFormat)
  readonly property string detailTimeText: formatDateTime(detailFormat)
  readonly property string compactTimeText: formatDateTime(timeFormat)
  readonly property var timeTextParts: ClockFormat.splitTimeText(compactTimeText, detailTimeText)
  readonly property string prefixTimeText: timeTextParts.prefix
  readonly property string secondsTimeText: timeTextParts.seconds
  readonly property string suffixTimeText: timeTextParts.suffix
  readonly property string timeText: detailed || opened ? detailTimeText : compactTimeText
  readonly property string weekdayText: now.toLocaleString(locale, ClockFormat.WEEKDAY_FORMAT)
  // The day and month in the language's own order ("29 Oct", "10月29日").
  readonly property string dateText: now.toLocaleString(locale, Calendar.patterns(localeTag).shortDate)

  // The time's slot: fits the idle time format by default, and expands to fit
  // seconds while hovered (after detailDelay), while the calendar is open, or
  // when timeFormat explicitly includes seconds. Only the seconds reveal
  // factor (0..1) animates, so changing timeFormat updates text and container
  // geometry coherently in one step with no transient overflow or empty space.
  readonly property real prefixSlot: Math.ceil(prefixMetrics.advanceWidth)
  readonly property real secondsSlot: timeTextParts.expandable ? Math.ceil(secondsMetrics.advanceWidth) : 0
  readonly property real suffixSlot: suffixTimeText !== "" ? Math.ceil(suffixMetrics.advanceWidth) : 0
  readonly property real compactTimeSlot: prefixSlot + suffixSlot
  readonly property real detailTimeSlot: compactTimeSlot + secondsSlot
  readonly property real targetTimeSlot: secondsShown ? detailTimeSlot : compactTimeSlot
  readonly property real targetSecondsProgress: secondsShown ? 1 : 0
  property bool _snappingFormat: false
  property real secondsProgress: targetSecondsProgress

  Behavior on secondsProgress {
    enabled: root.theme.widget > 0 && !root._snappingFormat
    NumberAnimation {
      duration: root.theme.widget
      easing.type: Easing.Bezier
      easing.bezierCurve: root.theme.easeOut
    }
  }

  onTimeFormatChanged: {
    var nextTarget = (root.detailed || root.opened || ClockFormat.hasSecondsToken(root.timeFormat)) ? 1 : 0
    root._snappingFormat = true
    root.secondsProgress = nextTarget
    root.secondsProgress = Qt.binding(function() { return root.targetSecondsProgress })
    root._snappingFormat = false
  }

  readonly property real secondsRevealWidth: timeTextParts.expandable
    ? secondsSlot * secondsProgress
    : 0
  readonly property real secondsRevealProgress: secondsSlot > 0 ? secondsRevealWidth / secondsSlot : 0
  readonly property real timeSlot: compactTimeSlot + secondsRevealWidth

  readonly property real buttonPadding: Math.round(14 * theme.m.scale)
  readonly property real partGap: Math.round(12 * theme.m.scale)
  readonly property real wordGap: Math.round(5 * theme.m.scale)

  paddingLeft: Math.round(6 * theme.m.scale)
  paddingRight: Math.round(6 * theme.m.scale)

  readonly property real chromeWidth: 2 * buttonPadding + paddingLeft + paddingRight + 2 * borderWidth + 1
  readonly property real fullSupplementaryWidth: (parts.date ? partGap + dateMetrics.advanceWidth : 0)
    + (parts.weekday ? wordGap + weekdayMetrics.advanceWidth : 0)
  readonly property real dateOnlySupplementaryWidth: parts.date ? partGap + dateMetrics.advanceWidth : 0
  readonly property real naturalWidth: Math.ceil(timeSlot + fullSupplementaryWidth + chromeWidth)
  readonly property bool constrained: maximumWidth >= 0 && naturalWidth > maximumWidth
  readonly property bool showWeekday: parts.weekday && (maximumWidth < 0 || Math.ceil(timeSlot + fullSupplementaryWidth + chromeWidth) <= maximumWidth)
  readonly property bool showDate: parts.date && (showWeekday || maximumWidth < 0 || Math.ceil(timeSlot + dateOnlySupplementaryWidth + chromeWidth) <= maximumWidth)
  readonly property real visibleSupplementaryWidth: (showDate ? partGap + dateMetrics.advanceWidth : 0)
    + (showWeekday ? wordGap + weekdayMetrics.advanceWidth : 0)
  readonly property bool timeElided: maximumWidth >= 0 && Math.ceil(timeSlot + visibleSupplementaryWidth + chromeWidth) > maximumWidth
  readonly property real effectiveTimeSlot: timeElided
    ? Math.max(0, Math.floor(maximumWidth - chromeWidth - visibleSupplementaryWidth))
    : timeSlot

  function demandForSlot(forTier, slot) {
    var p = ClockFormat.partsFor(forTier, root.timeFormat)
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
    onDateChanged: root.displayDate = date
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

  TextMetrics { id: prefixMetrics; font: prefixLabel.font; text: ClockFormat.stableDigits(root.prefixTimeText) }
  TextMetrics { id: secondsMetrics; font: prefixLabel.font; text: ClockFormat.stableDigits(root.secondsTimeText) }
  TextMetrics { id: suffixMetrics; font: prefixLabel.font; text: ClockFormat.stableDigits(root.suffixTimeText) }
  TextMetrics { id: weekdayMetrics; font: weekdayLabel.font; text: root.weekdayText }
  TextMetrics { id: dateMetrics; font: dateLabel.font; text: root.dateText }

  IslandButton {
    id: clockButton

    // KeyboardPanel forwards a click on this button while the calendar is
    // open, so left-click toggles it rather than closing and reopening, right-
    // click cycles the clock format, and middle-click opens the timezone menu.
    function triggerPress(button) {
      if (button === Qt.LeftButton) root.clickToggle()
      else if (button === Qt.RightButton) root.cycleFormatRequested()
      else if (button === Qt.MiddleButton) {
        if (root.opened) root.close()
        root.timezoneRequested()
      }
    }

    theme: root.theme
    active: root.opened
    onClicked: function(button) { triggerPress(button) }
    horizontalPadding: root.buttonPadding
    contentSpacing: 0
    reachTop: root.reach.top
    reachBottom: root.reach.bottom
    accessibleName: root.strings.t("clock").arg(root.now.toLocaleString(root.locale, "dddd d MMMM yyyy")).arg(root.timeText)

    // Flat on purpose: each part shows or hides on its own, so the row
    // re-measures as the tier changes (a hidden nested Row did not).
    // Within the time slot, prefix (HH:mm) stays unclipped and slides left as
    // the island expands symmetrically, while :ss reveals progressively in the
    // space opening on its right (and any trailing AM/PM shifts right).
    Row {
      id: timeContainer

      objectName: "clockTime"
      anchors.verticalCenter: parent.verticalCenter
      width: root.effectiveTimeSlot
      height: prefixLabel.implicitHeight
      spacing: 0

      Text {
        id: prefixLabel

        objectName: "clockTimePrefix"
        anchors.verticalCenter: parent.verticalCenter
        width: root.timeElided ? root.effectiveTimeSlot : root.prefixSlot
        horizontalAlignment: Text.AlignLeft
        elide: root.timeElided ? Text.ElideRight : Text.ElideNone
        textFormat: Text.PlainText
        text: root.timeElided ? root.timeText : root.prefixTimeText
        color: root.theme.foreground
        font.family: root.theme.monoFamily
        font.pixelSize: root.theme.timeSize
        font.weight: Font.DemiBold
        font.letterSpacing: root.theme.timeSize * 0.02
      }

      Item {
        id: secondsClip

        objectName: "clockTimeSecondsClip"
        anchors.verticalCenter: parent.verticalCenter
        width: root.secondsRevealWidth
        height: prefixLabel.implicitHeight
        visible: !root.timeElided && root.timeTextParts.expandable && width > 0
        clip: true

        Text {
          id: secondsLabel

          objectName: "clockTimeSeconds"
          x: 0
          anchors.verticalCenter: parent.verticalCenter
          opacity: Math.min(1, root.secondsRevealProgress * 1.4)
          textFormat: Text.PlainText
          text: root.secondsTimeText
          color: root.theme.foreground
          font: prefixLabel.font
        }
      }

      Text {
        id: suffixLabel

        objectName: "clockTimeSuffix"
        anchors.verticalCenter: parent.verticalCenter
        width: root.suffixSlot
        visible: !root.timeElided && root.suffixTimeText !== ""
        horizontalAlignment: Text.AlignLeft
        textFormat: Text.PlainText
        text: root.suffixTimeText
        color: root.theme.foreground
        font: prefixLabel.font
      }
    }

    Text {
      id: weekdayLabel

      objectName: "clockWeekday"
      anchors.verticalCenter: parent.verticalCenter
      visible: root.showWeekday
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
      visible: root.showDate
      leftPadding: root.showWeekday ? root.wordGap : root.partGap
      textFormat: Text.PlainText
      text: root.dateText
      color: root.theme.islandSecondaryText
      font.family: root.theme.textFamily
      font.pixelSize: root.theme.textSize
    }
  }
}
