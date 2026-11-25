.pragma library

// What the clock island shows in each tier: the time always, the day and month
// from compact up, and the weekday (in the accent) only in full.

function partsFor(tier) {
  return {
    date: tier === "full" || tier === "compact",
    weekday: tier === "full"
  }
}

// The weekday's Qt pattern; the date's comes from Calendar.patterns().
var WEEKDAY_FORMAT = "ddd"

// The detailed time (hover, calendar header): the time format with seconds
// after its minutes ("h:mm AP" -> "h:mm:ss AP"). A format that already shows
// seconds, or has no minutes to follow, is kept as it is.
function withSeconds(format) {
  if (format.indexOf("s") !== -1) return format
  var at = format.lastIndexOf("mm")
  return at === -1 ? format : format.slice(0, at + 2) + ":ss" + format.slice(at + 2)
}

// Normalizes ASCII digits to "8" for stable width measurement so individual
// second or minute ticks never jitter the clock island's width.
function stableDigits(text) {
  return String(text || "").replace(/[0-9]/g, "8")
}
