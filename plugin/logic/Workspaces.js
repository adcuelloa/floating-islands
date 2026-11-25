.pragma library

// Workspace numbering as Omarchy lays it out (default/hypr/monitor-workspaces.lua):
// each monitor owns a block of ten, 1-10, 11-20, ..., and a bar shows its own
// monitor's block. The first five always show; higher ones show while they
// exist; workspaces from another block that sit on this monitor (a monitor was
// unplugged) follow as guests.

var SLOTS = 10
var ALWAYS_SHOWN = 5

function blockOf(id) {
  return Math.floor((id - 1) / SLOTS)
}

function slotOf(id) {
  return (id - 1) % SLOTS + 1
}

// The state file Hyprland writes: "<block>\t<connector>\t<description>" lines.
function parseBlocks(text) {
  var blocks = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var fields = lines[i].split("\t")
    if (fields.length < 3 || fields[1] === "") continue
    var block = parseInt(fields[0], 10)
    if (isFinite(block) && block >= 0) blocks[fields[1]] = block
  }
  return blocks
}

// Until Hyprland has written the file, the workspace a monitor shows names
// its block.
function blockFor(blocks, monitorName, activeId) {
  if (blocks && Object.prototype.hasOwnProperty.call(blocks, monitorName)) return blocks[monitorName]
  return activeId > 0 ? blockOf(activeId) : 0
}

// workspaces: [{ id, monitorName, windows }]
function entries(block, workspaces, monitorName, activeId) {
  var known = {}
  var own = []
  var guests = []
  var base = block * SLOTS
  for (var n = 1; n <= ALWAYS_SHOWN; n++) own.push(base + n)

  var list = workspaces || []
  for (var i = 0; i < list.length; i++) {
    var ws = list[i]
    if (!ws || !(ws.id > 0)) continue
    known[ws.id] = ws
    if (blockOf(ws.id) === block) {
      if (own.indexOf(ws.id) === -1) own.push(ws.id)
    } else if (ws.monitorName === monitorName && guests.indexOf(ws.id) === -1) {
      guests.push(ws.id)
    }
  }

  var byNumber = function(left, right) { return left - right }
  own.sort(byNumber)
  guests.sort(byNumber)

  var out = []
  var ids = own.concat(guests)
  for (var j = 0; j < ids.length; j++) {
    var id = ids[j]
    var guest = blockOf(id) !== block
    out.push({
      id: id,
      slot: slotOf(id),
      label: guest ? String(id) : (slotOf(id) === SLOTS ? "0" : String(slotOf(id))),
      active: id === activeId,
      occupied: !!known[id] && known[id].windows > 0,
      guest: guest,
      firstGuest: guest && (j === 0 || blockOf(ids[j - 1]) === block)
    })
  }
  return out
}

// A Lua string literal; connector names come from the compositor, but are
// still quoted rather than trusted.
function luaString(value) {
  return "\"" + String(value || "").replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\n/g, "\\n") + "\""
}

// The `hyprctl dispatch` expression that shows workspace `id` on this
// monitor, as the stock workspaces widget sends it.
function focusDispatch(id, block, monitorName) {
  var n = Math.floor(Number(id))
  if (!(n > 0)) return ""
  if (blockOf(n) === block) return "o.workspaces.focus(" + slotOf(n) + ", " + luaString(monitorName) + ")"
  return "hl.dsp.focus({ workspace = " + luaString(String(n)) + " })"
}

// Wheel steps move along the shown row and stop at either end.
function scrollTarget(ids, activeId, steps) {
  var index = ids.indexOf(activeId)
  if (index === -1 || !steps) return -1
  var next = Math.max(0, Math.min(ids.length - 1, index - steps))
  return next === index ? -1 : ids[next]
}
