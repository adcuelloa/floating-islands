import QtQuick

// Stands in for Quickshell's Process: nothing is run. Starting one hands it
// to ProcessTrap, where a test reads its command and ends it with testExit()
// (an exit status) or testFailToStart() (stops with no exit status, as a
// missing binary does, or one stopped with `running = false`).
QtObject {
  id: proc

  property var command: []
  property bool running: false
  property QtObject stdout: null

  signal exited(int exitCode, int exitStatus)

  function testExit(code) {
    proc.exited(code, 0)
    proc.running = false
  }

  function testFailToStart() { proc.running = false }

  onRunningChanged: if (running) ProcessTrap.started(proc)
}
