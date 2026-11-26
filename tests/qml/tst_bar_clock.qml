import QtQuick
import QtTest
import qs.Commons as Commons
import "../../plugin/core/Identity.js" as Identity
import "../../plugin/logic/Calendar.js" as Calendar
import "../../plugin/logic/ClockFormat.mjs" as ClockFormat
import "../../plugin/logic/Settings.js" as Settings
import "../../plugin/theme"
import "../../plugin/widgets"

// Exercises the production clock orchestration helpers (`cycleClockFormatAction`,
// `toggleWeekStartAction`), reactive QML bindings, live ClockIsland +
// CalendarView propagation, timezone action, and `omarchy.clock` ShellIpc
// delegation. Bar.qml itself instantiates Wayland PanelWindow/WlrLayershell
// surfaces which only exist inside the quickshell binary, so this harness binds
// the exact same properties and production functions as Bar.qml.
Item {
  id: harness

  width: 640
  height: 480

  Theme { id: theme }

  QtObject {
    id: strings
    function t(key) { return key === "clock" ? "%1, %2" : key }
  }

  readonly property var fixtureTheme: theme
  readonly property var fixtureStrings: strings

  // Mirrors Bar.qml's exact clock properties, ShellIpc target, and production calls.
  component ClockBarHost: Item {
    id: host

    property var shell: null
    property var barConfig: ({})
    property int refreshCalls: 0

    readonly property var settings: Settings.read(barConfig, Identity.settingsKey)
    readonly property string localeTag: Calendar.resolveLocale(settings.locale, Commons.I18n.formatLocale)
    readonly property var clockConfig: ClockFormat.resolveClockConfig(barConfig, Identity.settingsKey)
    property string _localClockFormat: ""
    property var _localCustomClockFormats: null
    property string _localWeekStartDay: ""
    readonly property string clockFormat: _localClockFormat !== "" ? _localClockFormat : clockConfig.format
    readonly property var clockWeekStartDay: _localWeekStartDay !== "" ? _localWeekStartDay : clockConfig.weekStartDay
    readonly property var clockLocale: Qt.locale(localeTag)
    readonly property int effectiveWeekStart: ClockFormat.normalizedWeekStart(clockWeekStartDay, clockLocale.firstDayOfWeek)

    onBarConfigChanged: {
      _localClockFormat = ""
      _localCustomClockFormats = null
      _localWeekStartDay = ""
    }

    function cycleClockFormat() {
      return ClockFormat.cycleClockFormatAction(host, host.shell, host.clockConfig, Identity.settingsKey)
    }

    function toggleWeekStart() {
      return ClockFormat.toggleWeekStartAction(host, host.shell, host.clockConfig, Identity.settingsKey)
    }

    function openTimezoneSelector() {
      Commons.Util.execArgv(["omarchy-menu-timezone"])
    }

    function refreshClocks() {
      host.refreshCalls++
      clockIsland.refresh()
    }

    property alias clock: clockIsland
    property alias calendarA: calA
    property alias calendarB: calB
    property alias ipc: clockIpc

    ClockIsland {
      id: clockIsland
      theme: harness.fixtureTheme
      strings: harness.fixtureStrings
      timeFormat: host.clockFormat
      weekStartDay: host.clockWeekStartDay
      localeTag: host.localeTag
      onCycleFormatRequested: host.cycleClockFormat()
      onTimezoneRequested: host.openTimezoneSelector()
    }

    CalendarView {
      id: calA
      y: 60
      width: 308
      theme: harness.fixtureTheme
      strings: harness.fixtureStrings
      now: clockIsland.now
      localeTag: host.localeTag
      weekStartDay: host.clockWeekStartDay
    }

    CalendarView {
      id: calB
      x: 320
      y: 60
      width: 308
      theme: harness.fixtureTheme
      strings: harness.fixtureStrings
      now: clockIsland.now
      localeTag: "ja-JP"
      weekStartDay: host.clockWeekStartDay
    }

    Commons.ShellIpc {
      id: clockIpc
      target: "omarchy.clock"

      function refresh(): void { host.refreshClocks() }
      function cycleFormat(): void { host.cycleClockFormat() }
      function toggleWeekStart(): void { host.toggleWeekStart() }
    }
  }

  Component {
    id: barHostFactory
    ClockBarHost {}
  }

  TestCase {
    name: "BarClock"
    when: windowShown

    function makeStore(bar) {
      return {
        version: 1,
        bar: JSON.parse(JSON.stringify(bar)),
        idle: { lock: 300 }
      }
    }

    function makeShell(store, hostRef, opts) {
      var options = opts || {}
      var state = {
        inlineCalls: [],
        mutateCalls: 0,
        rejectInline: !!options.rejectInline,
        rejectMutate: !!options.rejectMutate,
        autoReload: options.autoReload !== false
      }
      return {
        state: state,
        updateEntryInline: function(id, entry) {
          state.inlineCalls.push({ id: id, entry: JSON.parse(JSON.stringify(entry)) })
          if (state.rejectInline) return false
          var stripped = String(id || "")
          var layout = store.bar && store.bar.layout ? store.bar.layout : {}
          var sections = ["left", "centerBegin", "center", "centerEnd", "right", "tray"]
          var dirty = false
          for (var s = 0; s < sections.length; s++) {
            var arr = layout[sections[s]] || []
            for (var i = 0; i < arr.length; i++) {
              if (arr[i] && typeof arr[i] === "object" && String(arr[i].id || "") === stripped) {
                var next = { id: stripped }
                for (var k in entry) if (k !== "id") next[k] = entry[k]
                if (JSON.stringify(arr[i]) !== JSON.stringify(next)) {
                  arr[i] = next
                  dirty = true
                }
              }
            }
          }
          if (!dirty) return false
          if (state.autoReload && hostRef.item) hostRef.item.barConfig = JSON.parse(JSON.stringify(store.bar))
          return true
        },
        mutateShellConfig: function(mutator) {
          state.mutateCalls++
          if (state.rejectMutate || typeof mutator !== "function") return false
          var scoped = { bar: JSON.parse(JSON.stringify(store.bar || {})) }
          mutator(scoped)
          if (scoped.bar && typeof scoped.bar === "object" && !Array.isArray(scoped.bar)) {
            store.bar = JSON.parse(JSON.stringify(scoped.bar))
          }
          if (state.autoReload && hostRef.item) hostRef.item.barConfig = JSON.parse(JSON.stringify(store.bar))
          return true
        }
      }
    }

    function createHost(barConfig, shell) {
      return createTemporaryObject(barHostFactory, harness, {
        barConfig: JSON.parse(JSON.stringify(barConfig)),
        shell: shell
      })
    }

    function test_cycleClockFormatUpdatesNativeEntryAndPreservesUnrelatedKeys() {
      var store = makeStore({
        id: "floating-islands",
        islands: { density: "comfortable" },
        layout: {
          center: [{ id: "omarchy.clock", format: "dddd HH:mm", formatAlt: "yyyy 'W'ww", weekStartDay: "monday", birthYear: 1990 }],
          right: [{ id: "omarchy.power" }]
        }
      })
      var ref = { item: null }
      var shell = makeShell(store, ref)
      var host = createHost(store.bar, shell)
      ref.item = host

      compare(host.clockFormat, "dddd HH:mm")
      var outcome = host.cycleClockFormat()
      verify(outcome.accepted)
      compare(outcome.status, "persisted")
      compare(outcome.method, "updateEntryInline")
      compare(outcome.durableConfirmed, false)
      compare(host.clockFormat, "dddd h:mm AP")
      compare(host.clock.timeFormat, "dddd h:mm AP")
      compare(shell.state.inlineCalls.length, 1)
      compare(shell.state.mutateCalls, 0)
      compare(store.bar.layout.center[0].format, "dddd h:mm AP")
      compare(store.bar.layout.center[0].formatAlt, "yyyy 'W'ww")
      compare(store.bar.layout.center[0].weekStartDay, "monday")
      compare(store.bar.layout.center[0].birthYear, 1990)
      compare(store.bar.islands.density, "comfortable")
      compare(store.bar.islands.customClockFormats, undefined)
      compare(store.idle.lock, 300)

      // Simulated restart: fresh host instantiated from persisted store.
      var restarted = createHost(store.bar, shell)
      compare(restarted.clockFormat, "dddd h:mm AP")
      compare(restarted.clockConfig.formatAlt, "yyyy 'W'ww")
    }

    function test_legacyMigrationSingleWriteIncludingWhenNextEqualsStoredNative() {
      var store = makeStore({
        id: "floating-islands",
        islands: { density: "compact", timeFormat: "yyyy-MM-dd HH:mm" },
        layout: {
          center: [{ id: "omarchy.clock", format: "dddd HH:mm", weekStartDay: "sunday" }]
        }
      })
      var ref = { item: null }
      var shell = makeShell(store, ref)
      var host = createHost(store.bar, shell)
      ref.item = host

      compare(host.clockFormat, "yyyy-MM-dd HH:mm")
      var outcome = host.cycleClockFormat()
      verify(outcome.accepted)
      compare(outcome.method, "mutateShellConfig")
      compare(host.clockFormat, "dddd HH:mm")
      compare(shell.state.inlineCalls.length, 0)
      compare(shell.state.mutateCalls, 1)
      compare(store.bar.layout.center[0].format, "dddd HH:mm")
      compare(store.bar.layout.center[0].weekStartDay, "sunday")
      compare(store.bar.islands.timeFormat, undefined)
      compare(store.bar.islands.density, "compact")
    }

    function test_stringFormNativeEntryUpgradesCoherently() {
      var store = makeStore({
        id: "floating-islands",
        layout: { center: ["omarchy.clock"] }
      })
      var ref = { item: null }
      var shell = makeShell(store, ref)
      var host = createHost(store.bar, shell)
      ref.item = host

      compare(host.clockFormat, "HH:mm")
      host.cycleClockFormat()
      compare(host.clockFormat, "h:mm AP")
      compare(shell.state.inlineCalls.length, 0)
      compare(shell.state.mutateCalls, 1)
      compare(store.bar.layout.center[0].id, "omarchy.clock")
      compare(store.bar.layout.center[0].format, "h:mm AP")
    }

    function test_missingNativeEntryFallsBackSafely() {
      var store = makeStore({
        id: "floating-islands",
        islands: { density: "compact" },
        layout: { right: ["omarchy.power"] }
      })
      var ref = { item: null }
      var shell = makeShell(store, ref)
      var host = createHost(store.bar, shell)
      ref.item = host

      host.cycleClockFormat()
      compare(host.clockFormat, "h:mm AP")
      compare(shell.state.inlineCalls.length, 0)
      compare(shell.state.mutateCalls, 1)
      compare(store.bar.islands.timeFormat, "h:mm AP")
      compare(store.bar.layout.center, undefined)
    }

    function test_rejectedAndUnavailablePersistenceRevertsOptimisticState() {
      var store = makeStore({
        id: "floating-islands",
        layout: { center: [{ id: "omarchy.clock", format: "HH:mm" }] }
      })
      var ref = { item: null }
      var rejectedInline = makeShell(store, ref, { rejectInline: true })
      var host = createHost(store.bar, rejectedInline)
      ref.item = host

      var out = host.cycleClockFormat()
      verify(!out.accepted)
      compare(out.status, "rejected")
      compare(host.clockFormat, "HH:mm")
      compare(rejectedInline.state.inlineCalls.length, 1)
      compare(rejectedInline.state.mutateCalls, 0)

      host.shell = null
      var unavail = host.cycleClockFormat()
      verify(!unavail.accepted)
      compare(unavail.status, "unavailable")
      compare(host.clockFormat, "HH:mm")

      host.shell = rejectedInline
      var initialWeekStart = host.effectiveWeekStart
      var wsOut = host.toggleWeekStart()
      verify(!wsOut.accepted)
      compare(host.effectiveWeekStart, initialWeekStart)
    }

    function test_rapidConsecutiveCyclingAndReloadReconciliation() {
      var store = makeStore({
        id: "floating-islands",
        layout: { center: [{ id: "omarchy.clock", format: "HH:mm" }] }
      })
      var ref = { item: null }
      var shell = makeShell(store, ref, { autoReload: false })
      var host = createHost(store.bar, shell)
      ref.item = host

      host.cycleClockFormat()
      compare(host.clockFormat, "h:mm AP")
      host.cycleClockFormat()
      compare(host.clockFormat, "ddd d MMM HH:mm")
      compare(shell.state.inlineCalls.length, 2)
      compare(store.bar.layout.center[0].format, "ddd d MMM HH:mm")

      var external = JSON.parse(JSON.stringify(store.bar))
      external.layout.center[0].format = "yyyy-MM-dd HH:mm"
      host.barConfig = external
      compare(host.clockFormat, "yyyy-MM-dd HH:mm")
    }

    function test_customFormatRetentionAcrossCyclingAndRestart() {
      var store = makeStore({
        id: "floating-islands",
        islands: { density: "compact" },
        layout: {
          center: [{ id: "omarchy.clock", format: "HH:mm 'UTC'", formatAlt: "yyyy 'W'ww" }]
        }
      })
      var ref = { item: null }
      var shell = makeShell(store, ref)
      var host = createHost(store.bar, shell)
      ref.item = host

      host.cycleClockFormat()
      compare(host.clockFormat, "dddd HH:mm")
      compare(shell.state.inlineCalls.length, 0)
      compare(shell.state.mutateCalls, 1)
      compare(store.bar.layout.center[0].formatAlt, "yyyy 'W'ww")
      compare(store.bar.islands.customClockFormats.length, 1)
      compare(store.bar.islands.customClockFormats[0], "HH:mm 'UTC'")

      var restarted = createHost(store.bar, shell)
      ref.item = restarted
      verify(restarted.clockConfig.ring.indexOf("HH:mm 'UTC'") !== -1)
      restarted.cycleClockFormat()
      compare(restarted.clockFormat, "dddd h:mm AP")
      compare(shell.state.inlineCalls.length, 1)
      compare(shell.state.mutateCalls, 1)
      compare(store.bar.islands.customClockFormats.length, 1)
    }

    function test_weekStartPropagationTimezoneAndIpcDelegation() {
      var store = makeStore({
        id: "floating-islands",
        islands: { locale: "en" },
        layout: {
          center: [{ id: "omarchy.clock", format: "dddd HH:mm", formatAlt: "yyyy 'W'ww" }]
        }
      })
      var ref = { item: null }
      var shell = makeShell(store, ref)
      var host = createHost(store.bar, shell)
      ref.item = host

      // Locale fallback: en-GB -> Monday (1), ja-JP -> Sunday (0).
      compare(host.calendarA.weekStart, 1)
      compare(host.calendarB.weekStart, 0)

      // IPC toggleWeekStart switches to Sunday and propagates to BOTH calendars.
      host.ipc.toggleWeekStart()
      compare(host.effectiveWeekStart, 0)
      compare(store.bar.layout.center[0].weekStartDay, "sunday")
      compare(store.bar.layout.center[0].format, "dddd HH:mm")
      compare(store.bar.layout.center[0].formatAlt, "yyyy 'W'ww")
      compare(host.calendarA.weekStart, 0)
      compare(host.calendarB.weekStart, 0)

      // Toggling again switches to Monday and propagates to BOTH calendars.
      host.ipc.toggleWeekStart()
      compare(host.effectiveWeekStart, 1)
      compare(store.bar.layout.center[0].weekStartDay, "monday")
      compare(host.calendarA.weekStart, 1)
      compare(host.calendarB.weekStart, 1)

      // IPC cycleFormat delegates to production cycleClockFormatAction.
      host.ipc.cycleFormat()
      compare(host.clockFormat, "dddd h:mm AP")
      compare(store.bar.layout.center[0].weekStartDay, "monday")

      // IPC refresh refreshes the clock.
      host.ipc.refresh()
      compare(host.refreshCalls, 1)

      // Middle-click timezone action invokes omarchy-menu-timezone via fixed argv.
      Commons.Util.ran = []
      host.openTimezoneSelector()
      compare(Commons.Util.ran.length, 1)
      compare(Commons.Util.ran[0], "omarchy-menu-timezone")
    }
  }
}
