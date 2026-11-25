pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import "../logic/ControlCenter.js" as Model

// Wi-Fi and Bluetooth for the Control Center's tiles. State is read from
// Quickshell's Networking (NetworkManager) and Bluetooth (BlueZ) services,
// whose properties change on their own when anything else (a panel, nmcli,
// rfkill, a hardware switch) changes them. Each provider gives a tile
// { available, blocked, on, connected, detail, count }, request(on, done)
// and refresh(). request runs the command that asks for that state
// (logic/ControlCenter.js radioCommand) and calls done(ok) with its exit
// status; a command still running after commandLimit is stopped and fails.
//
// Switching a radio off can take its device out of both services (see
// ControlCenter.js absent()), so the rfkill switches are read too: one
// read-only `rfkill --json` run, only when something changes (the services'
// devices or radio state, a command's exit, the panel opening), never on a
// timer. Nothing is read while inactive.
Scope {
  id: root

  property bool active: false
  property int commandLimit: 20000

  // The last rfkill read: { wlan, bluetooth } of rfkillState, or nulls.
  property var rfkill: ({ wlan: null, bluetooth: null })

  readonly property var wifiDevices: {
    if (!root.active) return []
    var devices = Networking.devices ? Networking.devices.values : []
    var out = []
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (!d || d.type !== DeviceType.Wifi) continue
      out.push({ connected: d.connected === true, network: Model.connectedNetwork(d.networks ? d.networks.values : []) })
    }
    return out
  }
  readonly property var bluetoothAdapters: {
    if (!root.active) return []
    var adapters = Bluetooth.adapters ? Bluetooth.adapters.values : []
    var out = []
    for (var i = 0; i < adapters.length; i++) if (adapters[i]) out.push({ enabled: adapters[i].enabled === true })
    return out
  }

  readonly property var wifi: QtObject {
    readonly property var state: root.active
      ? Model.wifi(Networking.backend === NetworkBackendType.NetworkManager, root.wifiDevices,
          Networking.wifiEnabled, Networking.wifiHardwareEnabled, root.rfkill.wlan)
      : Model.wifi(false, [], false, true, null)
    readonly property bool available: state.available
    readonly property bool blocked: state.blocked
    readonly property bool on: state.on
    readonly property bool connected: state.connected
    readonly property string detail: state.detail
    readonly property int count: state.count

    function request(on, done) { return wifiRequest.ask(on, done) }
    // Deferred: both providers ask on every panel open; one read serves both.
    function refresh() { Qt.callLater(root.refresh) }
  }

  readonly property var bluetooth: QtObject {
    readonly property var state: Model.bluetooth(root.bluetoothAdapters, root.active ? root.rfkill.bluetooth : null)
    readonly property bool available: state.available
    readonly property bool blocked: state.blocked
    readonly property bool on: state.on
    readonly property bool connected: state.connected
    readonly property string detail: state.detail
    readonly property int count: state.count

    function request(on, done) { return bluetoothRequest.ask(on, done) }
    // Deferred: both providers ask on every panel open; one read serves both.
    function refresh() { Qt.callLater(root.refresh) }
  }

  // Re-reads rfkill once, after the current read if one is running.
  property bool rereadRfkill: false
  function refresh() {
    if (!root.active) return
    if (rfkillRead.running) { root.rereadRfkill = true; return }
    rfkillRead.running = true
  }

  // What changes rfkill's meaning for the tiles: devices coming and going,
  // the radios' state, activation. Each schedules one read.
  readonly property string watched: root.active
    ? [root.wifiDevices.length, root.bluetoothAdapters.length, Networking.wifiEnabled,
       Networking.wifiHardwareEnabled, root.bluetooth.on].join(",")
    : ""
  onWatchedChanged: if (root.active) Qt.callLater(root.refresh)
  onActiveChanged: if (!root.active) root.rfkill = { wlan: null, bluetooth: null }

  Process {
    id: rfkillRead

    command: Model.RFKILL_READ
    stdout: StdioCollector { id: rfkillText }

    onExited: function(exitCode) {
      var text = exitCode === 0 ? rfkillText.text : ""
      root.rfkill = root.active
        ? { wlan: Model.rfkillState(text, "wlan"), bluetooth: Model.rfkillState(text, "bluetooth") }
        : { wlan: null, bluetooth: null }
    }
    onRunningChanged: if (!running && root.rereadRfkill) { root.rereadRfkill = false; Qt.callLater(root.refresh) }
  }

  component Request: Process {
    id: proc

    required property string kind
    // The caller's callback while a request runs.
    property var done: null

    // One request at a time; false when one is already running.
    function ask(on, callback) {
      if (proc.running || proc.done !== null) return false
      proc.done = typeof callback === "function" ? callback : function() {}
      proc.command = Model.radioCommand(proc.kind, on)
      proc.running = true
      limit.restart()
      return true
    }

    function finish(ok) {
      limit.stop()
      var callback = proc.done
      proc.done = null
      if (callback) callback(ok)
      root.refresh()
    }

    onExited: function(exitCode) { proc.finish(exitCode === 0) }
    // A command that could not start, or was stopped, ends without an exit
    // status (a stopped one may report one first, which finishes it).
    onRunningChanged: if (!proc.running && proc.done !== null) proc.finish(false)

    // A command that hangs is stopped (SIGTERM) and fails, so the radio's
    // tile is not refused forever.
    readonly property Timer limit: Timer {
      interval: root.commandLimit
      onTriggered: if (proc.running) proc.running = false
    }
  }

  Request { id: wifiRequest; kind: "wifi" }
  Request { id: bluetoothRequest; kind: "bluetooth" }
}
