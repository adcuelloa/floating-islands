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

// Splits a Qt time format around the seconds insertion point so the clock
// island can keep HH:mm readable while revealing :ss progressively on its
// right (and shifting any trailing suffix such as " AP" smoothly right).
function splitSeconds(format) {
  var fmt = String(format || "")
  if (fmt.indexOf("s") !== -1) {
    return { prefix: fmt, seconds: "", suffix: "", expandable: false }
  }
  var at = fmt.lastIndexOf("mm")
  if (at === -1) {
    return { prefix: fmt, seconds: "", suffix: "", expandable: false }
  }
  return {
    prefix: fmt.slice(0, at + 2),
    seconds: ":ss",
    suffix: fmt.slice(at + 2),
    expandable: true
  }
}

// The detailed time (hover, calendar header): the time format with seconds
// after its minutes ("h:mm AP" -> "h:mm:ss AP"). A format that already shows
// seconds, or has no minutes to follow, is kept as it is.
function withSeconds(format) {
  var parts = splitSeconds(format)
  return parts.expandable ? parts.prefix + parts.seconds + parts.suffix : parts.prefix
}

// Normalizes ASCII digits to "8" for stable width measurement so individual
// second or minute ticks never jitter the clock island's width.
function stableDigits(text) {
  return String(text || "").replace(/[0-9]/g, "8")
}
