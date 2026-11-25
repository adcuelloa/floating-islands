pragma ComponentBehavior: Bound
import QtQuick
import qs.Ui

// The calendar popover: Omarchy's KeyboardPanel, which grows out of the clock
// island on that island's output, takes keyboard focus while open, keeps to
// the screen edges, closes on an outside click, and hands over to another
// panel opening from the bar. Its content is built on first open.
KeyboardPanel {
  id: panel

  // Set by ClockIsland right after loading (a URL-loaded item cannot take
  // required properties).
  property var theme: null
  property var strings: null
  property var island: null
  property date now: new Date()
  property string localeTag: "en-GB"

  readonly property real s: theme ? theme.m.scale : 1

  owner: island
  centerOnBar: false
  padding: Math.round(16 * s)
  contentWidth: panel.fittedContentWidth(Math.round(340 * s))
  contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)
  focusTarget: panel.loadedContent

  // Back to today on every open. Called by name: the content is built from a
  // Component, so its type is only known at run time.
  onOpenChanged: {
    var view = panel.loadedContent
    var calls = open && view ? ["reset"] : []
    for (var i = 0; i < calls.length; i++) if (typeof view[calls[i]] === "function") view[calls[i]]()
  }

  content: panel.theme && panel.strings ? panel.calendarView : null

  readonly property Component calendarView: Component {
    CalendarView {
      theme: panel.theme
      strings: panel.strings
      now: panel.now
      localeTag: panel.localeTag
      width: parent ? parent.width : implicitWidth
      onCloseRequested: panel.close()
      Component.onCompleted: reset()
    }
  }
}
