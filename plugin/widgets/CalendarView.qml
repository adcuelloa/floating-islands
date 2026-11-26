pragma ComponentBehavior: Bound
import QtQuick
import "../components"
import "../logic/Calendar.js" as Calendar
import "../logic/ClockFormat.mjs" as ClockFormat

// The calendar panel's content, after the V2 design: the long weekday and
// date, a hairline, the month with previous/next buttons, and a six-week
// grid. Arrow keys move a day cursor (a week up and down), Page Up/Down a
// month, Home back to today, Escape asks to close. The cursor ring appears
// only once the keyboard is used.
FocusScope {
  id: root

  required property var theme
  required property var strings
  // A Date; the clock island's, so midnight rolls over without polling here.
  property date now: new Date()
  property string localeTag: "en-GB"
  property var weekStartDay: null

  signal closeRequested()

  readonly property var locale: Qt.locale(localeTag)
  readonly property var pattern: Calendar.patterns(localeTag)
  readonly property int weekStart: ClockFormat.normalizedWeekStart(weekStartDay, Calendar.weekStartFromLocale(locale.firstDayOfWeek))
  readonly property var today: Calendar.dayOf(now)

  property var selected: Calendar.dayOf(new Date())
  property bool cursorShown: false
  readonly property date viewDate: Calendar.dateAt(selected.year, selected.month, 1)
  readonly property var cells: Calendar.monthGrid(selected.year, selected.month, weekStart, today, selected)

  readonly property real s: theme.m.scale
  readonly property real cellHeight: Math.round(38 * s)
  readonly property real headHeight: Math.round(28 * s)
  readonly property real gap: Math.round(2 * s)

  // Back to today each time the panel opens.
  function reset() {
    root.selected = Calendar.dayOf(root.now)
    root.cursorShown = false
  }

  function command(name) {
    root.selected = Calendar.move(root.selected, root.today, name)
  }

  function stepMonth(direction) {
    root.command(direction < 0 ? "previousMonth" : "nextMonth")
  }

  implicitWidth: Math.round(308 * s)
  implicitHeight: column.implicitHeight
  focus: true

  Keys.onPressed: function(event) {
    var mirrored = LayoutMirroring.enabled
    var name = ""
    if (event.key === Qt.Key_Escape) {
      root.closeRequested()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Left) name = mirrored ? "right" : "left"
    else if (event.key === Qt.Key_Right) name = mirrored ? "left" : "right"
    else if (event.key === Qt.Key_Up) name = "up"
    else if (event.key === Qt.Key_Down) name = "down"
    else if (event.key === Qt.Key_PageUp) name = "previousMonth"
    else if (event.key === Qt.Key_PageDown) name = "nextMonth"
    else if (event.key === Qt.Key_Home) name = "today"
    if (!name) return
    root.cursorShown = true
    root.command(name)
    event.accepted = true
  }

  Column {
    id: column

    width: root.width
    spacing: Math.round(14 * root.s)

    Column {
      width: parent.width
      spacing: root.gap

      Text {
        objectName: "calendarWeekday"
        textFormat: Text.PlainText
        text: root.locale.dayName(root.now.getDay(), Locale.LongFormat)
        color: root.theme.secondaryText
        font.family: root.theme.textFamily
        font.pixelSize: Math.round(13 * root.theme.fontScale)
      }

      Text {
        textFormat: Text.PlainText
        text: root.now.toLocaleDateString(root.locale, root.pattern.longDate)
        color: root.theme.foreground
        font.family: root.theme.textFamily
        // From the size itself: reading font.pixelSize here is a binding loop.
        readonly property int size: Math.round(22 * root.theme.fontScale)

        font.pixelSize: size
        font.weight: Font.DemiBold
        font.letterSpacing: -0.01 * size
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: root.theme.border
    }

    Item {
      width: parent.width
      height: Math.round(44 * root.s)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.viewDate.toLocaleDateString(root.locale, root.pattern.monthTitle)
        color: root.theme.foreground
        font.family: root.theme.textFamily
        font.pixelSize: Math.round(14 * root.theme.fontScale)
        font.weight: Font.DemiBold
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.gap

        Repeater {
          model: [
            { direction: -1, key: "calendar.previous", path: "M15 6L9 12L15 18" },
            { direction: 1, key: "calendar.next", path: "M9 6L15 12L9 18" }
          ]

          IslandButton {
            id: navButton

            required property var modelData

            theme: root.theme
            minimumWidth: Math.round(44 * root.s)
            horizontalPadding: 0
            implicitHeight: Math.round(44 * root.s)
            accessibleName: root.strings.t(modelData.key)
            onClicked: root.stepMonth(modelData.direction)

            StrokeIcon {
              icon: ({ stroke: navButton.modelData.path })
              size: Math.round(18 * root.s)
              color: root.theme.foreground
            }
          }
        }
      }
    }

    Grid {
      id: grid

      readonly property real cellWidth: (width - 6 * columnSpacing) / 7

      width: parent.width
      columns: 7
      columnSpacing: root.gap
      rowSpacing: root.gap

      Repeater {
        model: Calendar.weekdayOrder(root.weekStart)

        Text {
          required property int modelData

          objectName: "calendarHeading"
          width: grid.cellWidth
          height: root.headHeight
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
          text: root.locale.dayName(modelData, root.pattern.weekdayFormat === "short" ? Locale.ShortFormat : Locale.NarrowFormat)
          color: root.theme.secondaryText
          font.family: root.theme.textFamily
          font.pixelSize: Math.round(12 * root.theme.fontScale)
        }
      }

      Repeater {
        model: root.cells

        Rectangle {
          id: cell

          required property var modelData

          width: grid.cellWidth
          height: root.cellHeight
          radius: Math.round(8 * root.s)
          color: modelData.today ? root.theme.accent : (dayPointer.containsMouse ? root.theme.hover : "transparent")
          border.width: root.cursorShown && modelData.selected ? Math.max(1, Math.round(1.5 * root.s)) : 0
          border.color: modelData.today ? root.theme.accentForeground : root.theme.accent

          Accessible.role: Accessible.Cell
          Accessible.name: root.locale.toString(Calendar.dateAt(modelData.year, modelData.month, modelData.day), "dddd d MMMM yyyy")

          Text {
            objectName: "calendarDay"
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: cell.modelData.day
            color: cell.modelData.today ? root.theme.accentForeground : (cell.modelData.outside ? root.theme.secondaryText : root.theme.foreground)
            font.family: root.theme.monoFamily
            font.pixelSize: Math.round(13 * root.theme.fontScale)
            font.weight: cell.modelData.today ? Font.DemiBold : Font.Normal
          }

          MouseArea {
            id: dayPointer

            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.selected = { year: cell.modelData.year, month: cell.modelData.month, day: cell.modelData.day }
          }
        }
      }

      WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) { if (event.angleDelta.y !== 0) root.stepMonth(event.angleDelta.y > 0 ? -1 : 1) }
      }
    }
  }
}
