.pragma library

// Hosted widgets keep their identity across configuration changes. Every
// shell.json change hands the bar a new layout, so the island's slots are a
// ListModel brought to the new order with the fewest moves, inserts and
// removals rather than rebuilt: a widget that stays configured keeps its
// instance, its open panel and its IPC handler.

// Entries may arrive as a JS array or as a QML sequence, which is array-like
// but not an Array.
function isList(value) {
  return !!value && typeof value === "object" && typeof value.length === "number"
}

// The ids in order, each once.
function uniqueIds(entries) {
  var out = []
  if (!isList(entries)) return out
  for (var i = 0; i < entries.length; i++) {
    var id = entries[i] && typeof entries[i].id === "string" ? entries[i].id : ""
    if (id && out.indexOf(id) === -1) out.push(id)
  }
  return out
}

// Operations that turn `current` into `next` (both id lists without
// duplicates), applied in order to a ListModel:
//   { op: "remove", index }, { op: "move", from, to }, { op: "insert", index, id }
function reconcile(current, next) {
  var ops = []
  var work = current.slice()
  for (var r = work.length - 1; r >= 0; r--) {
    if (next.indexOf(work[r]) === -1) {
      ops.push({ op: "remove", index: r })
      work.splice(r, 1)
    }
  }
  for (var i = 0; i < next.length; i++) {
    var id = next[i]
    var at = work.indexOf(id)
    if (at === i) continue
    if (at === -1) {
      ops.push({ op: "insert", index: i, id: id })
      work.splice(i, 0, id)
    } else {
      ops.push({ op: "move", from: at, to: i })
      work.splice(at, 1)
      work.splice(i, 0, id)
    }
  }
  return ops
}

// Settings by id, for the slot that shows each widget.
function settingsById(entries) {
  var out = {}
  if (!isList(entries)) return out
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    if (entry && typeof entry.id === "string" && !(entry.id in out)) out[entry.id] = entry.settings || {}
  }
  return out
}

// The last live component the registry gave for each widget id, shared by
// every instance of this bar. After a bar swap (shell.json briefly read as
// empty, so the stock bar loads for a moment and this bar is rebuilt), the
// registry snapshot a new instance receives can hold null in place of
// components that are still alive in the shell, until the shell next syncs
// it. The previous instance saw them live, so the slot falls back to that.
var lastLive = {}

// The component a slot should load: the registry's while it is live, else the
// last live one for that id. `entry` is the registry entry (null when the
// registry has none); `registryKnown` is false while there is no registry to
// ask, so a missing entry then forgets nothing.
function componentFor(id, entry, registryKnown) {
  if (entry && entry.component) {
    lastLive[id] = entry.component
    return entry.component
  }
  if (!entry) {
    if (registryKnown) delete lastLive[id]
    return null
  }
  return lastLive[id] || null
}

function forget() {
  lastLive = {}
}
