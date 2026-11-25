pragma Singleton
import QtQuick

// Test double of Omarchy's Commons.Util: records what would have run.
QtObject {
  property var ran: []
  function execDetached(command) { ran = ran.concat([String(command)]) }
  function execArgv(argv) { ran = ran.concat([argv.join(" ")]) }
  function wheelSteps(accumulator, delta) {
    var total = accumulator + delta
    var steps = total >= 120 ? Math.floor(total / 120) : (total <= -120 ? Math.ceil(total / 120) : 0)
    return { steps: steps, remainder: total - steps * 120 }
  }
}
