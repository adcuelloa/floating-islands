// Pure formatting, ring-cycling, and config-resolution helpers for the
// Adaptive Clock island. Native ECMAScript module executed directly by
// Qt/QML and Node.js with no build step.

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
 * @typedef {{
 *   readonly format: string,
 *   readonly formatAlt: string,
 *   readonly nativeConfigured: boolean,
 *   readonly nativeFormat: string,
 *   readonly nativeSettings: Record<string, unknown>,
 *   readonly hasLegacyOverride: boolean,
 *   readonly ring: readonly string[]
 * }} ResolvedClockConfig
 */

/**
 * Exact native Omarchy 4.5.0-3 horizontal clock format presets and ordering
 * (`panels/clock/Model.js` CLOCK_FORMATS).
 *
 * @type {readonly string[]}
 */
export const NATIVE_HORIZONTAL_FORMATS = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "dddd HH:mm:ss",
  "dddd h:mm:ss AP",
  "HH:mm",
  "h:mm AP",
  "ddd d MMM HH:mm",
  "ddd d MMM h:mm AP",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm"
];

export const DEFAULT_FORMAT = "HH:mm";
export const DEFAULT_ALT_FORMAT = "d MMMM 'W'ww yyyy";

// The weekday's Qt pattern; the date's comes from Calendar.patterns().
export const WEEKDAY_FORMAT = "ddd";

const MAX_FORMAT_LENGTH = 64;
const MS_PER_DAY = 86400000;
const BAR_SECTIONS = ["left", "centerBegin", "center", "centerEnd", "right", "tray"];

/**
 * Strips single-quoted Qt format literals (`'...'`, including an unclosed
 * trailing quote) so token checks never misread literal text such as `'Sat'`
 * or `'W'` as format specifiers.
 *
 * @param {string} format
 * @returns {string}
 */
export function stripQuotedLiterals(format) {
  const text = String(format === undefined || format === null ? "" : format);
  return text.replace(/'[^']*'?/g, "");
}

/**
 * Whether a format prints seconds outside single-quoted literals. Matches
 * Omarchy's `Model.clockNeedsSeconds`.
 *
 * @param {string} format
 * @returns {boolean}
 */
export function hasSecondsToken(format) {
  return /s/.test(stripQuotedLiterals(format));
}

/**
 * Whether a format already contains any date, weekday, or ISO-week token
 * outside single-quoted literals (`d`, `M`, `y`, `ww`). When true, the
 * supplementary Floating Islands weekday/date labels are suppressed to avoid
 * duplicate date or weekday rendering.
 *
 * @param {string} format
 * @returns {boolean}
 */
export function hasDateOrWeekdayToken(format) {
  return /[dMy]|ww/.test(stripQuotedLiterals(format));
}

/**
 * What supplementary parts the clock island shows beside the formatted text:
 * for time-only formats, the day and month from compact up and the weekday
 * (in the accent) only in full; for composite/date formats that already carry
 * date, weekday, or ISO week tokens, neither supplementary label is drawn.
 *
 * @param {Tier} tier
 * @param {string} [format]
 * @returns {ClockParts}
 */
export function partsFor(tier, format) {
  if (format !== undefined && hasDateOrWeekdayToken(format)) {
    return { date: false, weekday: false };
  }
  return {
    date: tier === "full" || tier === "compact",
    weekday: tier === "full"
  };
}

/**
 * The detailed time (hover, calendar header): inserts `:ss` after the last
 * unquoted `mm` token ("h:mm AP" -> "h:mm:ss AP", "dddd HH:mm" ->
 * "dddd HH:mm:ss"). A format that already shows seconds, or has no unquoted
 * minutes to follow, is kept as it is.
 *
 * @param {string} format
 * @returns {string}
 */
export function withSeconds(format) {
  const text = String(format === undefined || format === null ? "" : format);
  if (hasSecondsToken(text)) return text;

  let inQuote = false;
  let lastMm = -1;
  for (let i = 0; i < text.length; i++) {
    const ch = text.charAt(i);
    if (ch === "'") {
      if (inQuote && i + 1 < text.length && text.charAt(i + 1) === "'") {
        i++;
      } else {
        inQuote = !inQuote;
      }
      continue;
    }
    if (!inQuote && ch === "m" && i + 1 < text.length && text.charAt(i + 1) === "m") {
      lastMm = i;
      i++;
    }
  }
  return lastMm === -1 ? text : text.slice(0, lastMm + 2) + ":ss" + text.slice(lastMm + 2);
}

/**
 * ISO-8601 week number (1..53): the week owning the Thursday of that date's
 * Monday-based week. Mirrors Omarchy's `Model.isoWeek`.
 *
 * @param {number} year
 * @param {number} month 0-based JS month (0..11)
 * @param {number} day 1-based day of month (1..31)
 * @returns {number}
 */
export function isoWeek(year, month, day) {
  const date = new Date(Date.UTC(year, month, day));
  const weekday = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - weekday);
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7);
}

/**
 * Two-digit ISO week string (`"01"`..`"53"`).
 *
 * @param {number} year
 * @param {number} month 0-based JS month (0..11)
 * @param {number} day 1-based day of month (1..31)
 * @returns {string}
 */
export function isoWeekLiteral(year, month, day) {
  const n = isoWeek(year, month, day);
  return (n < 10 ? "0" : "") + String(n);
}

/**
 * Substitutes unquoted `ww` ISO-week tokens with the two-digit ISO week for
 * `date` (leaving quoted literals such as `'www'` untouched), optionally
 * localizing each digit via `formatDigit` (matching Omarchy's `I18n.formatNumber`).
 *
 * @param {string} format
 * @param {Date} date
 * @param {((digit: string) => string) | null} [formatDigit]
 * @returns {string}
 */
export function expandIsoWeek(format, date, formatDigit) {
  const text = String(format === undefined || format === null ? "" : format);
  if (text.indexOf("ww") === -1) return text;

  const rawWeek = isoWeekLiteral(date.getFullYear(), date.getMonth(), date.getDate());
  let week = rawWeek;
  if (typeof formatDigit === "function") {
    let localized = "";
    for (let d = 0; d < rawWeek.length; d++) {
      localized += String(formatDigit(rawWeek.charAt(d)));
    }
    week = localized;
  }

  let out = "";
  let inQuote = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text.charAt(i);
    if (ch === "'") {
      out += ch;
      if (inQuote && i + 1 < text.length && text.charAt(i + 1) === "'") {
        out += "'";
        i++;
      } else {
        inQuote = !inQuote;
      }
      continue;
    }
    if (!inQuote && ch === "w" && i + 1 < text.length && text.charAt(i + 1) === "w") {
      out += week;
      i++;
      continue;
    }
    out += ch;
  }
  return out;
}

/**
 * Builds the deduplicated format ring in fixed native order: presets first,
 * followed by any non-empty custom alternate and configured formats. Mirrors
 * Omarchy's `Model.clockFormatRing`.
 *
 * @param {string | null | undefined} configured
 * @param {string | null | undefined} [configuredAlt]
 * @param {readonly (string | null | undefined)[]} [presets]
 * @returns {string[]}
 */
export function formatRing(configured, configuredAlt, presets) {
  /** @type {string[]} */
  const ring = [];
  const base = Array.isArray(presets) ? presets : NATIVE_HORIZONTAL_FORMATS;
  /** @type {Array<string | null | undefined>} */
  const candidates = base.slice();
  candidates.push(configuredAlt, configured);
  for (let i = 0; i < candidates.length; i++) {
    const raw = candidates[i];
    const fmt = String(raw === undefined || raw === null ? "" : raw);
    if (fmt === "" || ring.indexOf(fmt) !== -1) continue;
    ring.push(fmt);
  }
  return ring.length > 0 ? ring : [DEFAULT_FORMAT];
}

/**
 * Next format in `ring` after `current`, wrapping around to index 0. An
 * unknown current format starts at index 0. Mirrors Omarchy's
 * `Model.nextClockFormat`.
 *
 * @param {readonly string[]} ring
 * @param {string | null | undefined} current
 * @returns {string}
 */
export function nextFormat(ring, current) {
  if (!ring || ring.length === 0) return "";
  const index = ring.indexOf(String(current === undefined || current === null ? "" : current));
  const target = ring[(index + 1) % ring.length];
  return target === undefined ? "" : target;
}

/**
 * @param {unknown} value
 * @returns {value is Record<string, unknown>}
 */
function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

/**
 * @param {unknown} value
 * @returns {string}
 */
function validFormatString(value) {
  return typeof value === "string" && value.length > 0 && value.length <= MAX_FORMAT_LENGTH ? value : "";
}

/**
 * @param {unknown} entry
 * @returns {string}
 */
function entryId(entry) {
  if (typeof entry === "string") return entry;
  return isPlainObject(entry) && entry.id !== undefined && entry.id !== null ? String(entry.id) : "";
}

/**
 * Resolves the active clock format, native `omarchy.clock` entry metadata,
 * alternate format, legacy `bar.islands.timeFormat` override status, and the
 * deduplicated format ring from `barConfig`.
 *
 * Read priority:
 * 1. Explicit `bar.<settingsKey>.timeFormat` (backwards compatibility)
 * 2. Native `bar.layout` `omarchy.clock` entry `format`
 * 3. `DEFAULT_FORMAT` (`"HH:mm"`)
 *
 * @param {unknown} barConfig
 * @param {string} [settingsKey]
 * @returns {ResolvedClockConfig}
 */
export function resolveClockConfig(barConfig, settingsKey) {
  const key = settingsKey || "islands";
  const cfg = isPlainObject(barConfig) ? barConfig : {};
  const layout = isPlainObject(cfg.layout) ? cfg.layout : {};

  /** @type {unknown} */
  let foundEntry = null;
  for (let s = 0; s < BAR_SECTIONS.length && foundEntry === null; s++) {
    const sectionName = BAR_SECTIONS[s];
    if (sectionName === undefined) continue;
    const list = Array.isArray(layout[sectionName]) ? layout[sectionName] : [];
    for (let i = 0; i < list.length; i++) {
      if (entryId(list[i]) === "omarchy.clock") {
        foundEntry = list[i];
        break;
      }
    }
  }

  const nativeConfigured = foundEntry !== null;
  /** @type {Record<string, unknown>} */
  const nativeSettings = {};
  if (isPlainObject(foundEntry)) {
    const keys = Object.keys(foundEntry);
    for (let k = 0; k < keys.length; k++) {
      const prop = keys[k];
      if (prop !== undefined && prop !== "id") {
        nativeSettings[prop] = foundEntry[prop];
      }
    }
  }

  const nativeFormat = validFormatString(nativeSettings.format);
  const formatAlt = validFormatString(nativeSettings.formatAlt) || DEFAULT_ALT_FORMAT;

  const islandsRaw = isPlainObject(cfg[key]) ? cfg[key] : {};
  const legacyFormat = validFormatString(islandsRaw.timeFormat);
  const hasLegacyOverride = legacyFormat !== "";
  const format = legacyFormat || nativeFormat || DEFAULT_FORMAT;

  const baseRing = formatRing(nativeFormat || format, formatAlt, NATIVE_HORIZONTAL_FORMATS);
  const ring = formatRing(format, formatAlt, baseRing);

  return {
    format: format,
    formatAlt: formatAlt,
    nativeConfigured: nativeConfigured,
    nativeFormat: nativeFormat,
    nativeSettings: nativeSettings,
    hasLegacyOverride: hasLegacyOverride,
    ring: ring
  };
}

/**
 * Builds the merged `omarchy.clock` inline entry payload for
 * `shell.updateEntryInline("omarchy.clock", entry)`, preserving all unrelated
 * keys (`formatAlt`, `weekStartDay`, `birthYear`, `lifeExpectancy`, etc.).
 *
 * @param {Record<string, unknown> | null | undefined} nativeSettings
 * @param {string} nextClockFormat
 * @returns {Record<string, unknown>}
 */
export function buildInlineClockEntry(nativeSettings, nextClockFormat) {
  /** @type {Record<string, unknown>} */
  const entry = { id: "omarchy.clock" };
  if (isPlainObject(nativeSettings)) {
    const keys = Object.keys(nativeSettings);
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      if (k !== undefined && k !== "id") {
        entry[k] = nativeSettings[k];
      }
    }
  }
  entry.format = nextClockFormat;
  return entry;
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
