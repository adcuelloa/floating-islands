import QtQuick
import "../components"
import "../theme/Icons.js" as Icons

// The Control Center's entry, at the start of the status island. It owns the
// panel's open state and follows the shell's popout contract (open(), close(),
// closeForPopoutSwitch(), popoutSwitchClosing), as the clock island does for
// the calendar. Its button is a registered click target, so a click on it
// while another panel is open hands over in one click.
IslandButton {
  id: root

  required property var strings
  // The bar facade the panel coordinates through; without one (tests) the
  // panel is not built.
  property var bar: null
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
  property var summon: null
  property var reach: ({ top: 0, bottom: 0 })

  property bool opened: false
  property bool popoutSwitchClosing: false

  function open() { if (panelLoader.status === Loader.Ready) root.opened = true }
  function close() { root.opened = false }
  function toggle() { root.opened ? root.close() : root.open() }
  function closeForPopoutSwitch() {
    root.popoutSwitchClosing = true
    root.close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }
  // KeyboardPanel forwards a click on this button while a panel is open.
  function triggerPress(button) { if (button === Qt.LeftButton) root.toggle() }

  active: root.opened
  minimumWidth: theme.m.statusSlot
  horizontalPadding: 0
  reachTop: root.reach.top
  reachBottom: root.reach.bottom
  accessibleName: root.strings.t("controlCenter.open")
  onClicked: function(button) { if (button === Qt.LeftButton) root.toggle() }

  StrokeIcon {
    icon: Icons.controlCenter
    size: Math.round(18 * root.theme.m.scale)
    color: root.theme.foreground
  }

  // Loaded by URL with its required properties given at construction, once
  // there is a bar to coordinate with (as the clock island loads the calendar).
  readonly property Loader panelLoader: Loader {
    onLoaded: {
      var panel = item
      var bindings = {
        services: function() { return root.services },
        links: function() { return root.links },
        audioSink: function() { return root.audioSink },
        audioPanelId: function() { return root.audioPanelId },
        wifi: function() { return root.wifi },
        bluetooth: function() { return root.bluetooth },
        wifiPanelId: function() { return root.wifiPanelId },
        bluetoothPanelId: function() { return root.bluetoothPanelId },
        powerProfile: function() { return root.powerProfile },
        brightness: function() { return root.brightness },
        summon: function() { return root.summon },
        open: function() { return root.opened }
      }
      for (var name in bindings) panel[name] = Qt.binding(bindings[name])
    }
  }

  function loadPanel() {
    if (!root.bar || panelLoader.status !== Loader.Null) return
    panelLoader.setSource(Qt.resolvedUrl("ControlCenterPanel.qml"), {
      anchorItem: root,
      bar: root.bar,
      owner: root,
      theme: root.theme,
      strings: root.strings
    })
  }

  onBarChanged: {
    if (!root.bar) return
    root.bar.registerClickTarget(root)
    root.loadPanel()
  }
  Component.onDestruction: if (root.bar) root.bar.unregisterClickTarget(root)
}
