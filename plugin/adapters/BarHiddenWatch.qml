import QtQuick
import Quickshell
import Quickshell.Io

// `omarchy toggle bar` hides the bar by creating a flag file. FileView cannot
// watch a file that does not exist yet, so the toggles directory is watched
// and the flag re-probed, as the stock bar does.
Scope {
  id: root

  property bool hidden: false

  readonly property string togglesDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/toggles"

  function probe() {
    probeProcess.running = true
  }

  Process {
    id: probeProcess

    running: true
    command: ["test", "-e", root.togglesDir + "/bar-off"]
    onExited: function(exitCode) { root.hidden = exitCode === 0 }
  }

  FileView {
    path: root.togglesDir
    watchChanges: true
    printErrors: false
    onFileChanged: root.probe()
  }
}
