pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../logic/ControlCenter.js" as Model

// The built-in display's brightness for one bar surface's output.
//
// Device: only for an internal output (logic/ControlCenter.js
// backlightOutput); the device is the one `omarchy-hw-display` prints,
// which is the one Omarchy's helper and brightness keys write for an
// internal output. Any other output reads as unavailable and nothing is
// read, watched or run for it.
//
// Reading: `actual_brightness` (what the hardware reports; the kernel
// notifies it for every change, whatever its source) and `max_brightness`
// once per device. A watch-only FileView never reads, so its inotify watch
// stays in place: Quickshell recreates a FileView's watch on every
// reload(), which a reader does. A notification starts one read; one that
// arrives during a read asks for a single read after it. Reads also run on
// activation, when the panel opens (refresh) and after our own write. No
// timer reads anything.
//
// Writing: setPercent() keeps only the latest percent asked for and runs
// Omarchy's helper with fixed arguments (Model.brightnessCommand). A send
// opens a window of `debounce` ms: the first request after a quiet moment
// goes out at once (a key step is not delayed), and what is asked during
// the window or while the helper runs is held, only the latest kept, and
// sent when both are over. So a drag sends at most one value per window,
// never two helpers at once, and always its last value. What a write came to is decided by the
// observed level (Model.brightnessOutcome), never by the exit status alone.
// A change of output or deactivation drops anything asked for; a helper
// still running then finishes unobserved (its exit is ignored) and is
// stopped at `commandLimit`.
Scope {
  id: root

  property bool active: false
  // The bar surface's output name (e.g. "eDP-1").
  property string output: ""
  property int debounce: 180
  property int settleGrace: 1500
  property int commandLimit: 10000

  readonly property bool supported: root.active && Model.backlightOutput(root.output)
  // From omarchy-hw-display; "" until known, or when the device went away.
  property string device: ""
  property int max: -1
  property int raw: -1
  readonly property string devicePath: root.supported && root.device !== "" ? "/sys/class/backlight/" + root.device : ""
  readonly property bool available: root.devicePath !== "" && root.max > 0 && root.raw >= 0
  // The observed level, -1 when unavailable.
  readonly property int percent: root.available ? Model.brightnessPercent(root.raw, root.max) : -1

  // The latest percent asked for and not yet settled, -1 when none.
  property int desired: -1
  readonly property bool pending: root.desired >= 0
  // "", "failed" or "unconfirmed": how the last request ended.
  property string outcome: ""
  // The write in flight or settling: { target, exited, code }, or null.
  property var write: null
  property bool graceOver: false
  // `desired` has not been sent yet (held by the window or the helper).
  property bool unsent: false
  // Bumped when the output changes or the adapter stops: a helper's exit
  // from before then is ignored.
  property int generation: 0

  // Asks for `value` percent (rounded, 1-100). False when nothing was asked.
  function setPercent(value) {
    if (!root.available) return false
    var p = Model.clampBrightness(value)
    if (p < 0) return false
    root.desired = p
    root.outcome = ""
    root.unsent = true
    root.flush()
    return true
  }

  // Rereads the level, and finds the device again if it is not known.
  function refresh() {
    if (!root.supported) return
    if (root.device === "") { root.resolve(); return }
    maxReader.reload()
    root.read()
  }

  function resolve() {
    if (!root.supported || deviceProcess.running) return
    deviceProcess.running = true
  }

  property bool reading: false
  property bool rereadPending: false
  function read() {
    if (root.devicePath === "") return
    if (root.reading) { root.rereadPending = true; return }
    root.reading = true
    actualReader.reload()
  }

  // Sends `desired` if it is unsent and neither the window nor the helper
  // is running; called on a request, at the window's end and on an exit.
  function flush() {
    if (!root.unsent || root.desired < 0) return
    if (setProcess.running || sendWindow.running) return
    var command = Model.brightnessCommand(root.output, root.desired)
    if (!command.length) { root.settle("failed"); return }
    root.unsent = false
    sendWindow.restart()
    root.graceOver = false
    grace.stop()
    root.write = { target: root.desired, exited: false, code: null }
    setProcess.sentGeneration = root.generation
    setProcess.awaiting = true
    setProcess.command = command
    setProcess.running = true
    limit.restart()
  }

  function helperExited(code) {
    limit.stop()
    // An exit from before an output change: only free the way for a newer request.
    if (setProcess.sentGeneration !== root.generation) { root.flush(); return }
    root.read()
    // A newer value is waiting: it decides, not this one.
    if (root.unsent) { root.flush(); return }
    if (!root.write) return
    root.write = { target: root.write.target, exited: true, code: code }
    root.graceOver = false
    grace.restart()
    root.evaluate()
  }

  function evaluate() {
    if (!root.write || root.unsent || setProcess.running) return
    var result = Model.brightnessOutcome(root.write, root.percent, root.graceOver)
    if (result !== "pending") root.settle(result === "done" ? "" : result)
  }

  function settle(outcome) {
    root.write = null
    root.desired = -1
    root.unsent = false
    grace.stop()
    root.outcome = outcome
  }

  function reset() {
    root.generation++
    sendWindow.stop()
    grace.stop()
    limit.stop()
    root.write = null
    root.desired = -1
    root.unsent = false
    root.outcome = ""
    root.reading = false
    root.rereadPending = false
    root.raw = -1
    root.max = -1
    root.device = ""
    if (deviceProcess.running) deviceProcess.running = false
  }

  Component.onCompleted: if (root.supported) Qt.callLater(root.resolve)
  onSupportedChanged: { root.reset(); if (root.supported) Qt.callLater(root.resolve) }
  onOutputChanged: { root.reset(); if (root.supported) Qt.callLater(root.resolve) }
  onDevicePathChanged: { root.reading = false; root.rereadPending = false }
  onPercentChanged: { if (root.write) root.evaluate(); else if (!root.pending) root.outcome = "" }

  Process {
    id: deviceProcess

    command: ["omarchy-hw-display"]
    stdout: StdioCollector { id: deviceText }
    onExited: function(exitCode) {
      var found = exitCode === 0 ? Model.backlightDevice(deviceText.text) : ""
      if (!root.supported || found === "") return
      if (found === root.device) { maxReader.reload(); root.read(); return }
      root.raw = -1
      root.max = -1
      root.device = found
    }
  }

  // Reads actual_brightness on demand; never watches.
  FileView {
    id: actualReader

    path: root.devicePath !== "" ? root.devicePath + "/actual_brightness" : ""
    printErrors: false
    onLoaded: {
      root.reading = false
      root.raw = Model.backlightValue(actualReader.text())
      // Not from inside loaded: Quickshell drops the finishing read only
      // after this signal, so a reload() here would be ignored and leave
      // `reading` set for good (every later change then lost).
      if (root.rereadPending) { root.rereadPending = false; Qt.callLater(root.read) }
    }
    // Unreadable or gone: unavailable until the device is found again
    // (the next refresh).
    onLoadFailed: {
      root.reading = false
      root.rereadPending = false
      root.raw = -1
      root.device = ""
    }
  }

  // Watches actual_brightness; never reads, so its watch is never rebuilt.
  FileView {
    id: watcher

    path: actualReader.path
    preload: false
    watchChanges: true
    printErrors: false
    onFileChanged: root.read()
  }

  FileView {
    id: maxReader

    path: root.devicePath !== "" ? root.devicePath + "/max_brightness" : ""
    printErrors: false
    onLoaded: root.max = Model.backlightValue(maxReader.text())
    onLoadFailed: root.max = -1
  }

  Process {
    id: setProcess

    property int sentGeneration: -1
    property bool awaiting: false

    function done(code) {
      if (!setProcess.awaiting) return
      setProcess.awaiting = false
      // Later: Quickshell still reports running while it signals the exit.
      Qt.callLater(root.helperExited, code)
    }

    onExited: function(exitCode) { setProcess.done(exitCode) }
    // Could not start, or stopped at the limit: no exit status.
    onRunningChanged: if (!running) setProcess.done(-1)
  }

  // The send window: started by each send, it holds later requests.
  Timer {
    id: sendWindow
    interval: root.debounce
    onTriggered: root.flush()
  }
  Timer {
    id: grace
    interval: root.settleGrace
    onTriggered: { root.graceOver = true; root.evaluate() }
  }
  // A helper that hangs is stopped (SIGTERM) and counts as failed.
  Timer {
    id: limit
    interval: root.commandLimit
    onTriggered: if (setProcess.running) setProcess.running = false
  }
}
