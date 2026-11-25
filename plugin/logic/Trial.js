.pragma library

// Trial activation: scripts/activate.sh records the Hyprland instance it ran
// in as `trialInstance`. In any other instance (after logging in again, or
// after the compositor restarted) the bar hands the desktop back to the stock
// bar instead of coming up, so a trial never survives a login on its own.

var INSTANCE_PATTERN = /^[A-Za-z0-9_.-]{1,160}$/

function sanitizeInstance(value) {
  return typeof value === "string" && INSTANCE_PATTERN.test(value) ? value : ""
}

// True when a recorded trial belongs to a different (or unknown) session.
function isStale(trialInstance, currentInstance) {
  var trial = sanitizeInstance(trialInstance)
  if (!trial) return false
  return trial !== String(currentInstance || "")
}

// The shell.json `bar` subtree change that ends a stale trial: deselect this
// bar (only if it is still the selected one) and forget the trial. A settings
// object left empty is removed, as rollback.sh does, so shell.json matches
// what it was before the trial.
function endTrial(barSubtree, pluginId, settingsKey) {
  if (!barSubtree || typeof barSubtree !== "object") return barSubtree
  if (barSubtree.id === pluginId) delete barSubtree.id
  var own = barSubtree[settingsKey]
  if (own && typeof own === "object" && !Array.isArray(own)) {
    delete own.trialInstance
    if (Object.keys(own).length === 0) delete barSubtree[settingsKey]
  }
  return barSubtree
}
