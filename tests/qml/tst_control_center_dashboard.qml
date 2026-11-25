import QtQuick
import QtTest
import qs.Commons
import qs.Commons as Commons
import "../../plugin/theme"
import "../../plugin/widgets"
import "../../plugin/logic/ControlCenter.js" as Model
import "../../plugin/theme/Palette.js" as Palette

// The grouped Control Center against fake providers and services, with the
// real string catalogs, sized the way Omarchy's KeyboardPanel sizes it: a
// card of Model.cardWidth() capped at the output, minus padding, and a
// height capped at the space below the bar. Checks geometry at several
// outputs, languages and font/theme scales, the keyboard model, scrolling
// and the two pages.
Item {
  id: scene
  width: 1600
  height: 1000

  Theme { id: testTheme }

  // The real catalogs (plugin/i18n), read the way Commons.Translations
  // serves them: the language's string, else English, else the key.
  QtObject {
    id: catalogs

    property string lang: "en"
    property var loaded: ({})

    function read(code) {
      if (loaded[code]) return loaded[code]
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../../plugin/i18n/" + code + ".json"), false)
      xhr.send()
      var data = JSON.parse(xhr.responseText)
      var copy = loaded
      copy[code] = data
      loaded = copy
      return data
    }
  }

  QtObject {
    id: testStrings

    // Re-evaluated by bindings when the language changes.
    property string lang: catalogs.lang
    function t(key) {
      var own = catalogs.read(lang)[key]
      if (own !== undefined) return own
      var en = catalogs.read("en")[key]
      return en !== undefined ? en : key
    }
  }

  component FakeRadio: QtObject {
    property bool available: true
    property bool blocked: false
    property bool on: false
    property bool connected: false
    property string detail: ""
    property int count: 1
    property var asked: []
    function request(on, done) { asked = asked.concat([on]); return true }
    function refresh() {}
  }
  component FakeService: QtObject {
    property bool enabled: false
    property bool stayAwake: false
    property bool doNotDisturb: false
    function setNightlight(v) { enabled = v }
    function setIdleEnabled(v) { stayAwake = !v }
    function setDoNotDisturb(v) { doNotDisturb = v }
  }
  component FakeSink: QtObject {
    property bool ready: true
    property string description: "Built-in Audio Analog Stereo"
    property QtObject audio: QtObject {
      property real volume: 0.5
      property bool muted: false
    }
  }

  FakeRadio { id: wifi; on: true; connected: true; detail: "A network with a rather long name" }
  FakeRadio { id: bt; on: true }
  FakeService { id: nightlight }
  FakeService { id: idle }
  FakeService { id: notifications }
  FakeSink { id: sink }
  QtObject {
    id: power
    property bool available: true
    property var profiles: ["power-saver", "balanced", "performance"]
    property string current: "performance"
    property string degraded: ""
    property bool onBattery: false
    property var asked: []
    function request(profile, done) { asked = asked.concat([profile]); return "ac" }
    function refresh() {}
  }
  // Shaped like adapters/BrightnessAdapter.qml; records what was asked.
  QtObject {
    id: bright
    property bool available: true
    property int percent: 60
    property int desired: -1
    property bool pending: false
    property string outcome: ""
    property var asked: []
    property int refreshes: 0
    function setPercent(v) { asked = asked.concat([v]); return true }
    function refresh() { refreshes++ }
  }

  readonly property var realLinks: [
    { id: "omarchy.agents", name: "Agents" }, { id: "omarchy.bluetooth", name: "Bluetooth" },
    { id: "omarchy.network", name: "Network" }, { id: "user.audio", name: "My Audio" },
    { id: "omarchy.monitor", name: "Display" }, { id: "omarchy.power", name: "Power" }
  ]

  // Stands in for KeyboardPanel's content area: its width and height are
  // what the panel would give the view.
  Item {
    id: host
    x: 10
    y: 10

    ControlCenterView {
      id: view
      anchors.fill: parent
      theme: testTheme
      strings: testStrings
      services: ({ nightlight: nightlight, stayAwake: idle, doNotDisturb: notifications })
      wifi: wifi
      bluetooth: bt
      audioSink: sink
      audioPanelId: "user.audio"
      wifiPanelId: "omarchy.network"
      bluetoothPanelId: "omarchy.bluetooth"
      powerProfile: power
      brightness: bright
      links: scene.realLinks
    }
  }

  SignalSpy { id: closeSpy; target: view; signalName: "closeRequested" }
  SignalSpy { id: panelSpy; target: view; signalName: "panelRequested" }

  TestCase {
    name: "ControlCenterDashboard"
    when: windowShown

    // KeyboardPanel: padding 16 (scaled), margin 5, a 40 px island bar plus
    // its gap at the top (scaled).
    function fit(screenW, screenH) {
      var s = testTheme.m.scale
      var padding = Math.round(16 * s)
      var availW = Math.max(120, screenW - 10)
      var availH = Math.max(120, screenH - Math.round(56 * s) - 5)
      var card = Math.min(Model.cardWidth(screenW, s), availW)
      host.width = card - 2 * padding
      wait(0)
      host.height = Math.min(view.implicitHeight, availH - 2 * padding)
      wait(50) // Grid and Flow lay out on polish
      host.height = Math.min(view.implicitHeight, availH - 2 * padding)
      wait(20)
      return { card: card, content: host.width, height: host.height, implicit: view.implicitHeight }
    }

    function find(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var found = find(item.children[i], name)
        if (found) return found
      }
      return null
    }
    function findAll(item, name, out) {
      out = out || []
      if (item.objectName === name) out.push(item)
      for (var i = 0; i < item.children.length; i++) findAll(item.children[i], name, out)
      return out
    }
    function tile(kind) {
      var hit = null
      function walk(item) {
        if ((item.kind === kind || item.key === kind) && typeof item.activate === "function") hit = hit || item
        for (var i = 0; i < item.children.length; i++) walk(item.children[i])
      }
      walk(view)
      return hit
    }
    function focused() {
      var list = view.controls()
      for (var i = 0; i < list.length; i++) if (list[i].activeFocus) return list[i]
      return null
    }
    // Nothing on the visible page reaches past the view's right edge.
    function checkHorizontal(label) {
      var list = view.controls()
      for (var i = 0; i < list.length; i++) {
        var p = list[i].mapToItem(view, 0, 0)
        verify(p.x >= -0.5 && p.x + list[i].width <= view.width + 0.5,
               label + ": control " + i + " spans " + p.x + ".." + (p.x + list[i].width) + " of " + view.width)
      }
    }
    // Every compact tile's label fits in two lines without eliding, and
    // every radio tile's title in one.
    function checkLabels(label) {
      var titles = findAll(view, "radioLabel")
      compare(titles.length, 2)
      for (var t = 0; t < titles.length; t++) verify(!titles[t].truncated, label + ": " + titles[t].text + " is cut")
      var segments = findAll(view, "profileLabel")
      compare(segments.length, 3)
      for (var q = 0; q < segments.length; q++) {
        verify(segments[q].lineCount <= 2, label + ": " + segments[q].text + " takes " + segments[q].lineCount + " lines")
        verify(!segments[q].truncated, label + ": " + segments[q].text + " is cut")
      }
      var labels = findAll(view, "tileLabel")
      compare(labels.length, 3)
      for (var i = 0; i < labels.length; i++) {
        verify(labels[i].lineCount <= 2, label + ": " + labels[i].text + " takes " + labels[i].lineCount + " lines")
        verify(!labels[i].truncated, label + ": " + labels[i].text + " is cut")
      }
    }
    // Every tile in the System grid has the same height.
    function checkRows(label) {
      var h = tile("nightlight").height
      compare(tile("stayAwake").height, h, label)
      compare(tile("doNotDisturb").height, h, label)
      verify(h >= tile("nightlight").implicitHeight)
    }

    function init() {
      // A QML runtime error in any Control Center test fails it (the known
      // Calendar warnings live in tst_calendar.qml, not here).
      failOnWarning(/TypeError|ReferenceError/)
      catalogs.lang = "en"
      Style.fontScale = 1
      Style.spacing.scale = 1
      wifi.available = true; wifi.on = true; wifi.connected = true; wifi.asked = []
      power.available = true; power.profiles = ["power-saver", "balanced", "performance"]; power.current = "performance"; power.asked = []
      var pc = find(view, "profilesControl"); if (pc) { pc.request = null; pc.outcome = "" }
      bt.available = true; bt.on = true; bt.asked = []
      bright.available = true; bright.percent = 60; bright.desired = -1; bright.pending = false; bright.outcome = ""; bright.asked = []; bright.refreshes = 0
      nightlight.enabled = false; idle.stayAwake = false; notifications.doNotDisturb = false
      view.links = scene.realLinks
      for (var k of ["wifi", "bluetooth"]) { tile(k).pending = null; tile(k).asking = false; tile(k).failed = false }
      for (var key of ["nightlight", "stayAwake", "doNotDisturb"]) { tile(key).pending = null; tile(key).failed = false }
      closeSpy.clear(); panelSpy.clear()
      fit(1536, 864)
      view.forceActiveFocus()
      view.reset()
    }

    function cleanupTestCase() {
      Style.fontScale = 1
      Style.spacing.scale = 1
    }

    // ------------------------------------------------------------ geometry

    function test_1536x864() {
      var g = fit(1536, 864)
      compare(g.card, 384)
      compare(g.content, 352)
      compare(view.connectivityColumns, 2)
      compare(view.systemColumns, 3)
      compare(g.height, g.implicit, "the whole dashboard fits: no scrolling")
      verify(!find(view, "scrollIndicator").visible)
      checkHorizontal("1536")
      checkLabels("1536")
      checkRows("1536")
      console.log("measured 1536x864: card", g.card, "content", g.content, "x", g.implicit)
    }

    function test_1280x720() {
      var g = fit(1280, 720)
      compare(g.card, 340)
      compare(g.content, 308)
      compare(view.connectivityColumns, 2)
      compare(view.systemColumns, 3)
      compare(g.height, g.implicit)
      checkHorizontal("1280")
      checkLabels("1280")
      console.log("measured 1280x720: card", g.card, "content", g.content, "x", g.implicit)
    }

    // A narrow output: the card takes what there is and the grids drop
    // columns instead of squeezing or hiding anything.
    function test_narrow() {
      var g = fit(300, 640)
      compare(g.card, 290, "capped at the output")
      compare(view.connectivityColumns, 1)
      compare(view.systemColumns, 2)
      checkHorizontal("narrow")
      checkLabels("narrow")
      checkRows("narrow")
      verify(view.controls().length >= 9, "nothing hidden: " + view.controls().length)
      console.log("measured 300x640: card", g.card, "content", g.content, "x", g.implicit, "shown", g.height)
    }

    function test_longTranslations() {
      var heights = {}
      for (var lang of ["es", "ja", "en"]) {
        catalogs.lang = lang
        var g = fit(1536, 864)
        checkHorizontal(lang)
        checkLabels(lang)
        checkRows(lang)
        compare(find(view, "groupSound").title, testStrings.t("controlCenter.group.sound"))
        heights[lang] = g.implicit
        console.log("measured", lang, "1536x864:", g.content, "x", g.implicit)
      }
      catalogs.lang = "es"
      fit(1280, 720)
      checkLabels("es 1280")
    }

    // The status line may elide (a long network name); the full text stays
    // in the accessible description.
    function test_elidedStatusKeepsTheFullText() {
      var toggle = tile("wifi").controls()[0]
      compare(toggle.Accessible.description, "A network with a rather long name")
    }

    function test_fontAndThemeScale() {
      var base = fit(1536, 864)
      Style.fontScale = 1.4
      var bigFont = fit(1536, 864)
      verify(bigFont.implicit > base.implicit, "a larger font grows the dashboard")
      checkHorizontal("font 1.4")
      checkLabels("font 1.4")
      checkRows("font 1.4")
      fit(1280, 720)
      checkLabels("font 1.4 at 1280")
      Style.fontScale = 1
      Style.spacing.scale = 1.25
      var scaled = fit(1536, 864)
      verify(scaled.card > base.card)
      checkHorizontal("scale 1.25")
      checkRows("scale 1.25")
      console.log("measured font 1.4:", bigFont.content, "x", bigFont.implicit, "; scale 1.25:", scaled.content, "x", scaled.implicit)
    }

    // A short output and a large font: the panel gives less height than the
    // dashboard needs, the page scrolls, and focus brings each control into view.
    function test_scrollsWhenShort() {
      Style.fontScale = 1.4
      var g = fit(1280, 480)
      verify(g.height < g.implicit, g.height + " vs " + g.implicit)
      var flick = find(view, "pageScroll")
      verify(flick.interactive)
      verify(find(view, "scrollIndicator").visible)
      view.forceActiveFocus()
      view.reset()
      for (var i = 0; i < 12; i++) {
        keyClick(Qt.Key_Down)
        var item = focused()
        verify(item !== null, "focus stays on a control")
        var p = item.mapToItem(flick, 0, 0)
        verify(p.y >= -0.5 && p.y + item.height <= flick.height + 0.5,
               "control " + i + " in view: " + p.y + ".." + (p.y + item.height) + " of " + flick.height)
      }
      compare(focused().objectName, "morePanels", "Down reaches the last group")
      keyClick(Qt.Key_Tab)
      compare(flick.contentY, 0, "back to the top for the first group")
    }

    // ---------------------------------------------------------- keyboard

    function test_tabBetweenGroups() {
      var wifiToggle = tile("wifi").controls()[0]
      verify(wifiToggle.activeFocus, "opens on the first control")
      keyClick(Qt.Key_Tab)
      verify(tile("nightlight").activeFocus, "System")
      verify(view.keyboardShown)
      keyClick(Qt.Key_Right)
      verify(tile("stayAwake").activeFocus)
      keyClick(Qt.Key_Tab)
      compare(focused().objectName, "profile:performance", "the profile selector, at the selected profile")
      keyClick(Qt.Key_Tab)
      compare(focused().Accessible.name, "Mute output", "Sound & Display")
      keyClick(Qt.Key_Tab)
      compare(focused().objectName, "morePanels", "More")
      keyClick(Qt.Key_Tab)
      verify(wifiToggle.activeFocus, "wraps to Connectivity")
      keyClick(Qt.Key_Backtab)
      compare(focused().objectName, "morePanels")
      keyClick(Qt.Key_Backtab)
      keyClick(Qt.Key_Backtab)
      compare(focused().objectName, "profile:performance", "Shift+Tab enters the selector")
      keyClick(Qt.Key_Backtab)
      verify(tile("stayAwake").activeFocus, "Shift+Tab leaves it; back where System was left")
      compare(power.asked.length, 0, "no Tab stop selects a profile")
    }

    function test_arrowsInsideAndAcross() {
      var w = tile("wifi").controls()
      var b = tile("bluetooth").controls()
      keyClick(Qt.Key_Right)
      verify(w[1].activeFocus, "the Wi-Fi panel link is its own stop")
      keyClick(Qt.Key_Right)
      verify(b[0].activeFocus)
      keyClick(Qt.Key_Right)
      verify(b[1].activeFocus)
      keyClick(Qt.Key_Right)
      verify(b[1].activeFocus, "Left/Right stop at the group's edge")
      keyClick(Qt.Key_Down)
      verify(tile("doNotDisturb").activeFocus, "Down into System at the nearest column")
      keyClick(Qt.Key_Up)
      verify(tile("wifi").controls()[0].activeFocus || b[0].activeFocus || b[1].activeFocus || w[1].activeFocus)
    }

    // The power profile selector is one Tab stop under the System heading:
    // the first Tab enters it at the selected profile, later ones where
    // focus was left; Left/Right move between
    // profiles without selecting and stop at its ends, Space or Enter
    // asks for the focused one, Down/Up still cross to the neighbours.
    function test_profileRow() {
      keyClick(Qt.Key_Tab)
      verify(tile("nightlight").activeFocus)
      keyClick(Qt.Key_Down)
      compare(focused().objectName, "profile:power-saver", "Down from a tile")
      keyClick(Qt.Key_Left)
      compare(focused().objectName, "profile:power-saver", "Left stops at the first profile")
      keyClick(Qt.Key_Right)
      compare(focused().objectName, "profile:balanced")
      keyClick(Qt.Key_Right)
      keyClick(Qt.Key_Right)
      compare(focused().objectName, "profile:performance", "Right stops at the last profile, not in Sound")
      keyClick(Qt.Key_Left)
      compare(power.asked.length, 0, "focus does not select")
      compare(power.current, "performance")
      keyClick(Qt.Key_Space)
      compare(power.asked, ["balanced"], "Space asks for the focused profile")
      keyClick(Qt.Key_Down)
      compare(focused().Accessible.name, "Output volume", "Down leaves for Sound & Display, nearest column")
      keyClick(Qt.Key_Backtab)
      compare(focused().objectName, "profile:balanced", "Shift+Tab back in, where focus was left")
      keyClick(Qt.Key_Up)
      verify(tile("stayAwake").activeFocus, "Up to the tiles, nearest column")
    }

    function test_profileEnter() {
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Tab)
      compare(focused().objectName, "profile:performance")
      keyClick(Qt.Key_Return)
      compare(power.asked.length, 0, "Enter on the selected profile asks nothing")
      keyClick(Qt.Key_Left)
      keyClick(Qt.Key_Left)
      compare(focused().objectName, "profile:power-saver")
      keyClick(Qt.Key_Enter)
      compare(power.asked, ["power-saver"], "keypad Enter asks for the focused profile")
    }

    // The selected and the focused profile look different from each other
    // and from the rest.
    function test_profileSelectedVersusFocused() {
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Left)
      var focusedSeg = find(view, "profile:balanced")
      var selected = find(view, "profile:performance")
      var other = find(view, "profile:power-saver")
      verify(focusedSeg.activeFocus)
      verify(selected.Accessible.checked && !focusedSeg.Accessible.checked)
      verify(!Qt.colorEqual(selected.color, focusedSeg.color), "selected fill differs from focused")
      verify(!Qt.colorEqual(focusedSeg.border.color, other.border.color), "focused edge differs from an unfocused one")
      verify(!find(selected, "litFocusRing").visible, "no ring on the selected profile while unfocused")
      keyClick(Qt.Key_Right)
      verify(find(selected, "litFocusRing").visible, "inset ring when the selected profile has focus")
    }

    // Only the profiles the daemon offers are stops.
    function test_profileOnlyOffered() {
      power.profiles = ["balanced", "performance"]
      wait(50)
      view.reset()
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Tab)
      compare(focused().objectName, "profile:performance")
      keyClick(Qt.Key_Left)
      keyClick(Qt.Key_Left)
      compare(focused().objectName, "profile:balanced", "no stop for an unsupported profile")
      compare(find(view, "profile:power-saver"), null)
    }

    // Unavailable: Tab passes from System straight to Sound & Display.
    function test_profileUnavailableTab() {
      power.available = false
      wait(50)
      view.reset()
      keyClick(Qt.Key_Tab)
      verify(tile("nightlight").activeFocus)
      keyClick(Qt.Key_Tab)
      compare(focused().Accessible.name, "Mute output", "the empty selector is skipped")
      keyClick(Qt.Key_Backtab)
      verify(tile("nightlight").activeFocus, "and skipped backwards")
    }

    // Tab memory of the other groups survives a pass through the selector.
    function test_profileKeepsOtherGroupsMemory() {
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Right)
      keyClick(Qt.Key_Right)
      verify(tile("doNotDisturb").activeFocus)
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Left)
      compare(focused().objectName, "profile:balanced")
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Right)
      var slider = focused()
      keyClick(Qt.Key_Backtab)
      compare(focused().objectName, "profile:balanced", "the selector re-enters where focus was left")
      keyClick(Qt.Key_Backtab)
      verify(tile("doNotDisturb").activeFocus, "System where it was left")
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Tab)
      verify(slider.activeFocus, "Sound & Display where it was left")
      compare(power.asked.length, 0)
      view.reset()
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Tab)
      compare(focused().objectName, "profile:performance", "after reopening, the selected profile again")
    }

    // A physical Shift+Tab reaches Qt as an ambiguous shortcut (it
    // matches both Backtab and Shift+Tab); it must still move back.
    function test_backtabWhenAmbiguous() {
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Left)
      keyClick(Qt.Key_Tab)
      compare(focused().Accessible.name, "Mute output")
      var shortcut = null
      for (var i = 0; i < view.data.length; i++)
        if (view.data[i].objectName === "backtabShortcut") shortcut = view.data[i]
      verify(shortcut !== null)
      shortcut.activatedAmbiguously()
      compare(focused().objectName, "profile:balanced", "back to the profile last focused")
      shortcut.activatedAmbiguously()
      verify(tile("nightlight").activeFocus, "and on to System")
      compare(power.asked.length, 0)
    }

    // ------------------------------------------------------- brightness

    // Below the audio rows in Sound & Display: Down from the audio
    // settings link reaches it, Left/Right adjust without leaving, Up/Down
    // leave, and only Left/Right/Page/Home/End ask for a level.
    function test_brightnessRow() {
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Tab)
      compare(focused().Accessible.name, "Mute output")
      keyClick(Qt.Key_Down)
      compare(focused().objectName, "moreAudio")
      keyClick(Qt.Key_Down)
      compare(focused().objectName, "brightnessSlider", "Down reaches brightness")
      compare(focused().Accessible.name, "Brightness")
      compare(focused().Accessible.role, Accessible.Slider)
      compare(bright.asked.length, 0, "focus asks nothing")
      keyClick(Qt.Key_Right)
      compare(bright.asked, [65], "one 5 % step up")
      verify(focused().objectName === "brightnessSlider", "Right stays on the slider")
      keyClick(Qt.Key_Left)
      compare(bright.asked[1], 55)
      keyClick(Qt.Key_Home)
      compare(bright.asked[2], 0, "Home asks for the bottom; the adapter makes it 1 %")
      keyClick(Qt.Key_Down)
      compare(focused().objectName, "morePanels", "Down leaves for More")
      keyClick(Qt.Key_Up)
      compare(focused().objectName, "brightnessSlider")
      keyClick(Qt.Key_Up)
      compare(focused().objectName, "moreAudio", "Up leaves for the audio rows")
      compare(sink.audio.volume, 0.5, "the audio slider is untouched")
    }

    // Tab memory: the Sound group re-enters on brightness when left there.
    function test_brightnessTabMemory() {
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      compare(focused().objectName, "brightnessSlider")
      keyClick(Qt.Key_Tab)
      compare(focused().objectName, "morePanels")
      keyClick(Qt.Key_Backtab)
      compare(focused().objectName, "brightnessSlider", "back where Sound & Display was left")
      compare(bright.asked.length, 0)
    }

    function test_brightnessUnavailableSkipped() {
      bright.available = false
      bright.percent = -1
      wait(20)
      view.reset()
      var list = view.controls()
      for (var i = 0; i < list.length; i++) verify(list[i].objectName !== "brightnessSlider", "not a stop")
      compare(find(view, "brightnessStatus").text, "Unavailable")
      verify(!find(view, "brightnessSlider").enabled)
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      compare(focused().objectName, "morePanels", "from the audio link straight to More")
    }

    // Every status is read in full on screen, in every language and at a
    // larger font: beside the slider at the default font, on its own line
    // under the slider when it no longer fits there. Where it goes depends
    // on strings, font and width only, never on the state.
    function test_brightnessStatusLanguages() {
      var control = find(view, "brightnessControl")
      var slider = find(view, "brightnessSlider")
      var status = find(view, "brightnessStatus")
      var cases = [["", false, 60], ["failed", false, 60], ["unconfirmed", false, 60], ["", true, 100]]
      for (var lang of ["en", "es", "ja"]) {
        for (var w of [1536, 1280]) {
          for (var scale of [1, 1.4]) {
            var label = lang + " " + w + " " + scale
            catalogs.lang = lang
            Style.fontScale = scale
            fit(w, Math.round(w * 9 / 16))
            if (scale === 1) verify(!control.stacked, label + ": beside the slider at the default font")
            var height = control.height
            var stacked = control.stacked
            for (var c of cases) {
              bright.outcome = c[0]; bright.pending = c[1]; bright.desired = c[1] ? c[2] : -1
              wait(0)
              var said = c[1] ? status.text + ", " + testStrings.t("controlCenter.applying") : status.text
              compare(slider.Accessible.description, said, label + ": the slider describes the full status")
              verify(!status.truncated, label + ": " + status.text + " is cut")
              compare(control.height, height, label + ": the row's height does not follow the state")
              compare(control.stacked, stacked, label)
              var s = status.mapToItem(control, 0, 0), k = slider.mapToItem(control, 0, 0)
              verify(s.x >= 0 && s.x + status.width <= control.width + 0.5, label + ": the status stays in the row")
              if (stacked) verify(s.y >= k.y + slider.height, label + ": under the slider")
              else verify(s.x >= k.x + slider.width, label + ": after the slider")
            }
            checkHorizontal(label)
          }
        }
      }
      bright.outcome = ""; bright.pending = false; bright.desired = -1
    }

    function test_brightnessFocusAndPointer() {
      var slider = find(view, "brightnessSlider")
      view.keyboardShown = true
      slider.forceActiveFocus()
      verify(find(slider, "sliderFocusRing").visible, "visible keyboard focus")
      view.keyboardShown = false
      verify(!find(slider, "sliderFocusRing").visible, "no ring in mouse mode")
      mouseClick(slider, slider.width * 0.8, slider.height / 2)
      compare(bright.asked.length, 1)
      verify(Math.abs(bright.asked[0] - 80) <= 1, "a click asks for that level: " + bright.asked[0])
      bright.available = false
      bright.percent = -1
      mouseClick(slider, slider.width * 0.3, slider.height / 2)
      compare(bright.asked.length, 1, "disabled: the pointer asks nothing")
    }

    function test_brightnessRefreshedOnOpen() {
      compare(bright.refreshes, 1, "init's reset is an open")
      view.reset()
      compare(bright.refreshes, 2)
    }

    // The pending level shows on the slider; the observed one once settled.
    function test_brightnessShownValue() {
      var slider = find(view, "brightnessSlider")
      var status = find(view, "brightnessStatus")
      compare(slider.value, 0.6)
      compare(status.text, "60 %")
      bright.desired = 30
      bright.pending = true
      compare(slider.value, 0.3, "the level asked for while pending")
      compare(status.text, "30 %", "no pending mark: the label follows the handle")
      compare(slider.Accessible.description, "30 %, applying", "pending is still announced")
      bright.desired = -1
      bright.pending = false
      bright.outcome = "unconfirmed"
      compare(slider.value, 0.6, "the observed level once settled")
      compare(status.text, "Not confirmed")
      bright.outcome = "failed"
      compare(status.text, "Did not change")
    }

    // Text on a lit or selected control (a service tile that is on, a radio
    // that is on, the active power profile) sits on the accent fill: at
    // least 4.5:1 there in every palette, and the fill stays the theme's
    // accent. Hover, keyboard focus and a press keep the accent fill; the
    // inner focus ring stays visible (3:1, a non-text indicator). Selection
    // is not shown by colour alone: lit controls are "checked" for
    // assistive technology and the active profile's name is DemiBold.
    function test_litControlTextContrast() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../unit/fixtures/omarchy-themes.json"), false)
      xhr.send()
      var themes = JSON.parse(xhr.responseText)
      var saved = [Commons.Color.foreground, Commons.Color.background, Commons.Color.muted, Commons.Color.urgent,
                   Commons.Color.accent, Commons.Color.bar.text, Commons.Color.bar.background, Commons.Color.popups.background]
      function over(top, under) {
        return Qt.rgba(under.r + (top.r - under.r) * top.a, under.g + (top.g - under.g) * top.a,
                       under.b + (top.b - under.b) * top.a, 1)
      }
      nightlight.enabled = true
      wait(0)
      var radioLabel = find(tile("bluetooth"), "radioLabel")
      // The radio's fill is its toggle: the rectangle that holds its texts.
      var lit = [tile("nightlight"), radioLabel.parent.parent, find(view, "profile:performance")]
      compare(lit[0].status, "on"); verify(lit[1].lit); verify(lit[2].lit)
      var texts = [find(lit[0], "tileLabel"), find(lit[0], "tileStatus"), radioLabel,
                   find(tile("bluetooth"), "radioStatus"), find(lit[2], "profileLabel")]
      verify(lit[0].Accessible.checked && lit[2].Accessible.checked, "checked for assistive technology")
      compare(texts[4].font.weight, Font.DemiBold)
      var low = 99, worst = ""
      for (var n in themes) {
        var t = themes[n]
        Commons.Color.foreground = t.foreground; Commons.Color.bar.text = t.foreground
        Commons.Color.background = t.background; Commons.Color.bar.background = t.background
        Commons.Color.popups.background = t.background
        Commons.Color.muted = t.muted; Commons.Color.urgent = t.urgent; Commons.Color.accent = t.accent
        wait(0)
        var fill = over(Commons.Color.accent, over(Commons.Color.popups.background, Commons.Color.background))
        function measure(tag) {
          for (var c of lit) verify(Qt.colorEqual(c.color, testTheme.accent), n + " " + tag + ": " + c.objectName + " keeps the accent fill")
          for (var x of texts) {
            var ratio = Palette.contrast(x.color, fill)
            if (ratio < low) { low = ratio; worst = n + " " + x.objectName }
            verify(ratio >= 4.5, n + " " + tag + ": " + x.objectName + " " + ratio.toFixed(2) + ":1")
          }
        }
        measure("rest")
        mouseMove(lit[0], lit[0].width / 2, lit[0].height / 2); wait(0); measure("hover")
        mousePress(lit[2], lit[2].width / 2, lit[2].height / 2); wait(0); measure("pressed")
        mouseRelease(view, 1, 1); mouseMove(view, 1, 1)
        view.keyboardShown = true
        lit[0].forceActiveFocus(); wait(0)
        var ring = find(lit[0], "litFocusRing")
        verify(ring.visible, n + ": focus ring on the lit tile")
        verify(Palette.contrast(ring.border.color, fill) >= 3, n + ": ring " + Palette.contrast(ring.border.color, fill).toFixed(2) + ":1")
        measure("focused")
        view.keyboardShown = false
        view.forceActiveFocus()
      }
      for (var lang of ["en", "es", "ja"]) for (var w of [1536, 1280]) for (var scale of [1, 1.4]) {
        catalogs.lang = lang; Style.fontScale = scale; fit(w, Math.round(w * 9 / 16))
        for (var x2 of texts) compare(x2.color.toString(), testTheme.accentForeground.toString(), lang + " " + w + " " + scale + ": " + x2.objectName)
      }
      catalogs.lang = "en"; Style.fontScale = 1; fit(1536, 864)
      compare(power.asked.length, 0, "no profile was asked for")
      console.log("lit control text: lowest", low.toFixed(2) + ":1 (" + worst + ") across", Object.keys(themes).length, "palettes")
      Commons.Color.foreground = saved[0]; Commons.Color.background = saved[1]; Commons.Color.muted = saved[2]; Commons.Color.urgent = saved[3]
      Commons.Color.accent = saved[4]; Commons.Color.bar.text = saved[5]; Commons.Color.bar.background = saved[6]; Commons.Color.popups.background = saved[7]
    }

    // The name of the profile being switched to, while its segment is
    // pressed, is on the pressed fill: at least 4.5:1 there in every
    // palette (and on the plain and hovered segment once released). The
    // press asks for nothing (it is released outside), and focus rings and
    // the selection logic are untouched.
    function test_pressedSwitchingSegmentContrast() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../unit/fixtures/omarchy-themes.json"), false)
      xhr.send()
      var themes = JSON.parse(xhr.responseText)
      var saved = [Commons.Color.foreground, Commons.Color.background, Commons.Color.muted, Commons.Color.urgent,
                   Commons.Color.bar.text, Commons.Color.bar.background, Commons.Color.popups.background]
      function over(top, under) {
        return Qt.rgba(under.r + (top.r - under.r) * top.a, under.g + (top.g - under.g) * top.a,
                       under.b + (top.b - under.b) * top.a, 1)
      }
      var pc = find(view, "profilesControl")
      var segment = find(view, "profile:balanced")
      var name = find(segment, "profileLabel")
      pc.request = { target: "balanced" }
      wait(0)
      verify(segment.asked, "balanced is being switched to")
      var low = 99, worst = ""
      for (var n in themes) {
        var t = themes[n]
        Commons.Color.foreground = t.foreground; Commons.Color.bar.text = t.foreground
        Commons.Color.background = t.background; Commons.Color.bar.background = t.background
        Commons.Color.popups.background = t.background
        Commons.Color.muted = t.muted; Commons.Color.urgent = t.urgent
        wait(0)
        var card = over(Commons.Color.popups.background, Commons.Color.background)
        mousePress(segment, segment.width / 2, segment.height / 2)
        verify(Qt.colorEqual(segment.color, testTheme.pressed), n + ": the pressed fill is shown")
        var ratio = Palette.contrast(name.color, over(testTheme.pressed, card))
        if (ratio < low) { low = ratio; worst = n }
        verify(ratio >= 4.5, n + ": pressed, switching: " + ratio.toFixed(2) + ":1")
        mouseRelease(view, 1, 1)
        wait(0)
        verify(!segment.lit, n + ": released outside: nothing selected")
        for (var g of [over(testTheme.surface, card), over(testTheme.hover, card)])
          verify(Palette.contrast(name.color, g) >= 4.5, n + ": switching, released: " + Palette.contrast(name.color, g).toFixed(2))
      }
      compare(power.asked.length, 0, "no profile was asked for")
      console.log("pressed switching segment: lowest", low.toFixed(2) + ":1 (" + worst + ") across", Object.keys(themes).length, "palettes")
      Commons.Color.foreground = saved[0]; Commons.Color.background = saved[1]; Commons.Color.muted = saved[2]; Commons.Color.urgent = saved[3]
      Commons.Color.bar.text = saved[4]; Commons.Color.bar.background = saved[5]; Commons.Color.popups.background = saved[6]
    }

    // A radio whose provider goes away (no adapter) drops the network
    // name's one-line limit: its "unavailable" is read in full (ja at 1280
    // needs two lines), with no runtime error. A long network name is still
    // kept to one line. Nothing is asked of the radio.
    function test_radioWithoutProvider() {
      var radio = tile("wifi")
      var status = find(radio, "radioStatus")
      catalogs.lang = "ja"
      fit(1280, 720)
      wifi.connected = true
      wifi.detail = "A wireless network with a really quite remarkably long name"
      wait(0)
      compare(status.text, wifi.detail)
      compare(status.maximumLineCount, 1, "a network name keeps to one line")
      compare(status.lineCount, 1)
      verify(status.truncated, "a long network name may still be shortened")
      view.wifi = null
      wait(0)
      compare(radio.status, "unavailable")
      compare(status.maximumLineCount, 3, "no provider: a status may wrap again")
      compare(status.text, testStrings.t("controlCenter.unavailable"))
      verify(!status.truncated, "unavailable is read in full: " + status.lineCount + " lines")
      view.wifi = wifi
      wifi.detail = "A network with a rather long name"
      catalogs.lang = "en"
      wait(0)
      compare(wifi.asked, [], "nothing was asked of the radio")
    }

    // Every status a control can show is read in full on screen, in every
    // language, at the default and a large font and at both reference
    // outputs. A row keeps its height whatever the state, so a result
    // never moves the panel under the pointer. (A Wi-Fi network's own name
    // is not a status; it may still be shortened.)
    function test_statusesShownInFull() {
      var audioLabel = find(view, "audioStatus")
      var audio = audioLabel
      while (audio && audio.failed === undefined) audio = audio.parent
      var pc = find(view, "profilesControl")
      var service = tile("nightlight"), radio = tile("wifi")
      var cut = []
      function check(item, what) {
        if (item.truncated || item.implicitWidth > item.width + 0.5 && item.lineCount <= 1 && item.elide !== Text.ElideNone)
          cut.push(what + " " + JSON.stringify(item.text))
      }
      for (var lang of ["en", "es", "ja"]) {
        for (var w of [1536, 1280]) {
          for (var scale of [1, 1.4]) {
            catalogs.lang = lang
            Style.fontScale = scale
            fit(w, Math.round(w * 9 / 16))
            var label = lang + " " + w + " x" + scale
            var heights = { audio: audio.height, service: service.height, radio: radio.height, profiles: pc.height }
            // Audio: level, muted, failed, no output.
            var audioStates = [function() {}, function() { sink.audio.muted = true },
                               function() { audio.failed = true }, function() { sink.ready = false }]
            for (var a of audioStates) {
              a(); wait(0)
              check(audioLabel, label + " audio")
              compare(audio.height, heights.audio, label + " audio height follows the state")
              sink.audio.muted = false; audio.failed = false; sink.ready = true
            }
            // A service tile: off, waiting, failed, on, unavailable.
            var serviceStates = [function() {}, function() { service.pending = true }, function() { service.failed = true },
                                 function() { nightlight.enabled = true }]
            for (var t of serviceStates) {
              t(); wait(0)
              check(find(service, "tileStatus"), label + " tile " + service.status)
              compare(service.height, heights.service, label + " tile height follows the state")
              service.pending = null; service.failed = false; nightlight.enabled = false
            }
            // A radio tile: on, off, switching, failed, blocked, unavailable.
            var radioStates = [function() { wifi.connected = false }, function() { wifi.on = false; wifi.connected = false },
                               function() { radio.pending = true }, function() { radio.failed = true },
                               function() { wifi.blocked = true }, function() { wifi.available = false }]
            for (var r of radioStates) {
              r(); wait(0)
              check(find(radio, "radioStatus"), label + " radio " + radio.status)
              compare(radio.height, heights.radio, label + " radio height follows the state")
              radio.pending = null; radio.failed = false
              wifi.available = true; wifi.blocked = false; wifi.on = true; wifi.connected = true
            }
            // Power profile notes.
            for (var o of ["failed", "unsaved", "superseded"]) {
              pc.outcome = o; wait(0)
              check(find(view, "profileStatus"), label + " profile " + o)
              compare(pc.height, heights.profiles, label + " profile height follows the note")
            }
            pc.outcome = ""
            power.degraded = "lap-detected"; wait(0)
            check(find(view, "profileStatus"), label + " profile degraded")
            power.degraded = ""
            wait(0)
          }
        }
      }
      catalogs.lang = "en"; Style.fontScale = 1
      compare(cut, [], "statuses cut on screen")
    }

    // Secondary text that carries meaning (group headings, a tile's or
    // radio's state, the profile note and a profile being switched to, the
    // output device, the empty panels note) reaches 4.5:1 on what it is
    // drawn on in every palette, stays weaker than ordinary text, and keeps
    // one colour in every language and font scale. Disabled controls keep
    // the muted colour (test_levelTextContrast).
    function test_secondaryTextContrast() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../unit/fixtures/omarchy-themes.json"), false)
      xhr.send()
      var themes = JSON.parse(xhr.responseText)
      var saved = [Commons.Color.foreground, Commons.Color.background, Commons.Color.muted, Commons.Color.urgent,
                   Commons.Color.bar.text, Commons.Color.bar.background, Commons.Color.popups.background]
      function over(top, under) {
        return Qt.rgba(under.r + (top.r - under.r) * top.a, under.g + (top.g - under.g) * top.a,
                       under.b + (top.b - under.b) * top.a, 1)
      }
      var pc = find(view, "profilesControl")
      wifi.on = false; wifi.connected = false
      pc.outcome = "unsaved"
      pc.request = { target: "balanced" }
      wait(0)
      compare(tile("wifi").status, "off")
      compare(tile("nightlight").status, "off")
      var headings = findAll(view, "groupTitle")
      verify(headings.length >= 4, "group headings: " + headings.length)
      var onCard = headings.concat([find(view, "audioDevice"), find(view, "profileStatus"), find(view, "noPanels")])
      var onTile = [find(tile("nightlight"), "tileStatus"), find(tile("wifi"), "radioStatus"), find(find(view, "profile:balanced"), "profileLabel")]
      var low = 99, worst = ""
      for (var name in themes) {
        var t = themes[name]
        Commons.Color.foreground = t.foreground; Commons.Color.bar.text = t.foreground
        Commons.Color.background = t.background; Commons.Color.bar.background = t.background
        Commons.Color.popups.background = t.background
        Commons.Color.muted = t.muted; Commons.Color.urgent = t.urgent
        wait(0)
        var card = over(Commons.Color.popups.background, Commons.Color.background)
        var groups = [[onCard, [card]], [onTile, [over(testTheme.surface, card), over(testTheme.hover, card)]]]
        for (var g of groups) {
          for (var label of g[0]) {
            verify(!Qt.colorEqual(label.color, testTheme.foreground), name + ": " + label.objectName + " stays secondary")
            for (var ground of g[1]) {
              var ratio = Palette.contrast(label.color, ground)
              if (ratio < low) { low = ratio; worst = name + " " + label.objectName }
              verify(ratio >= 4.5, name + ": " + label.objectName + " " + JSON.stringify(label.text) + " " + ratio.toFixed(2) + ":1")
              verify(ratio < Palette.contrast(testTheme.foreground, ground), name + ": " + label.objectName + " weaker than ordinary text")
            }
          }
        }
        for (var lang of ["en", "es", "ja"]) {
          for (var scale of [1, 1.4]) {
            catalogs.lang = lang; Style.fontScale = scale
            wait(0)
            for (var all of onCard.concat(onTile))
              compare(all.color.toString(), onCard[0].color.toString(), name + " " + lang + " " + scale + ": " + all.objectName)
          }
        }
        catalogs.lang = "en"; Style.fontScale = 1
      }
      console.log("secondary text: lowest contrast", low.toFixed(2) + ":1 (" + worst + ") across", Object.keys(themes).length, "palettes")
      Commons.Color.foreground = saved[0]; Commons.Color.background = saved[1]; Commons.Color.muted = saved[2]; Commons.Color.urgent = saved[3]
      Commons.Color.bar.text = saved[4]; Commons.Color.bar.background = saved[5]; Commons.Color.popups.background = saved[6]
    }

    // Failure text is ordinary-size text: at least 4.5:1 on what it is drawn
    // on (the card; a tile, plain or hovered, on the card) in every installed
    // Omarchy theme and the active custom one (tests/unit/fixtures), in
    // every language and font scale. It keeps its own colour (distinct from
    // ordinary text) and says what happened in words, not only by colour.
    function test_failureTextContrast() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../unit/fixtures/omarchy-themes.json"), false)
      xhr.send()
      var themes = JSON.parse(xhr.responseText)
      var saved = [Commons.Color.foreground, Commons.Color.background, Commons.Color.muted, Commons.Color.urgent,
                   Commons.Color.bar.text, Commons.Color.bar.background, Commons.Color.popups.background]
      var audio = find(view, "audioStatus")
      while (audio && audio.failed === undefined) audio = audio.parent
      var pc = find(view, "profilesControl")
      function over(top, under) {
        return Qt.rgba(under.r + (top.r - under.r) * top.a, under.g + (top.g - under.g) * top.a,
                       under.b + (top.b - under.b) * top.a, 1)
      }
      var labels = [["brightnessStatus", false], ["audioStatus", false], ["profileStatus", false]]
      var failedTile = tile("nightlight"), failedRadio = tile("wifi")
      var low = 99, worst = ""
      for (var name in themes) {
        var t = themes[name]
        Commons.Color.foreground = t.foreground; Commons.Color.bar.text = t.foreground
        Commons.Color.background = t.background; Commons.Color.bar.background = t.background
        Commons.Color.popups.background = t.background
        Commons.Color.muted = t.muted; Commons.Color.urgent = t.urgent
        bright.outcome = "failed"; audio.failed = true; pc.outcome = "failed"
        failedTile.failed = true; failedRadio.failed = true
        wait(0)
        var card = over(Commons.Color.popups.background, Commons.Color.background)
        var surface = over(testTheme.surface, card)
        var hover = over(testTheme.hover, card)
        var checks = [[find(view, "brightnessStatus"), [card]], [find(view, "audioStatus"), [card]],
                      [find(view, "profileStatus"), [card]],
                      [find(failedTile, "tileStatus"), [surface, hover]], [find(failedRadio, "radioStatus"), [surface, hover]]]
        for (var c of checks) {
          var label = c[0]
          verify(label.text.length > 0, name + ": " + label.objectName + " says what failed in words")
          verify(!Qt.colorEqual(label.color, testTheme.foreground), name + ": " + label.objectName + " stands apart")
          for (var g of c[1]) {
            var ratio = Palette.contrast(label.color, g)
            if (ratio < low) { low = ratio; worst = name + " " + label.objectName }
            verify(ratio >= 4.5, name + ": " + label.objectName + " " + ratio.toFixed(2) + ":1")
          }
        }
        for (var lang of ["en", "es", "ja"]) {
          for (var scale of [1, 1.4]) {
            catalogs.lang = lang; Style.fontScale = scale
            wait(0)
            for (var k of checks) verify(Qt.colorEqual(k[0].color, checks[0][0].color), name + " " + lang + " " + scale + ": one failure colour")
          }
        }
        catalogs.lang = "en"; Style.fontScale = 1
        bright.outcome = ""; audio.failed = false; pc.outcome = ""
        failedTile.failed = false; failedRadio.failed = false
      }
      console.log("failure text: lowest contrast", low.toFixed(2) + ":1 (" + worst + ") across", Object.keys(themes).length, "palettes")
      Commons.Color.foreground = saved[0]; Commons.Color.background = saved[1]; Commons.Color.muted = saved[2]; Commons.Color.urgent = saved[3]
      Commons.Color.bar.text = saved[4]; Commons.Color.bar.background = saved[5]; Commons.Color.popups.background = saved[6]
    }

    // The audio and brightness levels are ordinary text on the card
    // (Commons.Color.popups.background): at least 4.5:1 in dark and light
    // themes, the same colour in both rows, in every language and font
    // scale. Failure keeps the danger colour and unavailable the muted one,
    // each distinct from the ordinary level. Theme rows: foreground,
    // background, muted, urgent (the active theme first, then installed
    // Omarchy themes).
    function test_levelTextContrast() {
      var themes = [
        ["active (dark)", "#D6E6CE", "#0A120F", "#3C544A", "#8D221C"],
        ["tokyo-night", "#a9b1d6", "#1a1b26", "#414868", "#f7768e"],
        ["matte-black", "#bebebe", "#121212", "#333333", "#D35F5F"],
        ["catppuccin-latte", "#4c4f69", "#eff1f5", "#acb0be", "#d20f39"],
        ["rose-pine", "#575279", "#faf4ed", "#cecacd", "#b4637a"],
        ["flexoki-light", "#100F0F", "#FFFCF0", "#B7B5AC", "#D14D41"]
      ]
      var saved = [Commons.Color.foreground, Commons.Color.background, Commons.Color.muted, Commons.Color.urgent, Commons.Color.bar.text, Commons.Color.bar.background, Commons.Color.popups.background]
      var audioStatus = find(view, "audioStatus")
      var brightStatus = find(view, "brightnessStatus")
      var audio = audioStatus
      while (audio && audio.failed === undefined) audio = audio.parent
      // The card over what lies under it, as the compositor blends them.
      function card() {
        var c = Commons.Color.popups.background, u = Commons.Color.background
        return Qt.rgba(u.r + (c.r - u.r) * c.a, u.g + (c.g - u.g) * c.a, u.b + (c.b - u.b) * c.a, 1)
      }
      for (var t of themes) {
        Commons.Color.foreground = t[1]; Commons.Color.bar.text = t[1]
        Commons.Color.background = t[2]; Commons.Color.bar.background = t[2]; Commons.Color.popups.background = t[2]
        Commons.Color.muted = t[3]; Commons.Color.urgent = t[4]
        wait(0)
        var ratio = Palette.contrast(brightStatus.color, card())
        console.log("level text contrast", t[0], ratio.toFixed(2) + ":1",
                    "(muted was " + Palette.contrast(Commons.Color.muted, card()).toFixed(2) + ":1)")
        verify(ratio >= 4.5, t[0] + ": " + ratio.toFixed(2) + ":1")
        compare(audioStatus.color, brightStatus.color, t[0] + ": audio and brightness alike")
        for (var lang of ["en", "es", "ja"]) {
          for (var scale of [1, 1.4]) {
            catalogs.lang = lang; Style.fontScale = scale
            wait(0)
            compare(brightStatus.color, testTheme.foreground, t[0] + " " + lang + " " + scale)
            compare(audioStatus.color, testTheme.foreground, t[0] + " " + lang + " " + scale)
            verify(!brightStatus.truncated && !audioStatus.truncated, t[0] + " " + lang + " " + scale + ": cut")
          }
        }
        catalogs.lang = "en"; Style.fontScale = 1
        // Failure and unavailable keep their own colours.
        bright.outcome = "failed"; audio.failed = true
        compare(brightStatus.color.toString(), testTheme.dangerText.toString()); compare(audioStatus.color.toString(), testTheme.dangerText.toString())
        verify(!Qt.colorEqual(testTheme.dangerText, testTheme.foreground), t[0] + ": failure stands apart")
        bright.outcome = ""; audio.failed = false
        bright.available = false; bright.percent = -1; sink.ready = false
        compare(brightStatus.color, testTheme.muted); compare(audioStatus.color, testTheme.muted)
        verify(!Qt.colorEqual(testTheme.muted, testTheme.foreground), t[0] + ": unavailable stands apart")
        bright.available = true; bright.percent = 60; sink.ready = true
        // Pending keeps the ordinary colour; it is announced, not tinted.
        bright.desired = 30; bright.pending = true
        compare(brightStatus.color, testTheme.foreground)
        compare(find(view, "brightnessSlider").Accessible.description, "30 %, applying")
        bright.desired = -1; bright.pending = false
      }
      Commons.Color.foreground = saved[0]; Commons.Color.background = saved[1]; Commons.Color.muted = saved[2]; Commons.Color.urgent = saved[3]
      Commons.Color.bar.text = saved[4]; Commons.Color.bar.background = saved[5]; Commons.Color.popups.background = saved[6]
    }

    // Escape still closes from inside the selector.
    function test_profileEscape() {
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Tab)
      compare(focused().objectName, "profile:performance")
      keyClick(Qt.Key_Escape)
      compare(closeSpy.count, 1)
      compare(power.asked.length, 0)
    }

    function test_profileUnavailableKeepsItsPlace() {
      var h = view.implicitHeight
      power.available = false
      wait(50)
      var list = view.controls()
      for (var i = 0; i < list.length; i++) verify(String(list[i].objectName).indexOf("profile:") !== 0, "no segment reachable")
      verify(find(view, "profileStatus").text.length > 0, "the status says why")
      verify(view.implicitHeight <= h, "no growth when unavailable")
    }

    // The slider keeps Left/Right/Home/End for its value; Up/Down leave it.
    function test_sliderContract() {
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Right)
      var slider = focused()
      compare(slider.Accessible.role, Accessible.Slider)
      keyClick(Qt.Key_Right)
      compare(sink.audio.volume, 0.55)
      verify(slider.activeFocus, "Right changed the value, focus stayed")
      keyClick(Qt.Key_Home)
      compare(sink.audio.volume, 0)
      keyClick(Qt.Key_Down)
      compare(focused().objectName, "moreAudio", "Down leaves the slider")
      keyClick(Qt.Key_Up)
      keyClick(Qt.Key_Up)
      compare(focused().objectName, "profile:power-saver", "Up leaves the group, into System's last row")
      sink.audio.volume = 0.5
    }

    // Toggling and opening a full panel are separate targets.
    function test_toggleAndLinkAreSeparate() {
      keyClick(Qt.Key_Right)
      keyClick(Qt.Key_Space)
      compare(panelSpy.count, 1)
      compare(panelSpy.signalArguments[0][0], "omarchy.network")
      compare(wifi.asked.length, 0, "the link does not toggle")
      keyClick(Qt.Key_Left)
      keyClick(Qt.Key_Space)
      compare(wifi.asked, [false], "the toggle asks; nothing else")
      compare(panelSpy.count, 1)
    }

    // Focus is visible on lit and unlit tiles.
    function test_visibleFocus() {
      view.keyboardShown = true
      var t = tile("nightlight")
      t.forceActiveFocus()
      verify(!Qt.colorEqual(t.border.color, t.color), "unlit: accent edge")
      nightlight.enabled = true
      var ring = find(t, "litFocusRing")
      verify(ring.visible, "lit: inset ring")
      verify(!Qt.colorEqual(ring.border.color, t.color))
      var w = tile("wifi")
      w.controls()[0].forceActiveFocus()
      verify(find(w, "litFocusRing").visible)
    }

    // -------------------------------------------------------------- pages

    function test_panelsPage() {
      var main = view.implicitHeight
      var flick = find(view, "pageScroll")
      keyClick(Qt.Key_Backtab)
      compare(focused().objectName, "morePanels")
      keyClick(Qt.Key_Return)
      compare(view.page, "panels")
      compare(view.implicitHeight, main, "same footprint")
      compare(host.height, Math.min(main, host.height), "the panel is not resized")
      verify(focused() !== null && focused().Accessible.name === "Back", "focus on Back")
      verify(!find(view, "dashboard").visible)
      var list = view.controls()
      compare(list.length, 1 + scene.realLinks.length, "only this page's controls")
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      compare(panelSpy.signalArguments[0][0], "omarchy.bluetooth")
      keyClick(Qt.Key_Escape)
      compare(view.page, "main", "Escape goes back")
      compare(focused().objectName, "morePanels", "to the button that opened it")
      compare(closeSpy.count, 0)
      keyClick(Qt.Key_Escape)
      compare(closeSpy.count, 1)
    }

    function test_manyPanelsScroll() {
      var many = []
      for (var i = 0; i < 30; i++) many.push({ id: "p" + i, name: "Panel with a fairly long name " + i })
      view.links = many
      var main = view.implicitHeight
      view.showPanels()
      wait(50)
      compare(view.implicitHeight, main)
      var flick = find(view, "pageScroll")
      verify(flick.contentHeight > flick.height)
      verify(find(view, "scrollIndicator").visible)
      for (var j = 0; j < 30; j++) keyClick(Qt.Key_Down)
      var last = focused()
      compare(last.Accessible.name, "Open Panel with a fairly long name 29")
      var p = last.mapToItem(flick, 0, 0)
      verify(p.y + last.height <= flick.height + 0.5, "the last link is scrolled into view")
    }

    function test_noPanels() {
      view.links = []
      var main = view.implicitHeight
      verify(find(view, "morePanels").visible, "the More group stays; the footprint does not change")
      view.showPanels()
      compare(view.controls().length, 1, "only Back")
      compare(view.implicitHeight, main)
    }

    // The content is kept between opens: every open starts on the main page.
    function test_resetOnOpen() {
      view.showPanels()
      find(view, "pageScroll").contentY = 40
      view.reset()
      compare(view.page, "main")
      compare(find(view, "pageScroll").contentY, 0)
      verify(tile("wifi").controls()[0].activeFocus)
      verify(!view.keyboardShown)
    }

    // ------------------------------------------------------ state sync

    function test_servicesAndRadiosStayLive() {
      compare(tile("nightlight").status, "off")
      nightlight.enabled = true
      compare(tile("nightlight").status, "on", "changed elsewhere")
      bt.on = false
      compare(tile("bluetooth").status, "off")
      wifi.available = false
      compare(tile("wifi").status, "unavailable")
      var list = view.controls()
      for (var i = 0; i < list.length; i++)
        verify(!(list[i].Accessible.role === Accessible.CheckBox && list[i].Accessible.name === "Wi-Fi"), "an unavailable toggle takes no focus")
      compare(tile("wifi").controls().length, 1, "its panel link stays reachable")
      verify(tile("wifi").visible, "and stays on screen")
    }
  }
}
