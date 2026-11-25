.pragma library

// The Control Center's quick toggles and what each reads and sets. State comes
// only from Omarchy's services, through the narrow first-party proxies a bar is
// given (shell.firstPartyServiceFor); nothing here keeps a copy of it.

var TILES = [
  { key: "nightlight", service: "omarchy.nightlight" },
  { key: "stayAwake", service: "omarchy.idle" },
  { key: "doNotDisturb", service: "omarchy.notifications" }
]

function isOn(key, proxy) {
  if (!proxy) return false
  if (key === "nightlight") return proxy.enabled === true
  if (key === "stayAwake") return proxy.stayAwake === true
  if (key === "doNotDisturb") return proxy.doNotDisturb === true
  return false
}

// Asks the service for a state; the tile shows it only once the service reports
// it. False when there is nothing to ask.
function request(key, proxy, on) {
  if (!proxy) return false
  if (key === "nightlight" && typeof proxy.setNightlight === "function") proxy.setNightlight(!!on)
  // The idle service's setter is the inverse: idle enabled means not staying awake.
  else if (key === "stayAwake" && typeof proxy.setIdleEnabled === "function") proxy.setIdleEnabled(!on)
  else if (key === "doNotDisturb" && typeof proxy.setDoNotDisturb === "function") proxy.setDoNotDisturb(!!on)
  else return false
  return true
}

// What a tile shows: "unavailable", "pending" (asked, not yet reported),
// "failed" (asked, the service did not change), "on" or "off".
function status(available, on, pending, failed) {
  if (!available) return "unavailable"
  if (pending) return "pending"
  if (failed) return "failed"
  return on ? "on" : "off"
}

// `omarchy-shell floating-islands toggleControlCenter`.
function ipcToggle(enabled, surface) {
  if (!enabled) return "disabled"
  if (!surface) return "no-surface"
  return surface.toggleControlCenter()
}

// The hosted widgets with a panel, for the links to their full panels: the
// registry's display name, or the id.
function links(ids, registry) {
  var widgets = registry && registry.widgets ? registry.widgets : {}
  var out = []
  for (var i = 0; i < ids.length; i++) {
    var meta = widgets[ids[i]] && widgets[ids[i]].metadata ? widgets[ids[i]].metadata : {}
    out.push({ id: ids[i], name: typeof meta.displayName === "string" && meta.displayName ? meta.displayName : ids[i] })
  }
  return out
}

// ------------------------------------------------------------------ audio
// The default output's controls. `sink` is the Pipewire node the adapter
// follows (adapters/AudioOutput.qml); everything is read from it.

var VOLUME_STEP = 0.05

// A sink whose audio can be read and set; a node not yet bound reads as not ready.
function outputAvailable(sink) {
  return !!sink && !!sink.audio && sink.ready !== false
}

// The slider runs 0-100 %, as Omarchy's own panel sets it; a louder level set
// elsewhere is shown as it is and pinned to the end of the slider.
function clampVolume(value) {
  var v = Number(value)
  return isFinite(v) ? Math.max(0, Math.min(1, v)) : 0
}

function percent(value) {
  var v = Number(value)
  return isFinite(v) ? Math.round(Math.max(0, v) * 100) : 0
}

function outputName(sink) {
  if (!sink) return ""
  var names = [sink.description, sink.nickname, sink.name]
  for (var i = 0; i < names.length; i++) if (typeof names[i] === "string" && names[i]) return names[i]
  return ""
}

// The hosted widget for the full audio panel: the first whose registry
// category is "Audio" (Omarchy's own, or a user's clone of it).
function audioPanelId(ids, registry) {
  var widgets = registry && registry.widgets ? registry.widgets : {}
  for (var i = 0; i < ids.length; i++) {
    var meta = widgets[ids[i]] && widgets[ids[i]].metadata ? widgets[ids[i]].metadata : {}
    if (meta.category === "Audio") return ids[i]
  }
  return ""
}

// ----------------------------------------------------------- connectivity
// The Wi-Fi and Bluetooth tiles. adapters/Connectivity.qml reads Quickshell's
// Networking and Bluetooth services into the plain values below; these
// functions only decide what a tile shows.

// Wi-Fi from NetworkManager. `managed`: Networking.backend is NetworkManager.
// `devices`: the Wi-Fi devices only ({ connected, network }), so a wired link
// can never make the Wi-Fi tile read connected. `enabled` is NetworkManager's
// WirelessEnabled; `hardwareEnabled` false means a hardware switch (rfkill
// hard block) holds the radio off, which nothing here can change. `rf` is
// the wlan rfkill state (rfkillState), or null when it is not known.
function wifi(managed, devices, enabled, hardwareEnabled, rf) {
  var list = managed && devices ? devices.filter(function(d) { return !!d }) : []
  var out = { available: list.length > 0, blocked: false, on: false, connected: false, detail: "", count: list.length }
  if (!managed) return out
  if (!out.available) return absent(out, rf, hardwareEnabled === false)
  out.blocked = hardwareEnabled === false || !!(rf && rf.hard)
  out.on = enabled === true && !out.blocked
  if (!out.on) return out
  for (var i = 0; i < list.length; i++) {
    if (list[i].connected !== true) continue
    out.connected = true
    if (!out.detail && typeof list[i].network === "string") out.detail = list[i].network
  }
  return out
}

// No device or adapter is listed. Switching a radio off can take its device
// away: NetworkManager's radio off and omarchy-bluetooth-power off both
// soft-block every rfkill switch of the type, and a platform switch (on many
// laptops) cuts power to the module. A blocked rfkill switch that is still
// present means the hardware is there and can be switched back on; no switch
// at all, or an unblocked one with nothing listed, is unavailable.
function absent(out, rf, hardwareOff) {
  if (!rf || !rf.present || !(rf.soft || rf.hard || hardwareOff)) return out
  out.available = true
  out.blocked = rf.hard || hardwareOff
  return out
}
// The name of the connected network in a Wi-Fi device's list, or "". The
// device can be connected while its network is missing from the list
// (Omarchy's network panel notes this for OWE transition networks), so the
// device's own `connected` decides, not this.
function connectedNetwork(networks) {
  var list = networks || []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].connected === true && typeof list[i].name === "string") return list[i].name
  }
  return ""
}

// Bluetooth from BlueZ, over every adapter ({ enabled }): on when any
// adapter is powered, as omarchy-bluetooth-power reads it, since its rfkill
// block switches every radio at once. `rf` is the bluetooth rfkill state
// (rfkillState), or null when it is not known.
function bluetooth(adapters, rf) {
  var list = adapters ? adapters.filter(function(a) { return !!a }) : []
  var out = { available: list.length > 0, blocked: false, on: false, connected: false, detail: "", count: list.length }
  if (!out.available) return absent(out, rf, false)
  for (var i = 0; i < list.length; i++) {
    if (list[i].enabled === true) out.on = true
  }
  out.blocked = !out.on && !!(rf && rf.hard)
  return out
}

// `rfkill --json --output TYPE,SOFT,HARD` read into { present, soft, hard }
// for one type ("bluetooth" or "wlan"): any switch present, any soft-blocked,
// any hard-blocked. null when the output cannot be read.
function rfkillState(text, type) {
  var parsed
  try { parsed = JSON.parse(text) } catch (e) { return null }
  var list = parsed && Array.isArray(parsed.rfkilldevices) ? parsed.rfkilldevices : null
  if (!list) return null
  var out = { present: false, soft: false, hard: false }
  for (var i = 0; i < list.length; i++) {
    var d = list[i]
    if (!d || d.type !== type) continue
    out.present = true
    if (d.soft === "blocked") out.soft = true
    if (d.hard === "blocked") out.hard = true
  }
  return out
}

var RFKILL_READ = ["rfkill", "--json", "--output", "TYPE,SOFT,HARD"]

// What a connectivity tile shows: "unavailable", "blocked" (hardware switch),
// "pending", "failed", "connected", "on" or "off".
function radioStatus(state, pending, failed) {
  if (!state || !state.available) return "unavailable"
  if (state.blocked) return "blocked"
  if (pending) return "pending"
  if (failed) return "failed"
  if (state.connected) return "connected"
  return state.on ? "on" : "off"
}

// The command that asks for a radio state. Wi-Fi: nmcli, whose exit status
// is NetworkManager's answer (Quickshell 0.3.2 sets Networking.wifiEnabled
// locally before NetworkManager replies and keeps it if the write is
// refused). Bluetooth: Omarchy's own helper, as its Bluetooth panel uses,
// which moves the persistent rfkill block for every adapter.
function radioCommand(kind, on) {
  if (kind === "wifi") return ["nmcli", "radio", "wifi", on ? "on" : "off"]
  if (kind === "bluetooth") return ["omarchy-bluetooth-power", on ? "on" : "off"]
  return []
}

// The full panel for a tile: Omarchy's own widget, when the bar hosts it.
var PANELS = { wifi: "omarchy.network", bluetooth: "omarchy.bluetooth" }

function panelId(kind, ids) {
  var id = PANELS[kind]
  return id && ids && ids.indexOf(id) !== -1 ? id : ""
}

// -------------------------------------------------------------- dashboard
// Sizes and keyboard moves for the grouped view. Pure, so the rules are
// tested without QML.

// The card's width: a quarter of the output, kept between 340 and 420 px
// (scaled). The panel then caps it at the space the output has.
function cardWidth(screenWidth, scale) {
  var s = Number(scale) > 0 ? Number(scale) : 1
  var w = Number(screenWidth) > 0 ? Number(screenWidth) * 0.25 : 0
  return Math.round(Math.max(340 * s, Math.min(420 * s, w)))
}

// How many columns of at least `minWidth` fit in `width` with `gap` between
// them, between 1 and `most`.
function columns(width, minWidth, gap, most) {
  var w = Number(width) || 0
  var n = Math.floor((w + gap) / (minWidth + gap))
  return Math.max(1, Math.min(most, n))
}

// `items` in rows of `perRow`, keeping each item's visual row, then without
// the ones `keep` rejects (an unavailable control keeps its place on screen
// but takes no focus). Empty rows are dropped.
function rows(items, perRow, keep) {
  var out = []
  for (var i = 0; i < items.length; i += perRow) {
    var row = items.slice(i, i + perRow).filter(function(item) { return keep(item) })
    if (row.length) out.push(row)
  }
  return out
}

// The next focus position in a page shaped as groups of rows
// ([[rowLength, ...], ...]) from `at` ({ group, row, col }) for `move`:
//   left/right  the previous/next control in the group, across its rows;
//   up/down     the row above/below at the nearest column, continuing into
//               the neighbouring group at the group's edge;
//   tab/backtab the next/previous group (wrapping), at `memory[group]`
//               (the position last focused there) or its first control.
// Returns `at` itself when there is nowhere to go.
function navigate(shape, at, move, memory) {
  var groups = []
  for (var g = 0; g < shape.length; g++) if (shape[g] && shape[g].length) groups.push(g)
  if (!groups.length) return null
  var first = function(gi) { return { group: gi, row: 0, col: 0 } }
  if (!at || !shape[at.group] || !shape[at.group][at.row]) return first(groups[0])
  var rowsOf = shape[at.group]
  var flat = function(gi) { var n = []; for (var r = 0; r < shape[gi].length; r++) for (var c = 0; c < shape[gi][r]; c++) n.push({ group: gi, row: r, col: c }); return n }
  var nearest = function(gi, r, col) { return { group: gi, row: r, col: Math.min(col, shape[gi][r] - 1) } }
  var gi = groups.indexOf(at.group)
  if (move === "left" || move === "right") {
    var list = flat(at.group)
    var i = 0
    for (var k = 0; k < list.length; k++) if (list[k].row === at.row && list[k].col === at.col) i = k
    var j = i + (move === "right" ? 1 : -1)
    return j >= 0 && j < list.length ? list[j] : at
  }
  if (move === "down") {
    if (at.row + 1 < rowsOf.length) return nearest(at.group, at.row + 1, at.col)
    return gi + 1 < groups.length ? nearest(groups[gi + 1], 0, at.col) : at
  }
  if (move === "up") {
    if (at.row > 0) return nearest(at.group, at.row - 1, at.col)
    if (gi === 0) return at
    var prev = groups[gi - 1]
    return nearest(prev, shape[prev].length - 1, at.col)
  }
  if (move === "tab" || move === "backtab") {
    var target = groups[(gi + (move === "tab" ? 1 : groups.length - 1)) % groups.length]
    var remembered = memory && memory[target]
    if (remembered && shape[target][remembered.row] && remembered.col < shape[target][remembered.row])
      return { group: target, row: remembered.row, col: remembered.col }
    return first(target)
  }
  return at
}

// --------------------------------------------------------- power profile
// The power profile control. adapters/PowerProfileAdapter.qml reads the daemon
// (power-profiles-daemon) and Quickshell's PowerProfiles signal; these
// functions only parse, validate and decide what a request came to.

// Every profile power-profiles-daemon defines, in display order. Which of
// them a machine has comes from the daemon, never from this list.
var PROFILES = ["power-saver", "balanced", "performance"]

// Quickshell's PowerProfile enum (PowerSaver, Balanced, Performance) to the
// daemon's names.
function profileName(value) {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 && value < PROFILES.length ? PROFILES[value] : ""
}

// The daemon's properties, read with one read-only call that never starts
// it (busctl --auto-start=no, see PROFILE_READ). Returns
// { available, profiles, active, degraded }; unavailable when the call
// failed, the output is not the daemon's, or it lists no known profile.
function parseProfiles(text) {
  var none = { available: false, profiles: [], active: "", degraded: "" }
  var parsed
  try { parsed = JSON.parse(text) } catch (e) { return none }
  var props = parsed && Array.isArray(parsed.data) ? parsed.data[0] : null
  if (!props || typeof props !== "object") return none
  var listed = props.Profiles && Array.isArray(props.Profiles.data) ? props.Profiles.data : []
  var names = []
  for (var i = 0; i < listed.length; i++) {
    var name = listed[i] && listed[i].Profile ? listed[i].Profile.data : ""
    if (PROFILES.indexOf(name) !== -1 && names.indexOf(name) === -1) names.push(name)
  }
  names.sort(function(a, b) { return PROFILES.indexOf(a) - PROFILES.indexOf(b) })
  if (!names.length) return none
  var active = props.ActiveProfile ? String(props.ActiveProfile.data || "") : ""
  var degraded = props.PerformanceDegraded ? String(props.PerformanceDegraded.data || "") : ""
  return { available: true, profiles: names, active: names.indexOf(active) !== -1 ? active : "", degraded: degraded }
}

var PROFILE_READ = ["busctl", "--system", "--json=short", "--auto-start=no", "call",
  "net.hadess.PowerProfiles", "/net/hadess/PowerProfiles",
  "org.freedesktop.DBus.Properties", "GetAll", "s", "net.hadess.PowerProfiles"]

// The command that asks Omarchy for `profile` on power source `source`
// ("ac" or "battery"): its own helper, which also remembers the choice for
// that source. [] when either is not one the helper accepts or the profile
// is not one `available` lists.
function profileCommand(source, profile, available) {
  if (source !== "ac" && source !== "battery") return []
  if (PROFILES.indexOf(profile) === -1) return []
  if (!available || available.indexOf(profile) === -1) return []
  return ["omarchy-powerprofiles-set", source, profile]
}

// What a request has come to. `req`: { target, source, exited, code }.
// `observed`: the active profile now; `source`: the power source now.
// `graceOver`: the short wait after the command exited has passed;
// `timedOut`: the overall limit has passed.
//   "superseded"  the power source changed: Omarchy applies the other
//                 source's profile, so this request no longer decides it;
//   "pending"     still waiting;
//   "done"        observed, and the helper exited 0, which it does only
//                 after remembering the choice;
//   "unsaved"     observed, but the helper exited non-zero: the profile is
//                 active, whether Omarchy remembered it is not known;
//   "failed"      not observed by the end of the wait.
// The observed state alone never proves the preference was saved, and the
// exit status alone never proves the profile is active.
function profileOutcome(req, observed, source, graceOver, timedOut) {
  if (!req) return "pending"
  if (source !== req.source) return "superseded"
  if (!req.exited) return timedOut ? "failed" : "pending"
  if (observed === req.target) return req.code === 0 ? "done" : "unsaved"
  return graceOver || timedOut ? "failed" : "pending"
}

// ------------------------------------------------------------- brightness
// The built-in display's backlight. adapters/BrightnessAdapter.qml reads
// and watches the device and runs Omarchy's helper; these functions only
// validate, convert and decide what a request came to.

// Outputs whose brightness Omarchy drives through the backlight (its
// omarchy-brightness-display and BrightnessKeys use the same prefixes).
// The name also goes on a command line, so only plain characters pass.
function backlightOutput(name) {
  return typeof name === "string" && /^(eDP|LVDS|DSI)-[A-Za-z0-9-]{1,32}$/.test(name)
}

// The device omarchy-hw-display printed: the one the helper writes for an
// internal output. "" unless it is a plain sysfs name.
function backlightDevice(text) {
  var name = String(text || "").trim()
  return /^[A-Za-z0-9_.:-]{1,64}$/.test(name) && name !== "." && name !== ".." ? name : ""
}

// A sysfs reading: a non-negative integer, else -1.
function backlightValue(text) {
  var t = String(text || "").trim()
  return /^[0-9]{1,10}$/.test(t) ? Number(t) : -1
}

// Raw backlight to percent the way Omarchy shows it (round(100 * raw / max)).
// -1 when either value is unusable.
function brightnessPercent(raw, max) {
  if (!(max > 0) || !(raw >= 0)) return -1
  return Math.max(0, Math.min(100, Math.round(100 * raw / max)))
}

// A requested percent: a finite number rounded to 1..100 (never 0, which
// would blank the panel), or -1.
function clampBrightness(value) {
  var v = Number(value)
  if (typeof value === "boolean" || value === null || value === "" || !isFinite(v)) return -1
  return Math.max(1, Math.min(100, Math.round(v)))
}

// The write: Omarchy's helper for that output, no OSD, an integer percent.
// [] unless the output is a backlight one and percent an integer 1..100.
function brightnessCommand(output, percent) {
  if (!backlightOutput(output)) return []
  if (typeof percent !== "number" || !Number.isInteger(percent) || percent < 1 || percent > 100) return []
  return ["omarchy-brightness-display", "--no-osd", "--monitor", output, percent + "%"]
}

// How far the observed percent may sit from the one asked for and still
// count: brightnessctl and the driver round the raw value.
var BRIGHTNESS_TOLERANCE = 1

// What a write has come to. `req`: { target, exited, code }; `observed`:
// the percent read now (-1 unknown); `graceOver`: the wait after the
// helper exited has passed.
//   "pending"      still waiting;
//   "done"         the observed level is the target (within tolerance),
//                  whatever the helper's exit status;
//   "failed"       not observed, and the helper failed, could not start or
//                  was stopped;
//   "unconfirmed"  not observed although the helper exited 0. It exits 0
//                  without writing when another brightness command holds
//                  its lock, and with --no-osd even when brightnessctl
//                  failed; or another change won the race.
// Only the observed level proves a change.
function brightnessOutcome(req, observed, graceOver) {
  if (!req || !req.exited) return "pending"
  if (observed >= 0 && Math.abs(observed - req.target) <= BRIGHTNESS_TOLERANCE) return "done"
  if (!graceOver) return "pending"
  return req.code === 0 ? "unconfirmed" : "failed"
}
