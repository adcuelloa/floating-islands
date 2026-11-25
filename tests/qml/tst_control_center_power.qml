import QtQuick
import QtTest
import Quickshell.Io
import Quickshell.Services.UPower
import "../../plugin/theme"
import "../../plugin/adapters"
import "../../plugin/widgets"

// The power profile control against a fake provider (whose request() the
// test answers), and the adapter against stubbed UPower/PowerProfiles and
// the Process trap: no real profile is ever read or set.
Item {
  id: scene
  width: 800
  height: 600

  Theme { id: testTheme }

  QtObject {
    id: testStrings
    function t(key) { return key }
  }

  // Shaped like adapters/PowerProfileAdapter.qml.
  component FakeProvider: QtObject {
    property bool available: true
    property var profiles: ["power-saver", "balanced", "performance"]
    property string current: "performance"
    property string degraded: ""
    property bool onBattery: false
    property bool refuse: false
    property var asked: []
    property var done: null
    property int refreshes: 0

    function request(profile, callback) {
      if (refuse || done !== null) return ""
      asked = asked.concat([profile])
      done = callback
      return onBattery ? "battery" : "ac"
    }
    function answer(code) { var cb = done; done = null; cb(code) }
    function refresh() { refreshes++ }
  }

  FakeProvider { id: fake }

  ControlCenterProfiles {
    id: control
    width: 352
    theme: testTheme
    strings: testStrings
    provider: fake
    confirmTimeout: 600
    settleGrace: 150
  }

  Component {
    id: controlComponent
    ControlCenterProfiles {
      width: 352
      theme: testTheme
      strings: testStrings
      confirmTimeout: 600
      settleGrace: 150
    }
  }

  PowerProfileAdapter { id: adapter; commandLimit: 300 }

  readonly property string allThree: JSON.stringify({ type: "a{sv}", data: [{
    ActiveProfile: { type: "s", data: "performance" },
    PerformanceDegraded: { type: "s", data: "" },
    Profiles: { type: "aa{sv}", data: [
      { Profile: { type: "s", data: "power-saver" } },
      { Profile: { type: "s", data: "balanced" } },
      { Profile: { type: "s", data: "performance" } }] }
  }] })

  TestCase {
    name: "ControlCenterPower"
    when: windowShown

    function find(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var found = find(item.children[i], name)
        if (found) return found
      }
      return null
    }
    function segment(name) { return find(control, "profile:" + name) }
    function lit() {
      var out = []
      for (var p of ["power-saver", "balanced", "performance"]) { var s = segment(p); if (s && s.lit) out.push(p) }
      return out
    }
    function status() { return find(control, "profileStatus").text }

    function init() {
      fake.available = true
      fake.profiles = ["power-saver", "balanced", "performance"]
      fake.current = "performance"
      fake.degraded = ""
      fake.onBattery = false
      fake.refuse = false
      fake.asked = []
      fake.done = null
      control.provider = fake
      control.request = null
      control.outcome = ""
      control.keyboardShown = false
      for (var p of ProcessTrap.log) if (p.running) p.testExit(1)
      ProcessTrap.clear()
      adapter.active = false
      UPower.onBattery = false
      PowerProfiles.profile = 2
    }

    // ------------------------------------------------------------ control

    function test_showsTheObservedProfile() {
      compare(control.controls().length, 3)
      compare(lit(), ["performance"])
      compare(segment("performance").Accessible.checked, true)
      compare(segment("balanced").Accessible.checked, false)
      compare(segment("balanced").Accessible.role, Accessible.RadioButton)
      compare(find(segment("balanced"), "profileLabel").text, "controlCenter.profile.balanced")
      compare(status(), "")
    }

    function test_onlyTheProfilesTheDaemonOffers() {
      fake.profiles = ["power-saver", "balanced"]
      fake.current = "balanced"
      compare(control.controls().length, 2)
      verify(segment("performance") === null, "not offered, not shown")
      fake.profiles = ["balanced"]
      compare(control.controls().length, 1)
    }

    function test_unavailable() {
      fake.available = false
      compare(control.controls().length, 0)
      compare(status(), "controlCenter.unavailable", "said, not hidden")
      control.provider = null
      compare(status(), "controlCenter.unavailable")
      control.select("balanced")
      compare(fake.asked.length, 0)
    }

    function test_externalChange() {
      fake.current = "power-saver"
      compare(lit(), ["power-saver"], "a change made elsewhere shows at once")
      compare(status(), "")
    }

    // AC to battery with Omarchy switching the profile on its own.
    function test_automaticSourceSwitch() {
      fake.onBattery = true
      fake.current = "balanced"
      compare(lit(), ["balanced"])
      compare(status(), "", "nothing was asked, nothing to report")
      fake.onBattery = false
      fake.current = "performance"
      compare(lit(), ["performance"])
    }

    function test_confirmed() {
      control.select("balanced")
      compare(fake.asked, ["balanced"])
      compare(status(), "controlCenter.switching")
      compare(lit(), ["performance"], "the active profile is shown until it changes")
      fake.current = "balanced"
      compare(status(), "controlCenter.switching", "observed, but the helper has not exited")
      fake.answer(0)
      compare(lit(), ["balanced"])
      compare(status(), "")
      verify(control.request === null)
    }

    function test_delayedConfirmation() {
      control.select("balanced")
      fake.answer(0)
      compare(status(), "controlCenter.switching", "exit 0 alone proves nothing")
      wait(50)
      fake.current = "balanced"
      compare(status(), "")
      compare(control.outcome, "")
    }

    function test_exitZeroWithoutChange() {
      control.select("balanced")
      fake.answer(0)
      tryCompare(control, "outcome", "failed", 1000)
      compare(status(), "controlCenter.failed")
      compare(lit(), ["performance"])
    }

    // powerprofilesctl can die at exit after the switch (CPython 3.14); the
    // profile is active, but Omarchy's helper never got to remember it.
    function test_activeButNotRemembered() {
      control.select("power-saver")
      fake.current = "power-saver"
      fake.answer(139)
      compare(lit(), ["power-saver"], "never shown as unchanged")
      compare(control.outcome, "unsaved")
      compare(status(), "controlCenter.profileUnsaved")
    }

    function test_failsBeforeActivation() {
      control.select("balanced")
      fake.answer(1)
      compare(status(), "controlCenter.switching", "a late signal may still come")
      tryCompare(control, "outcome", "failed", 1000)
      fake.current = "balanced"
      compare(control.outcome, "", "a later observed change clears the failure")
    }

    function test_timeout() {
      control.select("balanced")
      tryCompare(control, "outcome", "failed", 1500)
      verify(control.request === null)
      fake.answer(0)
      compare(control.outcome, "failed", "a late answer changes nothing")
    }

    function test_sourceChangesMidRequest() {
      control.select("balanced")
      fake.onBattery = true
      compare(control.outcome, "superseded")
      compare(status(), "controlCenter.profileSuperseded")
      fake.current = "power-saver"
      compare(lit(), ["power-saver"], "Omarchy's profile for the new source is shown")
      fake.answer(0)
      compare(control.outcome, "", "the late answer is ignored; the next change cleared the note")
    }

    function test_rapidSelections() {
      waitForRendering(control)
      control.select("balanced")
      control.select("power-saver")
      control.select("balanced")
      mouseClick(segment("power-saver"))
      compare(fake.asked, ["balanced"], "one request while pending")
      fake.current = "balanced"
      fake.answer(0)
      control.select("balanced")
      compare(fake.asked, ["balanced"], "the active profile is not asked again")
      mouseClick(segment("power-saver"))
      compare(fake.asked, ["balanced", "power-saver"])
    }

    function test_refusedRequest() {
      fake.refuse = true
      control.select("balanced")
      compare(control.outcome, "failed")
      verify(control.request === null)
    }

    function test_daemonGoesAway() {
      control.select("balanced")
      fake.available = false
      verify(control.request === null)
      compare(status(), "controlCenter.unavailable")
    }

    function test_degraded() {
      fake.degraded = "high-operating-temperature"
      compare(status(), "controlCenter.profileDegraded")
    }

    function test_answerAfterDestruction() {
      failOnWarning(/./)
      var c = createTemporaryObject(controlComponent, scene, { provider: fake })
      c.select("balanced")
      c.destroy()
      wait(0)
      fake.answer(0)
    }

    function test_keyboardSelectsOnlyOnSpaceOrEnter() {
      var b = segment("balanced")
      control.keyboardShown = true
      b.forceActiveFocus()
      compare(fake.asked.length, 0, "focus does not select")
      verify(!Qt.colorEqual(b.border.color, b.color), "unlit: accent edge")
      keyClick(Qt.Key_Space)
      compare(fake.asked, ["balanced"])
      fake.current = "balanced"
      fake.answer(0)
      verify(find(b, "litFocusRing").visible, "lit and focused: inset ring")
      var p = segment("performance")
      p.forceActiveFocus()
      keyClick(Qt.Key_Return)
      compare(fake.asked, ["balanced", "performance"])
    }

    // ------------------------------------------------------------ adapter

    function answerRead(text, code) {
      wait(0)
      var proc = ProcessTrap.lastOf("busctl")
      verify(proc && proc.running, "a read is running")
      proc.stdout.text = text
      proc.testExit(code === undefined ? 0 : code)
      wait(0)
    }

    function test_adapterIdleWhileInactive() {
      wait(10)
      compare(ProcessTrap.log.length, 0, "nothing read while the Control Center is off")
      verify(!adapter.available)
      compare(adapter.current, "")
      PowerProfiles.profile = 0
      compare(adapter.current, "", "the signal is not followed while inactive")
    }

    function test_adapterReadsTheDaemon() {
      adapter.active = true
      wait(0)
      var proc = ProcessTrap.lastOf("busctl")
      compare(proc.command, ["busctl", "--system", "--json=short", "--auto-start=no", "call",
        "net.hadess.PowerProfiles", "/net/hadess/PowerProfiles",
        "org.freedesktop.DBus.Properties", "GetAll", "s", "net.hadess.PowerProfiles"])
      answerRead(scene.allThree)
      verify(adapter.available)
      compare(adapter.profiles, ["power-saver", "balanced", "performance"])
      compare(adapter.current, "performance")
      compare(adapter.source, "ac")
    }

    function test_adapterUnavailableDaemon() {
      adapter.active = true
      answerRead("", 1)
      verify(!adapter.available, "a failed read is unavailable")
      compare(adapter.request("balanced", function() {}), "")
      compare(ProcessTrap.lastOf("omarchy-powerprofiles-set"), null)
    }

    function test_adapterFollowsTheSignal() {
      adapter.active = true
      answerRead(scene.allThree)
      PowerProfiles.profile = 0
      compare(adapter.current, "power-saver", "changed elsewhere")
      PowerProfiles.profile = 1
      compare(adapter.current, "balanced")
    }

    function test_adapterPowerSource() {
      adapter.active = true
      answerRead(scene.allThree)
      UPower.onBattery = true
      compare(adapter.source, "battery")
      wait(0)
      verify(ProcessTrap.lastOf("busctl").running, "a source change re-reads the daemon")
      answerRead(scene.allThree)
      compare(adapter.request("balanced", function() {}), "battery")
      compare(ProcessTrap.lastOf("omarchy-powerprofiles-set").command, ["omarchy-powerprofiles-set", "battery", "balanced"])
      ProcessTrap.lastOf("omarchy-powerprofiles-set").testExit(0)
    }

    function test_adapterCommands() {
      adapter.active = true
      answerRead(scene.allThree)
      var codes = []
      compare(adapter.request("turbo", function() {}), "", "not a profile")
      compare(adapter.request("balanced", function(c) { codes.push(c) }), "ac")
      var proc = ProcessTrap.lastOf("omarchy-powerprofiles-set")
      compare(proc.command, ["omarchy-powerprofiles-set", "ac", "balanced"])
      verify(adapter.busy)
      compare(adapter.request("power-saver", function() {}), "", "one at a time")
      proc.testExit(139)
      compare(codes, [139], "the exit status is passed on as it is")
      wait(0)
      verify(ProcessTrap.lastOf("busctl").running, "re-read after the command")
      answerRead(scene.allThree)
      compare(adapter.request("power-saver", function(c) { codes.push(c) }), "ac")
      ProcessTrap.lastOf("omarchy-powerprofiles-set").testFailToStart()
      compare(codes, [139, -1], "could not start")
      for (var p of ProcessTrap.log) {
        var line = p.command.join(" ")
        verify(line.indexOf("busctl --system --json=short --auto-start=no call net.hadess.PowerProfiles") === 0
               || line === "omarchy-powerprofiles-set ac balanced" || line === "omarchy-powerprofiles-set ac power-saver", line)
      }
    }

    function test_adapterStopsAHungHelper() {
      adapter.active = true
      answerRead(scene.allThree)
      var codes = []
      adapter.request("balanced", function(c) { codes.push(c) })
      var proc = ProcessTrap.lastOf("omarchy-powerprofiles-set")
      tryCompare(proc, "running", false, 2000)
      compare(codes, [-1])
      verify(!adapter.busy)
    }

    function test_adapterOffDropsTheState() {
      adapter.active = true
      answerRead(scene.allThree)
      verify(adapter.available)
      adapter.active = false
      verify(!adapter.available)
      compare(adapter.profiles, [])
    }

    // The control on the real adapter, end to end: the helper exits 0 and
    // the daemon's signal confirms.
    function test_endToEnd() {
      adapter.active = true
      answerRead(scene.allThree)
      control.provider = adapter
      control.select("balanced")
      compare(status(), "controlCenter.switching")
      PowerProfiles.profile = 1
      ProcessTrap.lastOf("omarchy-powerprofiles-set").testExit(0)
      compare(lit(), ["balanced"])
      compare(status(), "")
    }
  }
}
