import QtQuick
import QtTest
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import "../../plugin/theme"
import "../../plugin/adapters"
import "../../plugin/widgets"

// The Control Center's Wi-Fi and Bluetooth tiles against fake providers
// (whose request() the test answers), and the adapter that reads Quickshell's
// Networking and Bluetooth services (stubbed; no command is ever run: the
// Process stub only records what it was asked).
Item {
  id: scene
  width: 800
  height: 700

  Theme { id: testTheme }

  QtObject {
    id: testStrings
    // controlCenter.openPanel is formatted with .arg(); keep its %1 as en.json does.
    function t(key) { return key === "controlCenter.openPanel" ? "Open %1" : key }
  }

  // A provider shaped like adapters/Connectivity.qml's. request() keeps the
  // callback for the test to answer; `refuse` makes it decline, as a
  // provider with a command still running does.
  component FakeRadio: QtObject {
    property bool available: true
    property bool blocked: false
    property bool on: false
    property bool connected: false
    property string detail: ""
    property int count: 1
    property bool refuse: false
    property var asked: []
    property var done: null

    function request(on, callback) {
      if (refuse) return false
      asked = asked.concat([on])
      done = callback
      return true
    }
    function answer(ok) { var cb = done; done = null; cb(ok) }
  }

  FakeRadio { id: fakeWifi }
  FakeRadio { id: fakeBluetooth }

  ControlCenterRadio {
    id: wifiTile
    width: 160
    theme: testTheme
    strings: testStrings
    kind: "wifi"
    provider: fakeWifi
    confirmTimeout: 150
  }

  SignalSpy { id: panelSpy; target: view; signalName: "panelRequested" }

  ControlCenterView {
    id: view
    y: 80
    width: 316
    theme: testTheme
    strings: testStrings
    wifi: fakeWifi
    bluetooth: fakeBluetooth
    links: [{ id: "a", name: "A" }, { id: "b", name: "B" }, { id: "c", name: "C" }, { id: "d", name: "D" }, { id: "e", name: "E" }, { id: "f", name: "F" }]
  }

  Connectivity { id: adapter; commandLimit: 300 }

  Component {
    id: radioComponent
    ControlCenterRadio {
      width: 160
      theme: testTheme
      strings: testStrings
      kind: "bluetooth"
      confirmTimeout: 1000
    }
  }

  // A tile on the real adapter, for the recovery paths end to end.
  ControlCenterRadio {
    id: liveBluetooth
    y: 500
    width: 160
    theme: testTheme
    strings: testStrings
    kind: "bluetooth"
    provider: adapter.bluetooth
    confirmTimeout: 1000
  }

  // Networking device and network objects, shaped like Quickshell's.
  component FakeDevice: QtObject {
    property int type: DeviceType.Wifi
    property bool connected: false
    property QtObject networks: QtObject { property var values: [] }
  }
  component FakeNetwork: QtObject {
    property string name: ""
    property bool connected: false
  }
  component FakeAdapter: QtObject {
    property bool enabled: false
  }

  FakeDevice { id: wlan }
  FakeDevice { id: eth; type: DeviceType.Wired }
  FakeNetwork { id: home; name: "Home" }
  FakeAdapter { id: hci0 }
  FakeAdapter { id: hci1 }

  TestCase {
    name: "ControlCenterConnectivity"
    when: windowShown

    function find(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var found = find(item.children[i], name)
        if (found) return found
      }
      return null
    }
    function tileOf(kind) {
      var hit = null
      function walk(item) {
        if (item.kind === kind && typeof item.activate === "function") hit = hit || item
        for (var i = 0; i < item.children.length; i++) walk(item.children[i])
      }
      walk(view)
      return hit
    }

    function init() {
      // A QML runtime error in any Control Center test fails it (the known
      // Calendar warnings live in tst_calendar.qml, not here).
      failOnWarning(/TypeError|ReferenceError/)
      for (var r of [fakeWifi, fakeBluetooth]) {
        r.available = true; r.blocked = false; r.on = false; r.connected = false
        r.detail = ""; r.count = 1; r.refuse = false; r.asked = []; r.done = null
      }
      for (var t of [wifiTile, tileOf("wifi"), tileOf("bluetooth")]) {
        t.pending = null; t.asking = false; t.failed = false
      }
      view.wifiPanelId = ""
      view.bluetoothPanelId = ""
      panelSpy.clear()
      adapter.active = false
      Networking.backend = NetworkBackendType.NetworkManager
      Networking.wifiEnabled = true
      Networking.wifiHardwareEnabled = true
      Networking.devices.values = []
      Bluetooth.adapters.values = []
      wlan.connected = false
      wlan.networks.values = []
      eth.connected = false
      home.connected = false
      hci0.enabled = false
      hci1.enabled = false
      for (var p of ProcessTrap.log) if (p.running) p.testExit(1)
      ProcessTrap.clear()
      liveBluetooth.pending = null; liveBluetooth.asking = false; liveBluetooth.failed = false
    }

    // ------------------------------------------------------------ tiles

    function test_showsTheObservedState() {
      compare(wifiTile.status, "off")
      fakeWifi.on = true
      compare(wifiTile.status, "on", "a change made elsewhere shows at once")
      fakeWifi.connected = true
      fakeWifi.detail = "Home"
      compare(wifiTile.status, "connected")
      compare(find(wifiTile, "radioStatus").text, "Home")
      fakeWifi.detail = ""
      compare(find(wifiTile, "radioStatus").text, "controlCenter.connected")
      fakeWifi.connected = false
      fakeWifi.on = false
      compare(wifiTile.status, "off")
    }

    function test_unavailableAndBlocked() {
      fakeWifi.available = false
      compare(wifiTile.status, "unavailable")
      compare(wifiTile.controls().length, 0, "nothing to reach by keyboard")
      wifiTile.activate()
      compare(fakeWifi.asked.length, 0)
      fakeWifi.available = true
      fakeWifi.blocked = true
      compare(wifiTile.status, "blocked")
      compare(find(wifiTile, "radioStatus").text, "controlCenter.blocked")
      wifiTile.activate()
      compare(fakeWifi.asked.length, 0, "a hardware switch is not overridden")
      wifiTile.provider = null
      compare(wifiTile.status, "unavailable")
      wifiTile.provider = fakeWifi
    }

    // Pending until both the command has exited and the state is observed.
    function test_pendingUntilObserved() {
      wifiTile.activate()
      compare(fakeWifi.asked, [true])
      compare(wifiTile.status, "pending")
      compare(find(wifiTile, "radioStatus").text, "controlCenter.switching")
      verify(!wifiTile.on, "nothing is shown as done before it is observed")
      fakeWifi.answer(true)
      compare(wifiTile.status, "pending", "the command succeeded, the state is not observed yet")
      fakeWifi.on = true
      compare(wifiTile.status, "on")
    }

    function test_observedBeforeTheCommandExits() {
      wifiTile.activate()
      fakeWifi.on = true
      compare(wifiTile.status, "pending", "the command is still running")
      wifiTile.activate()
      compare(fakeWifi.asked.length, 1, "no second command meanwhile")
      fakeWifi.answer(true)
      compare(wifiTile.status, "on")
    }

    function test_failedCommand() {
      fakeWifi.on = true
      wifiTile.activate()
      compare(fakeWifi.asked, [false])
      fakeWifi.answer(false)
      compare(wifiTile.status, "failed")
      compare(find(wifiTile, "radioStatus").text, "controlCenter.failed")
      verify(wifiTile.on, "the observed state is kept")
      fakeWifi.on = false
      compare(wifiTile.status, "off", "a later observed change clears the failure")
    }

    function test_unansweredReadsFailed() {
      wifiTile.activate()
      tryCompare(wifiTile, "failed", true, 1000)
      compare(wifiTile.status, "failed")
      // The command is still running: another press is refused by the provider.
      fakeWifi.refuse = true
      wifiTile.activate()
      compare(wifiTile.status, "failed")
      compare(fakeWifi.asked.length, 1)
      fakeWifi.refuse = false
      fakeWifi.answer(true)
      compare(wifiTile.status, "failed", "a late answer changes nothing")
    }

    function test_rapidPresses() {
      for (var i = 0; i < 5; i++) wifiTile.activate()
      compare(fakeWifi.asked, [true], "one request while pending")
      mouseClick(wifiTile)
      mouseClick(wifiTile)
      compare(fakeWifi.asked.length, 1)
      fakeWifi.on = true
      fakeWifi.answer(true)
      compare(wifiTile.status, "on")
      mouseClick(wifiTile)
      compare(fakeWifi.asked, [true, false], "the next request asks the other way")
    }

    // While the command runs, the device may vanish and come back (rfkill,
    // re-enumeration): the request is kept until the command exits.
    function test_goesAwayWhileTheCommandRuns() {
      wifiTile.activate()
      fakeWifi.available = false
      compare(wifiTile.status, "unavailable")
      verify(wifiTile.pending !== null, "kept while the command runs")
      fakeWifi.available = true
      compare(wifiTile.status, "pending")
      fakeWifi.on = true
      fakeWifi.answer(true)
      compare(wifiTile.status, "on")
    }

    function test_goesAwayAfterTheCommand() {
      wifiTile.activate()
      fakeWifi.answer(true)
      compare(wifiTile.status, "pending")
      fakeWifi.available = false
      verify(wifiTile.pending === null, "no command running: dropped")
      fakeWifi.available = true
      compare(wifiTile.status, "off", "nothing asked of the old radio is kept")
    }

    function test_goneAndFailed() {
      wifiTile.activate()
      fakeWifi.available = false
      fakeWifi.answer(false)
      fakeWifi.available = true
      compare(wifiTile.status, "failed")
    }

    // The panel rebuilt while a command runs: its answer reaches a dead tile.
    function test_answerAfterTheTileIsGone() {
      failOnWarning(/./)
      var tile = createTemporaryObject(radioComponent, scene, { provider: fakeBluetooth })
      tile.activate()
      compare(fakeBluetooth.asked, [true])
      tile.destroy()
      wait(0)
      fakeBluetooth.answer(true)
    }

    function test_accessibleState() {
      var toggle = wifiTile.controls()[0]
      compare(toggle.Accessible.role, Accessible.CheckBox)
      compare(toggle.Accessible.name, "controlCenter.wifi")
      compare(toggle.Accessible.checked, false)
      fakeWifi.on = true
      compare(toggle.Accessible.checked, true)
      compare(toggle.Accessible.description, "controlCenter.on")
    }

    // ------------------------------------------------------------ view

    function test_viewKeyboard() {
      var wifiToggle = tileOf("wifi").controls()[0]
      wifiToggle.forceActiveFocus()
      keyClick(Qt.Key_Space)
      compare(fakeWifi.asked, [true])
      keyClick(Qt.Key_Right)
      var btToggle = tileOf("bluetooth").controls()[0]
      verify(btToggle.activeFocus, "arrows move from Wi-Fi to Bluetooth")
      keyClick(Qt.Key_Return)
      compare(fakeBluetooth.asked, [true])
      keyClick(Qt.Key_Left)
      verify(wifiToggle.activeFocus)
      fakeBluetooth.available = false
      var order = view.controls()
      verify(order.indexOf(btToggle) === -1, "an unavailable tile is skipped")
    }

    function test_viewOrder() {
      var order = view.controls()
      var wifiAt = order.indexOf(tileOf("wifi").controls()[0])
      var btAt = order.indexOf(tileOf("bluetooth").controls()[0])
      verify(wifiAt >= 0)
      compare(btAt, wifiAt + 1)
    }

    function test_viewLinksToFullPanels() {
      compare(tileOf("wifi").controls().length, 1, "no Network panel hosted: no link")
      view.wifiPanelId = "omarchy.network"
      view.bluetoothPanelId = "omarchy.bluetooth"
      var wifiMore = tileOf("wifi").controls()[1]
      var btMore = tileOf("bluetooth").controls()[1]
      compare(wifiMore.accessibleName, "controlCenter.more.wifi")
      mouseClick(wifiMore)
      compare(panelSpy.count, 1)
      compare(panelSpy.signalArguments[0][0], "omarchy.network")
      compare(fakeWifi.asked.length, 0, "the link does not toggle the radio")
      btMore.forceActiveFocus()
      keyClick(Qt.Key_Enter)
      compare(panelSpy.signalArguments[1][0], "omarchy.bluetooth")
      fakeWifi.available = false
      compare(tileOf("wifi").controls().length, 1, "the panel stays reachable without Wi-Fi")
    }

    function test_viewKeepsItsHeight() {
      verify(view.contentHeight <= view.implicitHeight, view.contentHeight + " > " + view.implicitHeight)
      var height = view.implicitHeight
      fakeWifi.available = false
      view.audioSink = null
      view.wifiPanelId = "omarchy.network"
      compare(view.implicitHeight, height)
    }

    // The live panel's links wrapped past a fixed height (2026-11-02 trial).
    // They now live on the panels page: their number never changes the
    // footprint, and a long list scrolls inside it.
    function test_linksDoNotChangeTheFootprint() {
      var links = view.links
      var base = view.implicitHeight
      var many = []
      for (var i = 0; i < 20; i++) many.push({ id: "p" + i, name: "Panel " + i })
      view.links = many
      wait(50)
      compare(view.implicitHeight, base)
      fakeWifi.available = false
      fakeWifi.on = true
      fakeBluetooth.on = true
      view.audioSink = null
      view.wifiPanelId = "omarchy.network"
      wait(50)
      compare(view.implicitHeight, base, "no state shown changes it")
      view.links = links
    }

    // The focus ring stays visible on a lit tile (2026-11-02 trial: it was
    // the accent, drawn on the accent fill).
    function test_focusRingOnLitTiles() {
      var tile = tileOf("wifi")
      var toggle = tile.controls()[0]
      view.keyboardShown = true
      toggle.forceActiveFocus()
      verify(toggle.activeFocus)
      verify(!Qt.colorEqual(toggle.border.color, toggle.color), "unlit: the accent edge ring")
      verify(!find(tile, "litFocusRing").visible)
      fakeWifi.on = true
      compare(tile.status, "on")
      // Lit: drawn inside the fill, in a colour that differs from it (an edge
      // ring would sit against the panel's dark background, live 2026-11-02).
      var ring = find(tile, "litFocusRing")
      verify(ring.visible, "lit: the inset ring")
      verify(!Qt.colorEqual(ring.border.color, toggle.color))
      verify(ring.width < toggle.width)
      toggle.focus = false
      view.forceActiveFocus()
      verify(!ring.visible, "only while focused")
      view.keyboardShown = false
    }

    // ------------------------------------------------------------ adapter

    // Opening the panel refreshes both providers; one read serves both.
    function test_adapterOneReadPerOpen() {
      adapter.active = true
      wait(0)
      answerRfkill([])
      var reads = function() { return ProcessTrap.log.filter(function(p) { return p.command[0] === "rfkill" }).length }
      var before = reads()
      adapter.wifi.refresh()
      adapter.bluetooth.refresh()
      wait(0)
      compare(reads(), before + 1)
      answerRfkill([])
      wait(50)
      compare(reads(), before + 1)
    }

    function test_adapterIdleWhileInactive() {
      Networking.devices.values = [wlan]
      Bluetooth.adapters.values = [hci0]
      verify(!adapter.wifi.available)
      verify(!adapter.bluetooth.available)
      adapter.active = true
      verify(adapter.wifi.available)
      verify(adapter.bluetooth.available)
    }

    function test_adapterWifi() {
      adapter.active = true
      verify(!adapter.wifi.available, "no Wi-Fi device")
      Networking.devices.values = [eth]
      eth.connected = true
      verify(!adapter.wifi.available, "Ethernet is not Wi-Fi")
      Networking.devices.values = [eth, wlan]
      verify(adapter.wifi.available)
      verify(adapter.wifi.on)
      verify(!adapter.wifi.connected, "a wired link does not make Wi-Fi connected")
      wlan.networks.values = [home]
      home.connected = true
      wlan.connected = true
      verify(adapter.wifi.connected)
      compare(adapter.wifi.detail, "Home")
      Networking.wifiEnabled = false
      verify(!adapter.wifi.on, "changed elsewhere")
      verify(!adapter.wifi.connected)
      Networking.wifiEnabled = true
      Networking.wifiHardwareEnabled = false
      verify(adapter.wifi.blocked)
      Networking.wifiHardwareEnabled = true
      Networking.backend = NetworkBackendType.None
      verify(!adapter.wifi.available, "no NetworkManager")
    }

    function test_adapterBluetooth() {
      adapter.active = true
      verify(!adapter.bluetooth.available, "no adapter")
      Bluetooth.adapters.values = [hci0]
      verify(adapter.bluetooth.available)
      verify(!adapter.bluetooth.on)
      hci0.enabled = true
      verify(adapter.bluetooth.on, "changed elsewhere")
      hci0.enabled = false
      Bluetooth.adapters.values = [hci0, hci1]
      compare(adapter.bluetooth.count, 2)
      hci1.enabled = true
      verify(adapter.bluetooth.on, "any powered adapter")
      Bluetooth.adapters.values = []
      verify(!adapter.bluetooth.available, "removed")
    }

    function test_adapterCommands() {
      adapter.active = true
      var results = []
      verify(adapter.wifi.request(false, function(ok) { results.push(ok) }))
      var proc = ProcessTrap.lastOf("nmcli")
      compare(proc.command, ["nmcli", "radio", "wifi", "off"])
      verify(!adapter.wifi.request(true, function() {}), "one at a time")
      compare(ProcessTrap.log.filter(function(p) { return p.command[0] === "nmcli" }).length, 1)
      proc.testExit(0)
      compare(results, [true])
      verify(adapter.bluetooth.request(true, function(ok) { results.push(ok) }))
      proc = ProcessTrap.lastOf("omarchy-bluetooth-power")
      compare(proc.command, ["omarchy-bluetooth-power", "on"])
      proc.testExit(1)
      compare(results, [true, false], "a non-zero exit is a failure")
      verify(adapter.bluetooth.request(false, function(ok) { results.push(ok) }))
      ProcessTrap.lastOf("omarchy-bluetooth-power").testFailToStart()
      compare(results, [true, false, false], "a command that cannot start is a failure")
      verify(adapter.bluetooth.request(true, function() {}), "free again afterwards")
      ProcessTrap.lastOf("omarchy-bluetooth-power").testExit(0)
      // Only these programs, with these arguments, ever start.
      for (var p of ProcessTrap.log) {
        var line = p.command.join(" ")
        verify(["nmcli radio wifi off", "omarchy-bluetooth-power on", "omarchy-bluetooth-power off",
                "rfkill --json --output TYPE,SOFT,HARD"].indexOf(line) !== -1, line)
      }
    }

    // A command that never exits is stopped at the limit and fails, and the
    // radio can be asked again.
    function test_adapterStopsAHungCommand() {
      adapter.active = true
      var results = []
      verify(adapter.bluetooth.request(true, function(ok) { results.push(ok) }))
      var proc = ProcessTrap.lastOf("omarchy-bluetooth-power")
      tryCompare(proc, "running", false, 2000)
      compare(results, [false])
      verify(adapter.bluetooth.request(true, function() {}))
    }

    // rfkill is read on changes, not on a timer; one read at a time.
    function test_adapterReadsRfkillOnChanges() {
      adapter.active = true
      wait(0)
      var reads = function() { return ProcessTrap.log.filter(function(p) { return p.command[0] === "rfkill" }).length }
      compare(reads(), 1, "on activation")
      answerRfkill([])
      wait(50)
      compare(reads(), 1, "nothing more while nothing changes")
      Bluetooth.adapters.values = [hci0]
      wait(0)
      compare(reads(), 2, "an adapter appeared")
      liveBluetooth.controls()[0].forceActiveFocus()
      adapter.bluetooth.refresh()
      adapter.bluetooth.refresh()
      compare(reads(), 2, "a read already running is not doubled")
      answerRfkill([])
      wait(0)
      compare(reads(), 3, "one more read for the requests made meanwhile")
      answerRfkill([])
      answerRfkill("garbage")
      verify(adapter.rfkill.bluetooth === null || adapter.rfkill.bluetooth.present === false)
    }

    // A read started before a device change finishes after it: its stale
    // result is applied, but the change asked for another read, which runs
    // next and wins. The tile never stays on the stale result.
    function test_staleRfkillReadIsFollowedByAFreshOne() {
      adapter.active = true
      Bluetooth.adapters.values = [hci0]
      answerRfkill([{ type: "bluetooth", soft: "unblocked", hard: "unblocked" }])
      var reads = function() { return ProcessTrap.log.filter(function(p) { return p.command[0] === "rfkill" }).length }
      adapter.bluetooth.refresh()
      wait(0)
      var stale = ProcessTrap.lastOf("rfkill")
      verify(stale.running)
      var before = reads()
      // The radio is blocked and the adapter leaves while that read runs.
      Bluetooth.adapters.values = []
      wait(0)
      stale.stdout.text = JSON.stringify({ rfkilldevices: [{ type: "bluetooth", soft: "unblocked", hard: "unblocked" }] })
      stale.testExit(0)
      compare(liveBluetooth.status, "unavailable", "the stale result, briefly")
      wait(0)
      compare(reads(), before + 1, "a fresh read follows")
      verify(ProcessTrap.lastOf("rfkill").running)
      answerRfkill([{ type: "bluetooth", soft: "blocked", hard: "unblocked" }])
      compare(liveBluetooth.status, "off")
      wait(50)
      compare(reads(), before + 1, "and then no more")
    }

    function answerRfkill(devices) {
      wait(0)
      var proc = ProcessTrap.lastOf("rfkill")
      if (!proc || !proc.running) return
      proc.stdout.text = typeof devices === "string" ? devices : JSON.stringify({ rfkilldevices: devices })
      proc.testExit(0)
      wait(0)
    }

    // The machine has a platform switch: blocking Bluetooth removes the
    // adapter from BlueZ. The tile must stay able to turn it back on.
    function test_bluetoothOffLosesTheAdapterAndComesBack() {
      adapter.active = true
      Bluetooth.adapters.values = [hci0]
      hci0.enabled = true
      answerRfkill([{ type: "bluetooth", soft: "unblocked", hard: "unblocked" }])
      compare(liveBluetooth.status, "on")
      // Off: the helper blocks, the adapter goes, the helper exits.
      liveBluetooth.activate()
      compare(ProcessTrap.lastOf("omarchy-bluetooth-power").command, ["omarchy-bluetooth-power", "off"])
      hci0.enabled = false
      Bluetooth.adapters.values = []
      compare(liveBluetooth.status, "unavailable", "between the adapter going and rfkill being read")
      ProcessTrap.lastOf("omarchy-bluetooth-power").testExit(0)
      answerRfkill([{ type: "bluetooth", soft: "blocked", hard: "unblocked" }])
      compare(liveBluetooth.status, "off", "a soft-blocked switch is recoverable")
      verify(liveBluetooth.pending === null)
      verify(!liveBluetooth.failed)
      compare(liveBluetooth.controls().length, 1, "reachable by keyboard")
      // On again: unblock, BlueZ lists the adapter, bluetoothd powers it.
      liveBluetooth.controls()[0].forceActiveFocus()
      keyClick(Qt.Key_Space)
      compare(ProcessTrap.lastOf("omarchy-bluetooth-power").command, ["omarchy-bluetooth-power", "on"])
      compare(liveBluetooth.status, "pending")
      answerRfkill([{ type: "bluetooth", soft: "unblocked", hard: "unblocked" }])
      compare(liveBluetooth.status, "unavailable", "unblocked, not listed yet")
      verify(liveBluetooth.pending !== null, "the request survives re-enumeration")
      Bluetooth.adapters.values = [hci0]
      hci0.enabled = true
      compare(liveBluetooth.status, "pending", "the helper has not exited")
      ProcessTrap.lastOf("omarchy-bluetooth-power").testExit(0)
      compare(liveBluetooth.status, "on")
    }

    function test_bluetoothRecoveryFails() {
      adapter.active = true
      answerRfkill([{ type: "bluetooth", soft: "blocked", hard: "unblocked" }])
      compare(liveBluetooth.status, "off")
      liveBluetooth.activate()
      answerRfkill([{ type: "bluetooth", soft: "unblocked", hard: "unblocked" }])
      ProcessTrap.lastOf("omarchy-bluetooth-power").testExit(1)
      verify(liveBluetooth.failed, "the helper reported the adapter did not come up")
      answerRfkill([{ type: "bluetooth", soft: "unblocked", hard: "unblocked" }])
      compare(liveBluetooth.status, "unavailable", "nothing listed and nothing blocked")
    }

    function test_bluetoothHardBlockAndAbsence() {
      adapter.active = true
      answerRfkill([{ type: "bluetooth", soft: "unblocked", hard: "blocked" }])
      compare(liveBluetooth.status, "blocked")
      liveBluetooth.activate()
      compare(ProcessTrap.lastOf("omarchy-bluetooth-power"), null, "a hardware switch is not fought")
      adapter.bluetooth.refresh()
      answerRfkill([{ type: "wlan", soft: "unblocked", hard: "unblocked" }])
      compare(liveBluetooth.status, "unavailable", "no Bluetooth hardware at all")
    }

    function test_bluetoothSeveralAdapters() {
      adapter.active = true
      Bluetooth.adapters.values = [hci0, hci1]
      answerRfkill([{ type: "bluetooth", soft: "unblocked", hard: "unblocked" },
                    { type: "bluetooth", soft: "unblocked", hard: "unblocked" }])
      hci1.enabled = true
      compare(liveBluetooth.status, "on")
      liveBluetooth.activate()
      hci1.enabled = false
      Bluetooth.adapters.values = [hci0]
      ProcessTrap.lastOf("omarchy-bluetooth-power").testExit(0)
      compare(liveBluetooth.status, "off", "one adapter left, unpowered")
      liveBluetooth.activate()
      hci0.enabled = true
      ProcessTrap.lastOf("omarchy-bluetooth-power").testExit(0)
      compare(liveBluetooth.status, "on")
    }

    function test_wifiOffLosesTheDevice() {
      adapter.active = true
      Networking.devices.values = [wlan]
      answerRfkill([{ type: "wlan", soft: "unblocked", hard: "unblocked" }])
      verify(adapter.wifi.on)
      Networking.wifiEnabled = false
      Networking.devices.values = []
      answerRfkill([{ type: "wlan", soft: "blocked", hard: "unblocked" }])
      verify(adapter.wifi.available, "still switchable on")
      verify(!adapter.wifi.on)
      Networking.wifiHardwareEnabled = false
      answerRfkill([{ type: "wlan", soft: "blocked", hard: "blocked" }])
      verify(adapter.wifi.blocked)
    }
  }
}
