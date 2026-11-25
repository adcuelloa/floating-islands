pragma Singleton
import QtQuick

// Test-only: every Process stub that starts, in order.
QtObject {
  property var log: []
  // A copy of each command as it started (one Process can start many times).
  property var commands: []

  function started(proc) {
    log = log.concat([proc])
    commands = commands.concat([Array.prototype.slice.call(proc.command || [])])
  }
  function last() { return log.length > 0 ? log[log.length - 1] : null }
  // The last started process whose command begins with `program`.
  function lastOf(program) {
    for (var i = log.length - 1; i >= 0; i--) if (log[i].command[0] === program) return log[i]
    return null
  }
  function clear() { log = []; commands = [] }
}
