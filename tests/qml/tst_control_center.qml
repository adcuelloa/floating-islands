import QtQuick
import QtTest
import "../../plugin/theme"
import "../../plugin/core"
import "../../plugin/widgets"

// The Control Center's main view, tiles and entry against fake first-party
// proxies shaped like Omarchy's PluginFirstPartyServiceApi: one that applies
// a change at once (notifications), one that reports it later (Night Light
// applies a temperature, then reads it back), and one that never answers.
Item {
  id: scene
  width: 800
  height: 400

  Theme { id: testTheme }

  QtObject {
    id: testStrings
    function t(key) { return key === "controlCenter.openPanel" ? "Open %1" : key }
  }

  // Do Not Disturb: the setter changes the state at once.
  QtObject {
    id: notifications
    property bool doNotDisturb: false
    function setDoNotDisturb(value) { doNotDisturb = !!value }
  }

  // Night Light: the setter only records the request; the test reports it.
  QtObject {
    id: nightlight
    property bool enabled: false
    property var asked: []
    function setNightlight(value) { asked = asked.concat([!!value]) }
  }

  // Idle: answers nothing (a disabled service behind the proxy).
  QtObject {
    id: idle
    property bool stayAwake: false
    property var asked: []
    function setIdleEnabled(value) { asked = asked.concat([!!value]) }
  }

  SignalSpy { id: closeSpy; target: view; signalName: "closeRequested" }
  SignalSpy { id: panelSpy; target: view; signalName: "panelRequested" }

  ControlCenterView {
    id: view
    theme: testTheme
    strings: testStrings
    width: 316
    confirmTimeout: 150
    services: ({ nightlight: nightlight, stayAwake: idle, doNotDisturb: notifications })
    links: [{ id: "omarchy.bluetooth", name: "Bluetooth" }, { id: "omarchy.network", name: "Network" }]
  }

  Component {
    id: bareView
    ControlCenterView { theme: testTheme; strings: testStrings; width: 316; services: ({ doNotDisturb: notifications }) }
  }

  // Stands in for Bar.qml, as in tst_hosting.
  QtObject {
    id: fakeBar
    property var theme: testTheme
    property string fontFamily: "monospace"
    property string position: "top"
    property string pluginId: "floating-islands"
    property var barWidgetRegistry: null
    property var publicLayout: ({})
    property var shell: null
    function barSizeFor(name) { return 50 }
  }

  WidgetHosting { id: hosting; bar: fakeBar }

  ControlCenterButton {
    id: entry
    y: 300
    theme: testTheme
    strings: testStrings
  }

  // Another panel owner on the bar, as a hosted widget's would be.
  QtObject {
    id: other
    property bool opened: false
    function close() { opened = false }
  }

  TestCase {
    name: "ControlCenter"
    when: windowShown

    function tile(key) {
      for (var i = 0; i < view.children.length; i++) {
        var found = findTile(view, key)
        if (found) return found
      }
      return null
    }
    function findTile(item, key) {
      if (item.key === key && item.proxy !== undefined) return item
      for (var i = 0; i < item.children.length; i++) {
        var found = findTile(item.children[i], key)
        if (found) return found
      }
      return null
    }

    function init() {
      // A QML runtime error in any Control Center test fails it (the known
      // Calendar warnings live in tst_calendar.qml, not here).
      failOnWarning(/TypeError|ReferenceError/)
      notifications.doNotDisturb = false
      nightlight.enabled = false
      nightlight.asked = []
      idle.stayAwake = false
      idle.asked = []
      view.links = [{ id: "omarchy.bluetooth", name: "Bluetooth" }, { id: "omarchy.network", name: "Network" }]
      closeSpy.clear()
      panelSpy.clear()
      for (var key of ["nightlight", "stayAwake", "doNotDisturb"]) { tile(key).pending = null; tile(key).failed = false }
      view.reset()
    }

    function test_tilesShowTheServicesState() {
      compare(tile("doNotDisturb").status, "off")
      notifications.doNotDisturb = true
      compare(tile("doNotDisturb").status, "on", "a change made elsewhere shows at once")
      idle.stayAwake = true
      compare(tile("stayAwake").status, "on")
      compare(tile("stayAwake").Accessible.checked, true)
      compare(tile("nightlight").status, "off")
    }

    function test_immediateServiceToggles() {
      mouseClick(tile("doNotDisturb"))
      verify(notifications.doNotDisturb)
      compare(tile("doNotDisturb").status, "on", "no pending state when the service applies at once")
      mouseClick(tile("doNotDisturb"))
      verify(!notifications.doNotDisturb)
      compare(tile("doNotDisturb").status, "off")
    }

    function test_laterServiceShowsPendingThenItsState() {
      mouseClick(tile("nightlight"))
      compare(nightlight.asked, [true])
      compare(tile("nightlight").status, "pending", "not on before the service says so")
      compare(tile("nightlight").on, false)
      mouseClick(tile("nightlight"))
      compare(nightlight.asked, [true], "a second press waits for the answer")
      nightlight.enabled = true
      compare(tile("nightlight").status, "on")
    }

    function test_unansweredRequestReadsFailed() {
      mouseClick(tile("stayAwake"))
      compare(idle.asked, [false], "staying awake asks for idle disabled")
      compare(tile("stayAwake").status, "pending")
      tryCompare(tile("stayAwake"), "status", "failed", 1000)
      compare(tile("stayAwake").on, false, "the state is still the service's")
      idle.stayAwake = true
      compare(tile("stayAwake").status, "on", "the next real change clears it")
    }

    function test_unavailableServiceIsInert() {
      var bare = createTemporaryObject(bareView, scene)
      var night = findTile(bare, "nightlight")
      compare(night.status, "unavailable")
      verify(!night.activeFocusOnTab, "not reachable by keyboard")
      night.activate()
      compare(night.status, "unavailable")
      compare(nightlight.asked, [], "nothing was asked")
      compare(findTile(bare, "doNotDisturb").status, "off", "the others still work")
    }

    function test_keyboard() {
      view.forceActiveFocus()
      view.reset()
      verify(tile("nightlight").activeFocus, "opens on the first control")
      keyClick(Qt.Key_Right)
      verify(tile("stayAwake").activeFocus)
      verify(view.keyboardShown)
      keyClick(Qt.Key_Right)
      keyClick(Qt.Key_Space)
      verify(notifications.doNotDisturb, "Space toggles the focused tile")
      // No audio device here, so Down goes on to the More group.
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      compare(view.page, "panels", "All panels opens the panels page")
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      compare(panelSpy.count, 1)
      compare(panelSpy.signalArguments[0][0], "omarchy.bluetooth")
      keyClick(Qt.Key_Escape)
      compare(view.page, "main", "Escape goes back first")
      compare(closeSpy.count, 0)
      keyClick(Qt.Key_Escape)
      compare(closeSpy.count, 1)
    }

    function test_linksOpenTheirPanel() {
      view.showPanels()
      var found = null
      function walk(item) {
        if (item.accessibleName === "Open Network") found = found || item
        for (var i = 0; i < item.children.length; i++) walk(item.children[i])
      }
      walk(view)
      verify(found !== null)
      mouseClick(found)
      compare(panelSpy.count, 1)
      compare(panelSpy.signalArguments[0][0], "omarchy.network")
    }

    function test_fixedHeight() {
      var height = view.implicitHeight
      view.links = []
      compare(view.implicitHeight, height)
      view.links = [{ id: "a", name: "A" }, { id: "b", name: "B" }, { id: "c", name: "C" }, { id: "d", name: "D" }, { id: "e", name: "E" }, { id: "f", name: "F" }]
      compare(view.implicitHeight, height)
    }

    // The entry follows the popout contract KeyboardPanel and the coordinator use.
    function test_entryFollowsThePopoutContract() {
      compare(entry.implicitWidth, testTheme.m.statusSlot)
      entry.opened = true
      entry.close()
      verify(!entry.opened, "Escape and an outside click close through owner.close()")
      entry.opened = true
      entry.triggerPress(Qt.LeftButton)
      verify(!entry.opened, "a forwarded click on the entry closes it")
      entry.open()
      verify(!entry.opened, "never opens without its panel (no bar here)")
    }

    // Another panel opening closes the Control Center, and back.
    function test_oneAtATime() {
      entry.opened = true
      hosting.requestPopout("floating-islands", entry)
      compare(hosting.activePopout, entry)
      other.opened = true
      hosting.requestPopout("omarchy.bluetooth", other)
      verify(!entry.opened, "the Control Center hands over")
      compare(hosting.activePopout, other)
      hosting.releasePopout("omarchy.bluetooth", other)
      compare(hosting.activePopout, null)
    }
  }
}
