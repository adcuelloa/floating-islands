import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../logic/Title.js" as Title

// The window a given output is showing. The focused window belongs to the
// output it is on; every other output keeps the last window that was focused
// on the workspace it shows, so a second monitor does not mirror the first.
Scope {
  id: root

  required property var screen

  readonly property var monitor: screen ? Hyprland.monitorFor(screen) : null
  readonly property var workspace: monitor ? monitor.activeWorkspace : null
  readonly property int workspaceId: workspace ? workspace.id : -1
  readonly property int windowCount: workspace && workspace.toplevels ? workspace.toplevels.values.length : 0

  readonly property var focused: Hyprland.activeToplevel
  readonly property bool focusedHere: !!focused && !!focused.monitor && !!monitor && focused.monitor.name === monitor.name

  // workspace id -> { title, appId }, filled while a window is focused here.
  property var remembered: ({})

  function appIdOf(toplevel) {
    if (!toplevel) return ""
    if (toplevel.wayland && toplevel.wayland.appId) return String(toplevel.wayland.appId)
    var ipc = toplevel.lastIpcObject
    return ipc && ipc["class"] ? String(ipc["class"]) : ""
  }

  readonly property var current: {
    if (root.windowCount === 0) return { title: "", appId: "", empty: true }
    if (root.focusedHere) return { title: String(root.focused.title || ""), appId: root.appIdOf(root.focused), empty: false }
    var known = root.remembered[root.workspaceId]
    if (known) return { title: known.title, appId: known.appId, empty: false }
    var first = root.workspace.toplevels.values[0]
    return { title: String(first.title || ""), appId: root.appIdOf(first), empty: false }
  }

  readonly property bool empty: current.empty
  readonly property string title: Title.displayTitle(current.title, current.appId)
  readonly property string kind: current.empty ? "empty" : Title.appKind(current.appId)
  // The application's own icon, as Omarchy's dock finds it; "" falls back to
  // the symbol for `kind`. Reading the entry count re-resolves once desktop
  // entries finish loading.
  readonly property string iconSource: {
    var loaded = DesktopEntries.applications.values.length
    if (current.empty || !current.appId || loaded === 0) return ""
    return Title.appIconSource(DesktopEntries.heuristicLookup(current.appId),
      function(name) { return Quickshell.iconPath(name, true) })
  }

  onCurrentChanged: {
    if (!root.focusedHere || root.workspaceId < 0 || root.current.empty) return
    var next = ({})
    for (var key in root.remembered) next[key] = root.remembered[key]
    next[root.workspaceId] = { title: root.current.title, appId: root.current.appId }
    root.remembered = next
  }
}
