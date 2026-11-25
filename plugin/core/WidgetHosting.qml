import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons as Commons
import "Facades.js" as Facades

// Lets the bar host Omarchy bar widgets (stock ones and user plugins such as
// a cloned audio widget) through their public contract: each widget gets an
// Omarchy PluginBarApi facade, never this bar or the shell. Also the
// one-panel-at-a-time coordinator and the panel lookups the shell calls on its
// active bar (summonBarWidget, hideBarWidget, isBarWidgetOpen, panelWidgetIdAt).
Scope {
  id: root

  // The bar root: colors, sizes, fontFamily, position, layout, shell.
  required property var bar

  // Scoped shell API injected into the bar. Each widget gets a narrower
  // entry facade from it, the same one the stock bar gives replacement bars.
  readonly property var shell: bar.shell

  // Hosted ids the numbered panel hotkeys skip (Settings.unnumberedIds).
  property var unnumbered: []

  property var facades: ({})
  property var hostedItems: []
  property var clickTargets: []
  property var activePopout: null
  // Which plugin registered a popout or click target, so one widget's facade
  // never hands it another widget's objects.
  readonly property var owners: new Map()
  readonly property var foreignPopoutMarker: ({ foreign: true })

  function facadeFor(moduleName) {
    var id = String(moduleName || "")
    if (!id) return null
    if (root.facades[id]) return root.facades[id]

    var entryShell = root.shell && typeof root.shell.pluginShellForBarEntry === "function"
      ? root.shell.pluginShellForBarEntry(id, id) : null

    // Owned by JavaScript and created outside this bar's context (as the stock
    // bar parents its facades to null), so a facade outlives a hot reload's
    // teardown for as long as a widget still holds it; retire() leaves it inert.
    var api = Facades.create(Qt.resolvedUrl("HostedBarApi.qml"), {
      pluginId: id,
      moduleName: id,
      shell: entryShell,
      _barSizeFor: function(screenName) { return root.bar.barSizeFor(screenName) },
      _showTooltip: function(target, text) { root.bar.showTooltip(target, text) },
      _hideTooltip: function(target) { root.bar.hideTooltip(target) },
      _registerClickTarget: function(target) { root.registerClickTarget(id, target) },
      _unregisterClickTarget: function(target) { root.unregisterClickTarget(id, target) },
      _requestPopout: function(owner) { root.requestPopout(id, owner) },
      _releasePopout: function(owner) { root.releasePopout(id, owner) },
      _switchPanelFrom: function(owner, direction) { return root.switchPanelFrom(owner, direction) },
      _notePopoutCard: function(card) { },
      _popoutCardFor: function(owner) { return null },
      _targetBelongsToWindow: function(target, window) { return root.targetBelongsToWindow(target, window) },
      _moduleWidgets: function(requested) { return String(requested || "") === id ? root.itemsFor(id) : [] },
      _run: function(command) { if (command) Commons.Util.execDetached(String(command)) },
      _setCenterHoverRevealSuppressed: function(value) { }
    })
    if (!api) return null

    api.foreground = Qt.binding(function() { return root.bar.theme.foreground })
    api.barForeground = Qt.binding(function() { return root.bar.theme.foreground })
    api.background = Qt.binding(function() { return root.bar.theme.surface })
    api.urgent = Qt.binding(function() { return root.bar.theme.danger })
    api.fontFamily = Qt.binding(function() { return root.bar.fontFamily })
    api.position = Qt.binding(function() { return root.bar.position })
    api.vertical = false
    api.barSize = Qt.binding(function() { return root.bar.theme.m.islandHeight - 2 * root.bar.theme.m.buttonInset })
    api.layoutConfig = Qt.binding(function() { return root.bar.publicLayout })
    root.sync(api)

    var next = ({})
    for (var key in root.facades) next[key] = root.facades[key]
    next[id] = api
    root.facades = next
    return api
  }

  readonly property var callbackNames: [
    "_barSizeFor", "_showTooltip", "_hideTooltip", "_registerClickTarget", "_unregisterClickTarget",
    "_requestPopout", "_releasePopout", "_switchPanelFrom", "_notePopoutCard", "_popoutCardFor",
    "_targetBelongsToWindow", "_moduleWidgets", "_run", "_setCenterHoverRevealSuppressed"
  ]

  // Freezes a facade at its last values (assigning drops the bindings to this
  // bar) and cuts its callbacks, so widgets torn down after this hosting read
  // plain values and their late calls do nothing.
  function retire(api) {
    var bound = ["foreground", "barForeground", "background", "urgent", "fontFamily", "position", "barSize", "layoutConfig"]
    for (var i = 0; i < bound.length; i++) api[bound[i]] = api[bound[i]]
    for (var j = 0; j < root.callbackNames.length; j++) api[root.callbackNames[j]] = null
    api.activePopout = null
    api.clickTargets = []
  }

  Component.onDestruction: {
    for (var id in root.facades) root.retire(root.facades[id])
  }

  // Whether a facade lists every bar click target, as the stock bar's own
  // panels see them: this bar's (the calendar) and Omarchy's first-party
  // widgets, which the stock bar hands itself rather than a scoped API. A
  // KeyboardPanel forwards a click on the bar strip only to its bar's
  // clickTargets, so a panel that sees only its own button needs a second
  // click to hand over to another widget. Third-party plugins stay scoped.
  function seesAllTargets(pluginId) {
    if (pluginId === root.bar.pluginId) return true
    var registry = root.bar.barWidgetRegistry
    var entry = registry && registry.widgets ? registry.widgets[pluginId] : null
    return !!entry && !!entry.metadata && entry.metadata.firstParty === true
  }

  function sync(api) {
    if (!api) return
    var popout = root.activePopout
    api.activePopout = popout && root.owners.get(popout) === api.pluginId ? popout : (popout ? root.foreignPopoutMarker : null)
    api.clickTargets = root.seesAllTargets(api.pluginId)
      ? root.clickTargets.slice()
      : root.clickTargets.filter(function(target) { return root.owners.get(target) === api.pluginId })
  }

  function syncAll() {
    for (var id in root.facades) root.sync(root.facades[id])
  }

  // ------------------------------------------------------------ popouts

  function requestPopout(pluginId, owner) {
    if (!owner) return
    var known = root.owners.get(owner)
    if (known && known !== pluginId) return
    root.owners.set(owner, pluginId)
    if (root.activePopout !== owner) {
      var previous = root.activePopout
      root.activePopout = owner
      if (previous) {
        if (typeof previous.closeForPopoutSwitch === "function") previous.closeForPopoutSwitch()
        else if (typeof previous.close === "function") previous.close()
      }
    }
    root.syncAll()
  }

  function releasePopout(pluginId, owner) {
    if (root.owners.get(owner) !== pluginId) return
    if (root.activePopout === owner) root.activePopout = null
    root.syncAll()
  }

  // ------------------------------------------------------- click targets

  function registerClickTarget(pluginId, target) {
    if (!target || root.clickTargets.indexOf(target) !== -1) return
    var known = root.owners.get(target)
    if (known && known !== pluginId) return
    root.owners.set(target, pluginId)
    root.clickTargets = root.clickTargets.concat([target])
    root.syncAll()
  }

  function unregisterClickTarget(pluginId, target) {
    if (root.owners.get(target) !== pluginId) return
    root.clickTargets = root.clickTargets.filter(function(item) { return item !== target })
    if (root.activePopout !== target) root.owners.delete(target)
    root.syncAll()
  }

  function targetBelongsToWindow(target, window) {
    return !!target && !!window && !!target.QsWindow && target.QsWindow.window === window
  }

  // ------------------------------------------------------- hosted items

  // Each surface reports the widgets it instantiated: { item, moduleName, screenName }.
  function registerItem(record) {
    if (!record || !record.item) return
    root.hostedItems = root.hostedItems.concat([record])
  }

  function unregisterItem(item) {
    root.hostedItems = root.hostedItems.filter(function(record) { return record.item !== item })
    if (root.activePopout && !root.hostedItems.some(function(record) { return record.item === root.activePopout })) {
      // A widget unloaded with its panel open (output unplugged, reload).
      var owner = root.owners.get(root.activePopout)
      if (owner && root.itemsFor(owner).length === 0) root.activePopout = null
    }
    root.syncAll()
  }

  function itemsFor(moduleName) {
    return root.hostedItems
      .filter(function(record) { return record.moduleName === moduleName })
      .map(function(record) { return record.item })
  }

  function isPanelItem(item) {
    return !!item && typeof item.open === "function" && typeof item.close === "function" && item.opened !== undefined
  }

  // The instance a hotkey means: the focused output's, else any open one, else the first.
  function panelItemFor(pluginId) {
    var id = String(pluginId || "")
    var focusedName = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    var candidates = root.hostedItems.filter(function(record) {
      return record.moduleName === id && root.isPanelItem(record.item)
    })
    for (var i = 0; i < candidates.length; i++) if (candidates[i].screenName === focusedName) return candidates[i].item
    for (var j = 0; j < candidates.length; j++) if (candidates[j].item.opened === true) return candidates[j].item
    return candidates.length > 0 ? candidates[0].item : null
  }

  function summon(pluginId) {
    var item = root.panelItemFor(pluginId)
    if (!item) return false
    item.open()
    return true
  }

  function hide(pluginId) {
    var item = root.panelItemFor(pluginId)
    if (!item) return false
    item.close()
    return true
  }

  function isOpen(pluginId) {
    var item = root.panelItemFor(pluginId)
    return !!item && item.opened === true
  }

  // The hosted island is this bar's only section of panels; it answers to
  // "right" so `omarchy-shell shell togglePanelAt right N` hotkeys keep working.
  function panelIdAt(section, index) {
    if (String(section || "") !== "right") return ""
    var seen = root.panelIds(true)
    var n = Math.round(Number(index)) - 1
    return n >= 0 && n < seen.length ? seen[n] : ""
  }

  // The shown hosted widgets that have a panel, in order, each once; `numbered`
  // leaves out the ones the numbered hotkeys skip.
  function panelIds(numbered) {
    var seen = []
    for (var i = 0; i < root.hostedItems.length; i++) {
      var record = root.hostedItems[i]
      if (!root.isPanelItem(record.item) || record.item.visible === false) continue
      if (numbered && root.unnumbered.indexOf(record.moduleName) !== -1) continue
      if (seen.indexOf(record.moduleName) === -1) seen.push(record.moduleName)
    }
    return seen
  }

  function switchPanelFrom(owner, direction) {
    var ownerRecord = null
    for (var i = 0; i < root.hostedItems.length; i++) if (root.hostedItems[i].item === owner) ownerRecord = root.hostedItems[i]
    if (!ownerRecord) return false
    var row = root.hostedItems.filter(function(record) {
      return record.screenName === ownerRecord.screenName && root.isPanelItem(record.item) && record.item.visible !== false
    })
    if (row.length < 2) return false
    var index = row.indexOf(ownerRecord)
    var next = row[(index + (direction < 0 ? -1 : 1) + row.length) % row.length]
    if (!next || next.item === owner) return false
    next.item.open()
    return true
  }
}
