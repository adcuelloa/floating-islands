import QtQuick
import QtTest
import "../../plugin/theme"
import "../../plugin/core"
import "../../plugin/widgets"
import qs.Commons

// Hosting an Omarchy bar widget through the public PluginBarApi facade, as a
// user's cloned audio widget is hosted: props injected, sizes split between
// the button height and the bar thickness, one popout at a time, and shell
// summons routed to the widget.
Item {
  id: scene
  width: 900
  height: 120

  Theme { id: theme }

  // Stands in for Bar.qml: what WidgetHosting reads from the bar root.
  QtObject {
    id: fakeBar
    property var theme: theme
    property string fontFamily: "monospace"
    property string position: "top"
    property var publicLayout: ({ right: [{ id: "user.audio", step: 5 }] })
    property string pluginId: "floating-islands"
    property var barWidgetRegistry: registry
    property var shell: QtObject {
      property var entries: []
      function pluginShellForBarEntry(owner, moduleName) {
        entries = entries.concat([moduleName])
        return { pluginId: moduleName }
      }
    }
    function barSizeFor(name) { return 50 }
  }

  WidgetHosting { id: hosting; bar: fakeBar }

  // A bar widget shaped like Omarchy's: optional props, open/close/opened.
  Component {
    id: panelWidget
    Item {
      property var bar
      property string moduleName
      property var settings
      property string fixedEdge
      property bool opened: false
      property int clicks: 0
      implicitWidth: 40
      implicitHeight: bar ? bar.barSize : 0
      // The widget's own pointer handling, as WidgetButton has.
      readonly property bool hovered: ownArea.containsMouse
      MouseArea { id: ownArea; anchors.fill: parent; hoverEnabled: true; onClicked: parent.clicks += 1 }
      function open() { opened = true; bar.requestPopout(this) }
      function close() { opened = false; bar.releasePopout(this) }
      function closeForPopoutSwitch() { opened = false }
    }
  }

  QtObject {
    id: registry
    property int revision: 1
    property var widgets: ({
      "user.audio": { component: panelWidget, metadata: {} },
      "omarchy.power": { component: panelWidget, metadata: {} }
    })
  }

  HostedIsland {
    id: island
    theme: theme
    hosting: hosting
    registry: registry
    screenName: "DP-1"
    entries: [{ id: "user.audio", settings: { step: 5 } }, { id: "omarchy.power", settings: {} }, { id: "not.installed", settings: {} }]
  }

  Component {
    id: leadingEntry
    Rectangle { width: 30; height: 32 }
  }

  // A second hosting that a test tears down, as a hot reload does: the bar's
  // hosting goes before the widgets drawn on its surfaces.
  Component {
    id: doomedHosting
    WidgetHosting { bar: fakeBar }
  }

  TestCase {
    name: "Hosting"
    when: windowShown

    function items(id) { return hosting.itemsFor(id) }

    function test_injectsTheWidgetContract() {
      tryVerify(function() { return items("user.audio").length === 1 })
      var audio = items("user.audio")[0]
      compare(audio.moduleName, "user.audio")
      compare(audio.settings.step, 5)
      compare(audio.fixedEdge, "end")
      verify(audio.bar !== null)
      compare(audio.bar.pluginId, "user.audio")
      // The widget sizes its button to the island's inner height...
      compare(audio.bar.barSize, 32)
      compare(audio.implicitHeight, 32)
      // ...while its panel clears the whole bar.
      compare(audio.bar.barSizeFor("DP-1"), 50)
      compare(audio.bar.position, "top")
      compare(audio.bar.foreground, theme.foreground)
      verify(fakeBar.shell.entries.indexOf("user.audio") !== -1, "an entry facade was requested from the shell")
    }

    function test_unknownWidgetsTakeNoRoom() {
      compare(items("not.installed").length, 0)
      tryCompare(island, "implicitWidth", 2 + 2 * theme.m.buttonInset + 40 + theme.m.itemGap + 40)
      verify(island.visible)
    }

    function slotOf(item) {
      for (var p = item; p; p = p.parent) if (p.objectName === "hostedSlot") return p
      return null
    }

    // Hosted widgets get the islands' hover and pressed fills from passive
    // handlers around them; the widget still takes its own clicks.
    function test_hostedSlotsShowHoverAndPress() {
      var audio = items("user.audio")[0]
      var slot = slotOf(audio)
      verify(slot !== null)
      compare(slot.height, theme.m.islandHeight - 2 * theme.m.buttonInset)
      verify(slot.width >= theme.m.statusSlot)
      var fill = slot.fill
      mouseMove(audio, audio.width / 2, audio.height / 2)
      tryCompare(fill, "color", theme.hover)
      tryVerify(function() { return audio.hovered }, 1000, "the widget still sees hover (its tooltips depend on it)")
      mousePress(audio, audio.width / 2, audio.height / 2)
      tryCompare(fill, "color", theme.pressed)
      mouseRelease(audio, audio.width / 2, audio.height / 2)
      compare(audio.clicks, 1, "the widget's own MouseArea still gets the click")
      mouseMove(island, -20, -20)
      tryVerify(function() { return fill.color.a === 0 }, 1000, "no fill once the pointer leaves")
    }

    function test_onePopoutAtATime() {
      var audio = items("user.audio")[0]
      var power = items("omarchy.power")[0]
      audio.open()
      verify(audio.opened)
      compare(audio.bar.activePopout, audio)
      compare(power.bar.activePopout, power.bar.foreignPopoutMarker, "another widget's popout is not handed over")
      power.open()
      verify(power.opened)
      verify(!audio.opened, "opening a second panel closes the first")
      power.close()
      compare(hosting.activePopout, null)
    }

    function test_shellSummonsReachTheWidget() {
      verify(hosting.summon("user.audio"))
      verify(hosting.isOpen("user.audio"))
      verify(hosting.hide("user.audio"))
      verify(!hosting.isOpen("user.audio"))
      verify(!hosting.summon("not.installed"))
      compare(hosting.panelIdAt("right", 1), "user.audio")
      compare(hosting.panelIdAt("right", 2), "omarchy.power")
      compare(hosting.panelIdAt("left", 1), "")
    }

    // An extraHosted widget answers the shell by name but takes no number,
    // as a centre widget has none on the stock bar.
    function test_unnumberedWidgetsKeepTheirNamedRoute() {
      hosting.unnumbered = ["user.audio"]
      compare(hosting.panelIdAt("right", 1), "omarchy.power")
      compare(hosting.panelIdAt("right", 2), "")
      verify(hosting.summon("user.audio"))
      verify(hosting.isOpen("user.audio"))
      verify(hosting.hide("user.audio"))
      verify(!hosting.isOpen("user.audio"))
      hosting.unnumbered = []
      compare(hosting.panelIdAt("right", 1), "user.audio")
    }

    function test_switchPanelWalksTheRow() {
      var audio = items("user.audio")[0]
      var power = items("omarchy.power")[0]
      audio.open()
      verify(audio.bar.switchPanelFrom(audio, 1))
      verify(power.opened)
      power.close()
    }

    function test_clickTargetsStayWithTheirOwner() {
      var audio = items("user.audio")[0]
      var power = items("omarchy.power")[0]
      audio.bar.registerClickTarget(audio)
      compare(audio.bar.clickTargets.length, 1)
      compare(power.bar.clickTargets.length, 0)
      power.bar.unregisterClickTarget(audio)
      compare(audio.bar.clickTargets.length, 1, "a widget cannot drop another's target")
      audio.bar.unregisterClickTarget(audio)
      compare(audio.bar.clickTargets.length, 0)
    }

    // The calendar and Omarchy's own widgets see every bar button, so their
    // KeyboardPanel hands a click on another widget over in one click (as on
    // the stock bar); a third-party plugin still sees only its own.
    function test_trustedPanelsSeeEveryBarButton() {
      var audio = items("user.audio")[0]
      var power = items("omarchy.power")[0]
      var native = hosting.facadeFor("floating-islands")
      var widgets = registry.widgets
      registry.widgets = ({
        "user.audio": widgets["user.audio"],
        "omarchy.power": { component: widgets["omarchy.power"].component, metadata: { firstParty: true } }
      })
      audio.bar.registerClickTarget(audio)
      power.bar.registerClickTarget(power)
      native.registerClickTarget(scene)
      compare(native.clickTargets.length, 3, "the calendar can forward to hosted buttons")
      compare(power.bar.clickTargets.length, 3, "a first-party widget sees the others")
      compare(audio.bar.clickTargets.length, 1, "a third-party plugin sees only its own")
      compare(audio.bar.clickTargets[0], audio)
      power.bar.unregisterClickTarget(audio)
      compare(audio.bar.clickTargets.length, 1, "seeing a target does not allow dropping it")
      audio.bar.unregisterClickTarget(audio)
      power.bar.unregisterClickTarget(power)
      native.unregisterClickTarget(scene)
      compare(native.clickTargets.length, 0)
      registry.widgets = widgets
    }

    // The Control Center's entry leads the island but is not a hosted widget:
    // the island grows by its slot and the hotkey numbers do not move.
    function test_leadingEntryTakesNoNumber() {
      tryVerify(function() { return hosting.panelIdAt("right", 2) === "omarchy.power" })
      var width = island.implicitWidth
      island.leading = leadingEntry
      tryCompare(island, "implicitWidth", width + 30 + theme.m.itemGap)
      verify(island.leadingItem !== null)
      compare(hosting.panelIdAt("right", 1), "user.audio")
      compare(hosting.panelIdAt("right", 2), "omarchy.power")
      compare(hosting.panelIds(false), ["user.audio", "omarchy.power"])
      island.leading = null
      tryCompare(island, "implicitWidth", width)
      compare(island.leadingItem, null)
    }

    function test_runGoesThroughOmarchy() {
      var audio = items("user.audio")[0]
      audio.bar.run("pamixer -t")
      verify(Util.ran.indexOf("pamixer -t") !== -1)
    }

    // Trial 4: 27-64 TypeErrors per hot reload ("Cannot read property
    // 'foreground' of null") from hosted panels, because the facades died
    // with the hosting while the widgets that bind to them were still alive.
    function test_facadesOutliveTheirHosting() {
      var doomed = doomedHosting.createObject(scene)
      var api = doomed.facadeFor("user.audio")
      compare(api.foreground, theme.foreground)
      doomed.destroy()
      wait(0)
      tryVerify(function() { return api !== null && api.fontFamily === "monospace" }, 1000, "the facade survives its hosting")
      compare(api.foreground, theme.foreground, "and keeps its last values")
      api.showTooltip(scene, "late")
      api.registerClickTarget(scene)
      compare(api.clickTargets.length, 0, "a retired facade does nothing")
    }
  }
}
