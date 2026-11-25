pragma ComponentBehavior: Bound
import QtQuick
import qs.Ui
import "../logic/ControlCenter.js" as Model

// The Control Center popover: Omarchy's KeyboardPanel, as the calendar uses
// it. It grows out of the entry button on that button's output, takes
// keyboard focus only while open, keeps to the screen edges, closes on
// Escape or an outside click, and hands over to another panel opening from
// the bar. Its content is built on first open.
KeyboardPanel {
  id: panel

  // Set by ControlCenterButton right after loading (a URL-loaded item cannot
  // take required properties).
  property var theme: null
  property var strings: null
  property var services: ({})
  property var links: []
  property var audioSink: null
  property string audioPanelId: ""
  property var wifi: null
  property var bluetooth: null
  property string wifiPanelId: ""
  property string bluetoothPanelId: ""
  property var powerProfile: null
  property var brightness: null
  // Opens a hosted widget's full panel (the bar's routing); the hand-over
  // closes this one.
  property var summon: null

  readonly property real s: theme ? theme.m.scale : 1

  centerOnBar: false
  padding: Math.round(16 * s)
  // A quarter of the output, 340-420 px (scaled), capped at what the output
  // has (logic/ControlCenter.js cardWidth, KeyboardPanel's fitting).
  contentWidth: panel.fittedContentWidth(Model.cardWidth(panel.screenW, s))
  contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)
  focusTarget: panel.loadedContent

  // Back to the first control on every open. Called by name: the content is
  // built from a Component, so its type is only known at run time.
  onOpenChanged: {
    var view = panel.loadedContent
    var name = "reset"
    if (open && view && typeof view[name] === "function") view[name]()
  }

  content: panel.theme && panel.strings ? panel.mainView : null

  readonly property Component mainView: Component {
    ControlCenterView {
      theme: panel.theme
      strings: panel.strings
      services: panel.services
      links: panel.links
      audioSink: panel.audioSink
      audioPanelId: panel.audioPanelId
      wifi: panel.wifi
      bluetooth: panel.bluetooth
      wifiPanelId: panel.wifiPanelId
      bluetoothPanelId: panel.bluetoothPanelId
      powerProfile: panel.powerProfile
      brightness: panel.brightness
      width: parent ? parent.width : implicitWidth
      onCloseRequested: panel.close()
      onPanelRequested: function(id) { if (typeof panel.summon === "function") panel.summon(id) }
      Component.onCompleted: reset()
    }
  }
}
