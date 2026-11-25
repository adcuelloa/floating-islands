// Pure formatting helpers for the Adaptive Clock island. Native ECMAScript
// module executed directly by Qt/QML and Node.js with no build step.

/** @typedef {import("../geometry/Layout.mjs").Tier} Tier */

/**
 * @typedef {{
 *   readonly date: boolean,
 *   readonly weekday: boolean
 * }} ClockParts
 */

/**
 * @typedef {{
 *   readonly prefix: string,
 *   readonly seconds: string,
 *   readonly suffix: string,
 *   readonly expandable: boolean
 * }} TimeTextParts
 */

/**
 * What the clock island shows in each tier: the time always, the day and month
 * from compact up, and the weekday (in the accent) only in full.
 *
 * @param {Tier} tier
 * @returns {ClockParts}
 */
export function partsFor(tier) {
  return {
    date: tier === "full" || tier === "compact",
    weekday: tier === "full"
  };
}

// The weekday's Qt pattern; the date's comes from Calendar.patterns().
export const WEEKDAY_FORMAT = "ddd";

/**
 * The detailed time (hover, calendar header): the time format with seconds
 * after its minutes ("h:mm AP" -> "h:mm:ss AP"). A format that already shows
 * seconds, or has no minutes to follow, is kept as it is.
 *
 * @param {string} format
 * @returns {string}
 */
export function withSeconds(format) {
  if (format.indexOf("s") !== -1) return format;
  const at = format.lastIndexOf("mm");
  return at === -1 ? format : format.slice(0, at + 2) + ":ss" + format.slice(at + 2);
}

/**
 * Splits already-formatted compact and detailed time strings into
 * { prefix, seconds, suffix, expandable } so Qt's own locale/12h formatting
 * (e.g. "3:55 PM" vs "3:55:42 PM") is preserved verbatim while :ss reveals
 * progressively between prefix and suffix.
 *
 * @param {string} compactText
 * @param {string} detailText
 * @returns {TimeTextParts}
 */
export function splitTimeText(compactText, detailText) {
  const compact = String(compactText || "");
  const detail = String(detailText || "");
  if (compact === detail || detail.length <= compact.length) {
    return { prefix: compact, seconds: "", suffix: "", expandable: false };
  }
  let prefixLen = 0;
  while (prefixLen < compact.length && compact.charCodeAt(prefixLen) === detail.charCodeAt(prefixLen)) {
    prefixLen++;
  }
  const maxSuffix = compact.length - prefixLen;
  let suffixLen = 0;
  while (
    suffixLen < maxSuffix &&
    compact.charCodeAt(compact.length - 1 - suffixLen) === detail.charCodeAt(detail.length - 1 - suffixLen)
  ) {
    suffixLen++;
  }
  if (prefixLen + suffixLen !== compact.length) {
    return { prefix: detail, seconds: "", suffix: "", expandable: false };
  }
  return {
    prefix: compact.slice(0, prefixLen),
    seconds: detail.slice(prefixLen, detail.length - suffixLen),
    suffix: suffixLen > 0 ? compact.slice(compact.length - suffixLen) : "",
    expandable: true
  };
}

/**
 * Normalizes ASCII digits to "8" for stable width measurement so individual
 * second or minute ticks never jitter the clock island's width.
 *
 * @param {string} text
 * @returns {string}
 */
export function stableDigits(text) {
  return String(text || "").replace(/[0-9]/g, "8");
}
