import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons as Commons
import "../logic/Workspaces.js" as Workspaces

// Hyprland workspace state for one output, in the shape the workspace strip
// draws (logic/Workspaces.js), and the two things it can ask for: show a
// workspace, or step along the row.
Scope {
  id: root

  required property var screen

  readonly property var monitor: screen ? Hyprland.monitorFor(screen) : null
  readonly property string monitorName: monitor ? String(monitor.name || "") : ""
  readonly property int activeId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1

  property var blocks: ({})
  readonly property int block: Workspaces.blockFor(blocks, monitorName, activeId)

  // Reading each workspace's toplevels here makes the list follow windows
  // opening and closing, not only workspaces appearing.
  readonly property var snapshot: {
    var values = Hyprland.workspaces.values
    var out = []
    for (var i = 0; i < values.length; i++) {
      var ws = values[i]
      out.push({
        id: ws.id,
        monitorName: ws.monitor ? String(ws.monitor.name || "") : "",
        windows: ws.toplevels ? ws.toplevels.values.length : 0
      })
    }
    return out
  }

  readonly property var entries: Workspaces.entries(block, snapshot, monitorName, activeId)

  function focus(id) {
    var expression = Workspaces.focusDispatch(id, root.block, root.monitorName)
    if (expression) Commons.Util.execArgv(["hyprctl", "dispatch", expression])
  }

  property real wheelRemainder: 0

  function scroll(delta) {
    var wheel = Commons.Util.wheelSteps(root.wheelRemainder, delta)
    root.wheelRemainder = wheel.remainder
    var ids = root.entries.map(function(entry) { return entry.id })
    var target = Workspaces.scrollTarget(ids, root.activeId, wheel.steps)
    if (target > 0) root.focus(target)
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.blocks = Workspaces.parseBlocks(text())
    onLoadFailed: root.blocks = ({})
  }

  // Quickshell credits a workspace switch to the focused monitor and misses
  // moves between monitors, so ask Hyprland again after those events, as the
  // stock widget does. Only the focused output asks after a plain switch.
  Connections {
    target: Hyprland

    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      var switched = name === "workspacev2" && root.monitor !== null && root.monitor.focused
      if (switched || name === "moveworkspacev2" || name === "changeworkspaceid") {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
      }
    }
  }
}
