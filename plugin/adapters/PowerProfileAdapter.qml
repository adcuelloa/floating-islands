pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../logic/ControlCenter.js" as Model

// The power profile for the Control Center. State comes from
// power-profiles-daemon:
//   - one read-only call for the profiles it offers, the active one and any
//     degradation (logic/ControlCenter.js PROFILE_READ). It uses
//     --auto-start=no, so it never starts a daemon that is not running;
//     a failed read means unavailable;
//   - Quickshell's PowerProfiles.profileChanged for changes made anywhere
//     (Omarchy's menu or panel, its automatic AC/battery switch, the CLI).
//     The shell's own battery service already uses that singleton, so this
//     adds no activation; it is only touched while active.
// The read runs on activation, when the panel opens, after our command
// exits and when the power source changes; never on a timer.
//
// request(profile, done) runs Omarchy's helper for the current power source
// (logic/ControlCenter.js profileCommand), which also remembers the choice
// for that source, and calls done(exitCode); -1 when it could not start or
// was stopped at commandLimit. It returns the source asked for, or "" when
// nothing was started (unavailable, not offered, or a request running).
// Nothing here stores a preference or a profile of its own.
Scope {
  id: root

  property bool active: false
  property int commandLimit: 20000

  // The last daemon read (ControlCenter.js parseProfiles), or null.
  property var daemon: null

  readonly property bool available: root.active && !!root.daemon && root.daemon.available
  readonly property var profiles: root.available ? root.daemon.profiles : []
  readonly property string current: root.available ? root.daemon.active : ""
  readonly property string degraded: root.available ? root.daemon.degraded : ""
  readonly property bool onBattery: root.active && UPower.onBattery === true
  readonly property string source: root.onBattery ? "battery" : "ac"
  readonly property bool busy: setProcess.running || setProcess.done !== null

  function request(profile, done) {
    if (!root.available || root.busy) return ""
    var command = Model.profileCommand(root.source, profile, root.profiles)
    if (!command.length) return ""
    setProcess.done = typeof done === "function" ? done : function() {}
    setProcess.command = command
    setProcess.running = true
    limit.restart()
    return command[1]
  }

  property bool rereadPending: false
  function refresh() {
    if (!root.active) return
    if (readProcess.running) { root.rereadPending = true; return }
    readProcess.running = true
  }

  onActiveChanged: {
    if (root.active) Qt.callLater(root.refresh)
    else root.daemon = null
  }
  onOnBatteryChanged: if (root.active) Qt.callLater(root.refresh)

  // A change made anywhere, as the daemon signals it.
  Connections {
    target: root.active ? PowerProfiles : null
    function onProfileChanged() {
      if (!root.daemon || !root.daemon.available) return
      var name = Model.profileName(PowerProfiles.profile)
      if (root.daemon.profiles.indexOf(name) === -1) return
      root.daemon = { available: true, profiles: root.daemon.profiles, active: name, degraded: root.daemon.degraded }
    }
  }

  Process {
    id: readProcess

    command: Model.PROFILE_READ
    stdout: StdioCollector { id: readText }

    onExited: function(exitCode) {
      root.daemon = root.active ? Model.parseProfiles(exitCode === 0 ? readText.text : "") : null
    }
    onRunningChanged: if (!running && root.rereadPending) { root.rereadPending = false; Qt.callLater(root.refresh) }
  }

  Process {
    id: setProcess

    // The caller's callback while a request runs.
    property var done: null

    function finish(code) {
      limit.stop()
      var callback = setProcess.done
      setProcess.done = null
      if (callback) callback(code)
      root.refresh()
    }

    onExited: function(exitCode) { setProcess.finish(exitCode) }
    // A command that could not start, or was stopped, ends without an exit
    // status (a stopped one may report one first, which finishes it).
    onRunningChanged: if (!running && setProcess.done !== null) setProcess.finish(-1)
  }

  // A helper that hangs is stopped (SIGTERM) and reported as -1.
  Timer {
    id: limit
    interval: root.commandLimit
    onTriggered: if (setProcess.running) setProcess.running = false
  }
}
