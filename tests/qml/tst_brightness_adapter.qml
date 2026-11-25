import QtQuick
import QtTest
import Quickshell.Io
import "../../plugin/adapters"

// adapters/BrightnessAdapter.qml against the FileView and Process stubs:
// sysfs files come from FileTrap, omarchy-hw-display and the helper from
// ProcessTrap. Nothing real is read, watched or written.
Item {
  id: scene

  readonly property string dir: "/sys/class/backlight/intel_backlight"
  readonly property string actual: dir + "/actual_brightness"
  readonly property string maxPath: dir + "/max_brightness"

  Component {
    id: adapterComponent
    BrightnessAdapter {
      active: true
      output: "eDP-1"
      debounce: 40
      settleGrace: 150
      commandLimit: 400
    }
  }

  TestCase {
    name: "BrightnessAdapter"
    when: windowShown

    property var a: null

    function init() {
      ProcessTrap.clear()
      FileTrap.reset()
      FileTrap.setFile(scene.actual, "57600\n")
      FileTrap.setFile(scene.maxPath, "96000\n")
    }

    function cleanup() {
      if (a) { a.destroy(); a = null }
      wait(0)
    }

    function hwDisplay() {
      tryVerify(function() { var p = ProcessTrap.lastOf("omarchy-hw-display"); return p !== null && p.running }, 1000)
      return ProcessTrap.lastOf("omarchy-hw-display")
    }

    function answerDevice(name, code) {
      var p = hwDisplay()
      p.stdout.text = name
      p.testExit(code === undefined ? 0 : code)
    }

    function make(props) {
      a = createTemporaryObject(adapterComponent, scene, props || {})
      verify(a !== null)
      return a
    }

    function ready(props) {
      make(props)
      answerDevice("intel_backlight\n")
      tryCompare(a, "available", true, 1000)
      return a
    }

    function helper() {
      tryVerify(function() { var p = ProcessTrap.lastOf("omarchy-brightness-display"); return p !== null && p.running }, 1000)
      return ProcessTrap.lastOf("omarchy-brightness-display")
    }

    // The percents sent to the helper, in order ("70%", ...).
    function sent() {
      return ProcessTrap.commands.filter(function(c) { return c[0] === "omarchy-brightness-display" })
                                 .map(function(c) { return c[4] })
    }
    function helperCount() { return sent().length }

    // Holds the send window open until endWindow(), so a test decides when
    // it ends instead of racing a timer (changing a running Timer's
    // interval restarts it).
    function holdWindow() { a.debounce = 600000 }
    function endWindow() { a.debounce = 1 }
    function observe(percent) { FileTrap.change(scene.actual, String(percent * 960)) }

    // ----------------------------------------------------------- reading

    function test_initialValue() {
      ready()
      compare(a.device, "intel_backlight")
      compare(a.max, 96000)
      compare(a.raw, 57600)
      compare(a.percent, 60)
      compare(a.pending, false)
      compare(FileTrap.watchers(scene.actual), 1, "one watch on actual_brightness")
      compare(FileTrap.watchers(scene.dir + "/brightness"), 0, "never brightness")
      compare(helperCount(), 0, "nothing written")
    }

    function test_hardwareRounding() {
      FileTrap.setFile(scene.actual, "7")
      FileTrap.setFile(scene.maxPath, "15")
      ready()
      compare(a.percent, 47)
    }

    function test_changeNotificationRereads() {
      ready()
      var before = FileTrap.reads(scene.actual)
      FileTrap.change(scene.actual, "52800\n")
      tryCompare(a, "percent", 55, 1000)
      compare(FileTrap.reads(scene.actual), before + 1, "one read per notification")
    }

    // Notifications during a read ask for one read after it, not one each.
    function test_rapidEventsCoalesce() {
      ready()
      FileTrap.autoSettle = false
      var before = FileTrap.reads(scene.actual)
      FileTrap.change(scene.actual, "48000")
      FileTrap.change(scene.actual, "43200")
      FileTrap.change(scene.actual, "38400")
      FileTrap.settle()
      wait(0) // the reread is queued after the loaded handler
      FileTrap.settle()
      wait(0)
      FileTrap.settle()
      compare(a.percent, 40, "the last value")
      compare(FileTrap.reads(scene.actual), before + 2, "three notifications, two reads")
      compare(a.reading, false)
    }

    // Live regression (M5 trial, 2026-11-03): the panel opens with two
    // refreshes back to back; the second waits for the first read. Its
    // reread was a reload() from inside loaded, which Quickshell ignores,
    // so `reading` stayed set and every later change was lost.
    function test_overlappingRefreshesKeepWatching() {
      ready()
      a.refresh()
      a.refresh()
      tryCompare(a, "reading", false, 1000)
      wait(20)
      compare(a.reading, false, "the coalesced reread completed")
      FileTrap.change(scene.actual, "62400\n")
      tryCompare(a, "percent", 65, 1000)
      FileTrap.change(scene.actual, "57600\n")
      tryCompare(a, "percent", 60, 1000)
    }

    function test_missedNotificationCaughtOnRefresh() {
      ready()
      FileTrap.setFile(scene.actual, "28800")
      wait(100)
      compare(a.percent, 60, "no notification, no read: nothing polls")
      a.refresh()
      tryCompare(a, "percent", 30, 1000)
      compare(FileTrap.watchers(scene.actual), 1, "refresh adds no watch")
    }

    function test_noPolling() {
      ready()
      var before = FileTrap.reads(scene.actual)
      wait(500)
      compare(FileTrap.reads(scene.actual), before, "no read without a reason")
      compare(ProcessTrap.log.length, 1, "only the device lookup ran")
    }

    function test_repeatedOpensKeepOneWatch() {
      ready()
      for (var i = 0; i < 5; i++) a.refresh()
      wait(50)
      compare(FileTrap.watchers(scene.actual), 1)
      compare(ProcessTrap.log.length, 1, "the device is known: no new lookup")
    }

    // ----------------------------------------------------------- outputs

    function test_externalOutputIsUnavailable() {
      make({ output: "HDMI-A-1" })
      wait(100)
      compare(a.available, false)
      compare(ProcessTrap.log.length, 0, "nothing run for an external output")
      compare(FileTrap.watchers(scene.actual), 0)
      compare(a.setPercent(50), false)
    }

    function test_outputChangeRebinds() {
      ready()
      a.output = "DP-2"
      compare(a.available, false)
      compare(FileTrap.watchers(scene.actual), 0, "the watch goes with the output")
      a.output = "eDP-1"
      answerDevice("intel_backlight")
      tryCompare(a, "available", true, 1000)
      compare(FileTrap.watchers(scene.actual), 1)
    }

    function test_inactiveReleasesEverything() {
      ready()
      a.active = false
      compare(a.available, false)
      compare(FileTrap.watchers(scene.actual), 0)
      a.active = true
      answerDevice("intel_backlight")
      tryCompare(a, "available", true, 1000)
    }

    function test_unsafeDeviceNameIgnored() {
      make()
      answerDevice("../../etc\n")
      wait(100)
      compare(a.device, "")
      compare(a.available, false)
    }

    function test_noDevice() {
      make()
      answerDevice("", 1)
      wait(100)
      compare(a.available, false)
      compare(ProcessTrap.log.length, 1, "no retry loop")
    }

    // ------------------------------------------------- missing hardware

    function test_unreadable() {
      FileTrap.removeFile(scene.actual)
      make()
      answerDevice("intel_backlight")
      wait(100)
      compare(a.available, false)
      compare(a.device, "", "forgotten, so the next open looks again")
      FileTrap.setFile(scene.actual, "57600")
      a.refresh()
      answerDevice("intel_backlight")
      tryCompare(a, "available", true, 1000)
    }

    function test_deviceDisappears() {
      ready()
      FileTrap.change(scene.actual, null)
      tryCompare(a, "available", false, 1000)
      compare(FileTrap.watchers(scene.actual), 0, "the watch is released")
      compare(a.percent, -1)
    }

    function test_badReadings() {
      FileTrap.setFile(scene.maxPath, "0")
      make()
      answerDevice("intel_backlight")
      wait(100)
      compare(a.available, false, "a zero maximum is unusable")
      FileTrap.setFile(scene.maxPath, "96000")
      FileTrap.change(scene.actual, "garbage")
      a.refresh()
      wait(100)
      compare(a.available, false)
    }

    // ----------------------------------------------------------- writing

    function test_invalidRequests() {
      ready()
      compare(a.setPercent(NaN), false)
      compare(a.setPercent(Infinity), false)
      compare(a.setPercent("x"), false)
      compare(a.setPercent(null), false)
      compare(a.pending, false)
      verify(a.setPercent(0))
      compare(a.desired, 1, "0 becomes 1: never blank")
      verify(a.setPercent(250))
      compare(a.desired, 100)
    }

    function test_writeConfirmedByObservation() {
      ready()
      verify(a.setPercent(40))
      compare(helperCount(), 1, "sent at once: no debounce before the first step")
      var p = helper()
      compare(p.command, ["omarchy-brightness-display", "--no-osd", "--monitor", "eDP-1", "40%"])
      compare(a.pending, true)
      FileTrap.change(scene.actual, "38400")
      tryCompare(a, "percent", 40, 1000)
      compare(a.pending, true, "observed, but the helper has not exited")
      p.testExit(0)
      tryCompare(a, "pending", false, 1000)
      compare(a.outcome, "")
    }

    function test_roundingWithinTolerance() {
      ready()
      a.setPercent(40)
      var p = helper()
      FileTrap.setFile(scene.actual, "37920")
      p.testExit(0)
      tryCompare(a, "pending", false, 1000)
      compare(a.percent, 40)
      compare(a.outcome, "")
    }

    function test_exitZeroWithoutChange() {
      ready()
      a.setPercent(30)
      helper().testExit(0)
      wait(50)
      compare(a.pending, true, "within the grace")
      tryCompare(a, "outcome", "unconfirmed", 1000)
      compare(a.pending, false)
      compare(a.percent, 60, "shows what is observed, not what was asked")
    }

    function test_failedExit() {
      ready()
      a.setPercent(30)
      helper().testExit(1)
      tryCompare(a, "outcome", "failed", 1000)
      compare(a.percent, 60)
    }

    function test_failedExitButApplied() {
      ready()
      a.setPercent(30)
      var p = helper()
      FileTrap.setFile(scene.actual, "28800")
      p.testExit(1)
      tryCompare(a, "pending", false, 1000)
      compare(a.outcome, "", "observed: applied, whatever the exit status")
    }

    function test_timeout() {
      ready()
      a.setPercent(30)
      var p = helper()
      tryCompare(p, "running", false, 1500)
      tryCompare(a, "outcome", "failed", 1500)
    }

    function test_failedToStart() {
      ready()
      a.setPercent(30)
      helper().testFailToStart()
      tryCompare(a, "outcome", "failed", 1000)
    }

    // ---------------------------------------- the send window (latency)

    // A key step from idle goes out in the same call: no wait.
    function test_firstIdleStepImmediate() {
      ready()
      holdWindow()
      verify(a.setPercent(65))
      compare(sent(), ["65%"], "dispatched synchronously")
      compare(a.pending, true)
    }

    // One request, then nothing: one send, it settles, nothing follows.
    function test_singleRequestSettles() {
      ready()
      a.setPercent(65)
      observe(65)
      helper().testExit(0)
      tryCompare(a, "pending", false, 1000)
      compare(a.outcome, "")
      wait(3 * a.debounce) // the window ends with nothing to send
      compare(sent(), ["65%"])
    }

    // Key presses faster than the window: the first at once, the rest held
    // and only the last sent. A helper that exits inside the window does
    // not reopen sending at once.
    function test_rapidKeyPresses() {
      ready()
      holdWindow()
      a.setPercent(65)
      a.setPercent(70)
      helper().testExit(0)
      a.setPercent(75)
      a.setPercent(80)
      wait(0)
      compare(sent(), ["65%"], "held while the window is open, though the helper is done")
      compare(a.desired, 80)
      compare(a.pending, true)
      endWindow()
      tryVerify(function() { return helperCount() === 2 }, 1000)
      compare(sent(), ["65%", "80%"], "only the last held value")
      observe(80)
      helper().testExit(0)
      tryCompare(a, "pending", false, 1000)
      compare(a.percent, 80, "requested and observed converge")
      compare(a.outcome, "")
    }

    // The window ends while the helper still runs: the held value waits for
    // the exit, then goes at once. Never two helpers.
    function test_windowEndsDuringHelper() {
      ready()
      holdWindow()
      a.setPercent(65)
      var p = helper()
      a.setPercent(55)
      endWindow()
      wait(20)
      compare(sent(), ["65%"], "one helper at a time")
      verify(p.running)
      p.testExit(0)
      tryVerify(function() { return helperCount() === 2 }, 1000)
      compare(sent(), ["65%", "55%"])
    }

    // A short drag inside one window: two sends, first and last.
    function test_shortDrag() {
      ready()
      holdWindow()
      for (var v = 61; v <= 70; v++) a.setPercent(v)
      compare(sent(), ["61%"])
      helper().testExit(0)
      endWindow()
      tryVerify(function() { return helperCount() === 2 }, 1000)
      compare(sent(), ["61%", "70%"])
      observe(70)
      helper().testExit(0)
      tryCompare(a, "pending", false, 1000)
      compare(a.percent, 70)
    }

    // A long drag over many windows: values go out while it moves (not only
    // at the end), at most one per window, never overlapping, and the last
    // one is the last asked for.
    function test_longDrag() {
      ready()
      a.debounce = 40
      var maxRunning = 0
      var started = Date.now()
      for (var v = 61; v <= 90; v++) {
        a.setPercent(v)
        var p = ProcessTrap.lastOf("omarchy-brightness-display")
        maxRunning = Math.max(maxRunning, p && p.running ? 1 : 0)
        if (p && p.running) p.testExit(0) // a helper as fast as the real one
        wait(10)
      }
      var elapsed = Date.now() - started
      // After release: helpers finish as they start, until 90 % has gone out.
      tryVerify(function() {
        var p = ProcessTrap.lastOf("omarchy-brightness-display")
        if (p.running) p.testExit(0)
        return sent()[helperCount() - 1] === "90%" && !p.running
      }, 1000)
      observe(90)
      tryCompare(a, "pending", false, 1000)
      verify(helperCount() >= 3, "sent while moving: " + sent())
      verify(helperCount() <= Math.ceil(elapsed / 40) + 2, helperCount() + " sends in " + elapsed + " ms")
      compare(a.percent, 90)
      compare(a.outcome, "")
    }

    // A failed helper with a newer value held: the newer one is sent once,
    // the old failure is not reported, and nothing is retried.
    function test_failedWithNewerValue() {
      ready()
      holdWindow()
      a.setPercent(65)
      a.setPercent(70)
      helper().testExit(1)
      endWindow()
      tryVerify(function() { return helperCount() === 2 }, 1000)
      compare(a.outcome, "")
      helper().testExit(1)
      tryCompare(a, "outcome", "failed", 1000)
      wait(3 * a.debounce)
      compare(sent(), ["65%", "70%"], "no retry")
    }

    // A helper stopped at the limit with a newer value held: same.
    function test_timeoutWithNewerValue() {
      ready()
      a.commandLimit = 100
      holdWindow()
      a.setPercent(65)
      a.setPercent(70)
      endWindow()
      tryVerify(function() { return helperCount() === 2 }, 1500)
      compare(sent(), ["65%", "70%"])
      tryCompare(a, "outcome", "failed", 1500)
      compare(helperCount(), 2, "no retry")
    }

    // An Fn key during a held request: the held request (the latest intent)
    // still goes out and the levels converge on it.
    function test_fnKeyWhileHeld() {
      ready()
      holdWindow()
      a.setPercent(65)
      a.setPercent(70)
      helper().testExit(0)
      observe(55) // Fn key
      tryCompare(a, "percent", 55, 1000)
      compare(a.pending, true, "a held request is not judged by someone else's change")
      endWindow()
      tryVerify(function() { return helperCount() === 2 }, 1000)
      observe(70)
      helper().testExit(0)
      tryCompare(a, "pending", false, 1000)
      compare(a.percent, 70)
      compare(a.outcome, "")
    }

    // The output changes while a helper runs; once rebound, a new request
    // waits for that old helper and is then sent, never stranded.
    function test_requestAfterRebindWaitsForOldHelper() {
      ready()
      a.setPercent(65)
      var p = helper()
      a.output = "HDMI-A-1"
      a.output = "eDP-1"
      answerDevice("intel_backlight\n")
      tryCompare(a, "available", true, 1000)
      a.setPercent(50)
      wait(3 * a.debounce) // the window is over; only the old helper holds it
      compare(sent(), ["65%"], "the old helper still runs")
      p.testExit(0)
      tryVerify(function() { return helperCount() === 2 }, 1000)
      compare(sent(), ["65%", "50%"])
    }

    // Another change wins the race: the observed level is shown.
    function test_anotherChangeWins() {
      ready()
      a.setPercent(30)
      var p = helper()
      FileTrap.change(scene.actual, "76800")
      p.testExit(0)
      tryCompare(a, "outcome", "unconfirmed", 1000)
      compare(a.percent, 80)
      compare(a.desired, -1)
    }

    function test_staleExitIgnored() {
      ready()
      a.setPercent(30)
      var p = helper()
      a.output = "HDMI-A-1"
      p.testExit(1)
      wait(300)
      compare(a.outcome, "", "a write from before the change does not report")
      compare(a.pending, false)
      compare(helperCount(), 1, "nothing more sent")
    }

    function test_unavailableAfterRequestDropsIt() {
      ready()
      holdWindow()
      a.setPercent(30)
      a.setPercent(35)
      a.active = false
      endWindow()
      helper().testExit(0)
      wait(100)
      compare(sent(), ["30%"], "the held value is dropped")
      compare(a.pending, false)
    }

    function test_destructionReleases() {
      ready()
      a.setPercent(30)
      a.setPercent(35)
      a.destroy()
      a = null
      wait(300)
      compare(FileTrap.watchers(scene.actual), 0)
      compare(sent(), ["30%"], "the held value is never sent")
    }

    // An external change clears an old failure.
    function test_externalChangeClearsOutcome() {
      ready()
      a.setPercent(30)
      helper().testExit(1)
      tryCompare(a, "outcome", "failed", 1000)
      FileTrap.change(scene.actual, "48000")
      tryCompare(a, "outcome", "", 1000)
      compare(a.percent, 50)
    }
  }
}
