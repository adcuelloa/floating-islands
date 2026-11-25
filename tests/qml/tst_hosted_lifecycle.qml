import QtQuick
import QtTest
import "../../plugin/theme"
import "../../plugin/core"
import "../../plugin/widgets"

// The status island across shell.json changes and registry updates (trial 5:
// after shell.json was rewritten, only one of six hosted widgets came back).
// Each test builds its own island over its own registry; widget ids are unique
// per test because the last-live component cache is shared, as it is live.
Item {
  id: scene
  width: 900
  height: 120

  Theme { id: appTheme }

  QtObject {
    id: fakeBar
    property var theme: appTheme
    property string fontFamily: "monospace"
    property string position: "top"
    property var publicLayout: ({})
    property var shell: QtObject {
      function pluginShellForBarEntry(owner, moduleName) { return { pluginId: moduleName } }
    }
    function barSizeFor(name) { return 50 }
  }

  WidgetHosting { id: appHosting; bar: fakeBar }

  // A bar widget that counts its instances, as each one would register an IPC
  // handler in the shell.
  property int alive: 0
  Component {
    id: widgetA
    Item {
      property var bar
      property string moduleName
      property var settings
      property string fixedEdge
      readonly property string kind: "A"
      implicitWidth: 40
      implicitHeight: 20
      Component.onCompleted: scene.alive += 1
      Component.onDestruction: scene.alive -= 1
    }
  }
  Component {
    id: widgetB
    Item {
      property var bar
      property string moduleName
      property var settings
      readonly property string kind: "B"
      implicitWidth: 40
      implicitHeight: 20
      Component.onCompleted: scene.alive += 1
      Component.onDestruction: scene.alive -= 1
    }
  }

  Component {
    id: registryComponent
    QtObject {
      property int revision: 1
      property var widgets: ({})
      // As the shell's register(): a new map and a new revision.
      function put(id, component) {
        var next = {}
        for (var k in widgets) next[k] = widgets[k]
        next[id] = { component: component, metadata: {} }
        widgets = next
        revision++
      }
      function drop(id) {
        var next = {}
        for (var k in widgets) if (k !== id) next[k] = widgets[k]
        widgets = next
        revision++
      }
    }
  }

  Component {
    id: islandComponent
    HostedIsland {
      theme: appTheme
      hosting: appHosting
      screenName: "DP-1"
    }
  }

  TestCase {
    name: "HostedLifecycle"
    when: windowShown

    property var made: []

    function cleanup() {
      for (var i = 0; i < made.length; i++) {
        try { if (made[i]) made[i].destroy() } catch (e) { }
      }
      made = []
      wait(0)
    }

    function registryWith(ids, component) {
      var registry = registryComponent.createObject(scene)
      for (var i = 0; i < ids.length; i++) registry.put(ids[i], component || widgetA)
      made.push(registry)
      return registry
    }

    function islandOver(registry, ids) {
      var island = islandComponent.createObject(scene, { registry: registry, entries: entries(ids) })
      made.push(island)
      return island
    }

    function entries(ids, settings) {
      return ids.map(function(id) { return { id: id, settings: settings || {} } })
    }

    function itemOf(id) {
      var items = appHosting.itemsFor(id)
      return items.length === 1 ? items[0] : null
    }

    function order(island) {
      var cells = []
      for (var i = 0; i < island.children.length; i++) collect(island.children[i], cells)
      cells.sort(function(a, b) { return a.mapToItem(scene, 0, 0).x - b.mapToItem(scene, 0, 0).x })
      return cells.map(function(cell) { return cell.wid })
    }

    function collect(item, out) {
      if (item.objectName === "hostedSlot") { out.push(item); return }
      for (var i = 0; i < item.children.length; i++) collect(item.children[i], out)
    }

    // A rewritten shell.json hands the bar a new layout array every time; the
    // widgets that stay configured must keep their instances.
    function test_configChangesKeepWidgetInstances() {
      var ids = ["life.keep.a", "life.keep.b", "life.keep.c"]
      var island = islandOver(registryWith(ids), ids)
      tryVerify(function() { return itemOf("life.keep.c") !== null })
      var before = ids.map(itemOf)
      var count = scene.alive
      for (var n = 0; n < 10; n++) island.entries = entries(ids, { step: n })
      wait(0)
      for (var i = 0; i < ids.length; i++) compare(itemOf(ids[i]), before[i], ids[i] + " keeps its instance")
      compare(scene.alive, count, "no widget was rebuilt")
      compare(itemOf("life.keep.a").settings.step, 9, "and each got its new settings")
      compare(appHosting.itemsFor("life.keep.b").length, 1, "registered once")
    }

    function test_reorderMovesWidgets() {
      var ids = ["life.order.a", "life.order.b", "life.order.c"]
      var island = islandOver(registryWith(ids), ids)
      tryVerify(function() { return itemOf("life.order.c") !== null })
      var a = itemOf("life.order.a")
      island.entries = entries(["life.order.c", "life.order.a", "life.order.b"])
      tryVerify(function() { return order(island).join() === "life.order.c,life.order.a,life.order.b" })
      compare(itemOf("life.order.a"), a, "moved, not rebuilt")
    }

    function test_removalAndReAddition() {
      var ids = ["life.rm.a", "life.rm.b"]
      var island = islandOver(registryWith(ids), ids)
      tryVerify(function() { return itemOf("life.rm.b") !== null })
      var a = itemOf("life.rm.a")
      island.entries = entries(["life.rm.a"])
      tryVerify(function() { return appHosting.itemsFor("life.rm.b").length === 0 })
      compare(itemOf("life.rm.a"), a)
      island.entries = entries(["life.rm.b", "life.rm.a"])
      tryVerify(function() { return itemOf("life.rm.b") !== null })
      compare(order(island).join(), "life.rm.b,life.rm.a")
      compare(itemOf("life.rm.a"), a)
    }

    // A plugin reload registers a new component: the slot rebuilds that one
    // widget, withdraws the old instance and injects the new one.
    function test_replacedComponentRebuildsOnlyThatWidget() {
      var ids = ["life.swap.a", "life.swap.b"]
      var registry = registryWith(ids)
      var island = islandOver(registry, ids)
      tryVerify(function() { return itemOf("life.swap.b") !== null })
      var b = itemOf("life.swap.b")
      registry.put("life.swap.a", widgetB)
      tryVerify(function() { return itemOf("life.swap.a") !== null && itemOf("life.swap.a").kind === "B" })
      compare(itemOf("life.swap.a").moduleName, "life.swap.a")
      verify(itemOf("life.swap.a").bar !== null, "the new instance got its facade")
      compare(itemOf("life.swap.b"), b, "the other widget kept its instance")
    }

    // The trial-5 failure: after a bar swap the new bar instance's registry
    // snapshot holds null where the components are still alive. The slot falls
    // back to the component the previous instance saw live.
    function test_deadSnapshotFallsBackToLastLiveComponent() {
      var ids = ["life.dead.a", "life.dead.b"]
      var first = islandOver(registryWith(ids), ids)
      tryVerify(function() { return itemOf("life.dead.b") !== null })
      first.destroy()
      tryVerify(function() { return appHosting.itemsFor("life.dead.a").length === 0 })

      var stale = registryComponent.createObject(scene, {
        widgets: { "life.dead.a": { component: null, metadata: {} }, "life.dead.b": { component: null, metadata: {} } }
      })
      made.push(stale)
      islandOver(stale, ids)
      tryVerify(function() { return itemOf("life.dead.a") !== null && itemOf("life.dead.b") !== null }, 1000,
        "both widgets load although the snapshot holds no live component")
      verify(itemOf("life.dead.a").bar !== null)
    }

    // When the shell then syncs the snapshot with the live component, nothing
    // is rebuilt; a registry that drops the entry removes the widget and the
    // fallback.
    function test_fallbackYieldsToTheRegistry() {
      var ids = ["life.sync.a"]
      var first = islandOver(registryWith(ids), ids)
      tryVerify(function() { return itemOf("life.sync.a") !== null })
      first.destroy()
      wait(0)
      var stale = registryComponent.createObject(scene, { widgets: { "life.sync.a": { component: null, metadata: {} } } })
      made.push(stale)
      islandOver(stale, ids)
      tryVerify(function() { return itemOf("life.sync.a") !== null })
      var item = itemOf("life.sync.a")
      var count = scene.alive
      stale.put("life.sync.a", widgetA)
      wait(0)
      compare(itemOf("life.sync.a"), item, "the same component: no rebuild")
      compare(scene.alive, count)
      stale.drop("life.sync.a")
      tryVerify(function() { return appHosting.itemsFor("life.sync.a").length === 0 })
      stale.put("life.sync.a", null)
      wait(0)
      compare(appHosting.itemsFor("life.sync.a").length, 0, "a dropped entry is not resurrected from the fallback")
    }

    // Widgets that are destroyed must not run queued injections afterwards.
    function test_noLateInjectionAfterTeardown() {
      var ids = ["life.late.a"]
      var island = islandOver(registryWith(ids), ids)
      tryVerify(function() { return itemOf("life.late.a") !== null })
      failOnWarning(/TypeError|invalid context/)
      island.entries = entries([])
      island.destroy()
      wait(50)
      compare(appHosting.itemsFor("life.late.a").length, 0)
    }
  }
}
