.pragma library

// This bar's settings live beside the stock bar's under shell.json `bar`:
//   { "bar": { "id": "<this plugin>", "islands": { "density": "compact", ... } } }
// The shell hands them over as barConfig and reloads them live. Everything is
// validated here; unknown or malformed values fall back to the defaults.

var DEFAULTS = {
  density: "compact",
  tier: "auto",
  timeFormat: "HH:mm",
  showTitle: true,
  hostWidgets: true,
  hosted: null,
  extraHosted: [],
  trialInstance: "",
  locale: "auto",
  showMedia: true,
  mediaEqualizer: "animated",
  launcherIcon: "omarchy",
  titleIcon: "app",
  controlCenter: false
}

var LOCALES = ["auto", "en", "es", "ja"]
var EQUALIZER = ["animated", "static"]
// The Omarchy logo from its icon font, or a generic application grid.
var LAUNCHER_ICONS = ["omarchy", "grid"]
// The application's own icon, or the design's monochrome symbol for its kind.
var TITLE_ICONS = ["app", "symbol"]

var DENSITIES = ["compact", "comfortable"]
var TIERS = ["auto", "full", "compact", "minimal"]
var ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/
var MAX_HOSTED = 24

// Widgets this bar draws itself, so they are never hosted a second time.
var NATIVE_IDS = ["omarchy.menu", "omarchy.workspaces", "omarchy.clock", "omarchy.active-window", "omarchy.spacer", "omarchy.media"]

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function read(barConfig, key) {
  var raw = isPlainObject(barConfig) && isPlainObject(barConfig[key]) ? barConfig[key] : {}
  var out = {}
  out.density = DENSITIES.indexOf(raw.density) !== -1 ? raw.density : DEFAULTS.density
  out.tier = TIERS.indexOf(raw.tier) !== -1 ? raw.tier : DEFAULTS.tier
  out.timeFormat = typeof raw.timeFormat === "string" && raw.timeFormat.trim().length > 0 && !/[\u0000-\u001f\u007f]/.test(raw.timeFormat)
    ? raw.timeFormat : DEFAULTS.timeFormat
  out.showTitle = raw.showTitle !== false
  out.hostWidgets = raw.hostWidgets !== false
  out.hosted = Array.isArray(raw.hosted) ? sanitizeIds(raw.hosted) : null
  out.extraHosted = Array.isArray(raw.extraHosted) ? sanitizeIds(raw.extraHosted) : []
  out.locale = LOCALES.indexOf(raw.locale) !== -1 ? raw.locale : DEFAULTS.locale
  out.showMedia = raw.showMedia !== false
  out.mediaEqualizer = EQUALIZER.indexOf(raw.mediaEqualizer) !== -1 ? raw.mediaEqualizer : DEFAULTS.mediaEqualizer
  out.launcherIcon = LAUNCHER_ICONS.indexOf(raw.launcherIcon) !== -1 ? raw.launcherIcon : DEFAULTS.launcherIcon
  out.titleIcon = TITLE_ICONS.indexOf(raw.titleIcon) !== -1 ? raw.titleIcon : DEFAULTS.titleIcon
  // Off unless asked for, while the Control Center is being built.
  out.controlCenter = raw.controlCenter === true
  out.trialInstance = typeof raw.trialInstance === "string" && /^[A-Za-z0-9_.-]{1,160}$/.test(raw.trialInstance)
    ? raw.trialInstance : ""
  return out
}

function sanitizeIds(list) {
  var out = []
  for (var i = 0; i < list.length && out.length < MAX_HOSTED; i++) {
    var id = typeof list[i] === "string" ? list[i] : (isPlainObject(list[i]) ? list[i].id : "")
    if (typeof id === "string" && ID_PATTERN.test(id) && out.indexOf(id) === -1) out.push(id)
  }
  return out
}

function entryId(entry) {
  if (typeof entry === "string") return entry
  return isPlainObject(entry) && entry.id !== undefined && entry.id !== null ? String(entry.id) : ""
}

// The entry's own settings: every key but the id, as the stock bar passes them.
function entrySettings(entry) {
  var copy = {}
  if (!isPlainObject(entry)) return copy
  for (var key in entry) if (key !== "id") copy[key] = entry[key]
  return copy
}

function findEntry(layout, id) {
  var sections = ["left", "centerBegin", "center", "centerEnd", "right", "tray"]
  for (var i = 0; i < sections.length; i++) {
    var list = isPlainObject(layout) && Array.isArray(layout[sections[i]]) ? layout[sections[i]] : []
    for (var j = 0; j < list.length; j++) if (entryId(list[j]) === id) return list[j]
  }
  return null
}

// The widgets the right-hand island hosts: the stock layout's right section by
// default, or the ids in `hosted`; then any `extraHosted` ids not already
// there (the stock World clock or weather from the centre, say), marked
// `extra` so the numbered panel hotkeys still count only the others. A hosted
// widget must still be placed somewhere in bar.layout, because the shell only
// grants a widget its scoped API while its entry is configured. Custom
// command/qml modules are skipped.
function hostedEntries(barConfig, settings) {
  if (!settings || !settings.hostWidgets) return []
  var layout = isPlainObject(barConfig) && isPlainObject(barConfig.layout) ? barConfig.layout : {}
  var ids = settings.hosted
  if (!ids) ids = sanitizeIds(Array.isArray(layout.right) ? layout.right : [])
  var extra = Array.isArray(settings.extraHosted) ? settings.extraHosted : []
  var out = []
  var seen = []
  function add(id, isExtra) {
    if (seen.indexOf(id) !== -1 || out.length >= MAX_HOSTED) return
    seen.push(id)
    if (NATIVE_IDS.indexOf(id) !== -1) return
    var entry = findEntry(layout, id)
    if (!entry) return
    if (isPlainObject(entry) && (entry.type === "command" || entry.type === "qml")) return
    var record = { id: id, settings: entrySettings(entry) }
    if (isExtra) record.extra = true
    out.push(record)
  }
  for (var i = 0; i < ids.length; i++) add(ids[i], false)
  for (var j = 0; j < extra.length; j++) add(extra[j], true)
  return out
}

// The hosted ids the numbered panel hotkeys skip (see hostedEntries).
function unnumberedIds(entries) {
  return entries.filter(function(entry) { return entry.extra === true }).map(function(entry) { return entry.id })
}
