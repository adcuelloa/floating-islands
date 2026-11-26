// Pure formatting, ring-cycling, week-start, and config-resolution helpers
// for the Adaptive Clock island. Native ECMAScript module executed directly
// by Qt/QML and Node.js with no build step.

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
 *   readonly nativeEntryIsObject: boolean,
 *   readonly nativeFormat: string,
 *   readonly nativeSettings: Record<string, unknown>,
 *   readonly hasLegacyOverride: boolean,
 *   readonly hasLegacyTimeFormatKey: boolean,
 *   readonly customFormats: readonly string[],
 *   readonly weekStartDay: unknown,
 *   readonly hasLegacyWeekStart: boolean,
 *   readonly ring: readonly string[]
 * }} ResolvedClockConfig
 */

/**
 * @typedef {{
 *   readonly accepted: boolean,
 *   readonly status: "persisted" | "unchanged" | "rejected" | "unavailable",
 *   readonly method: "none" | "updateEntryInline" | "mutateShellConfig",
 *   readonly durableConfirmed: false
 * }} PersistOutcome
 */

/**
 * @typedef {{
 *   updateEntryInline?: (id: string, entry: Record<string, unknown>) => boolean,
 *   mutateShellConfig?: (mutator: (config: Record<string, unknown>) => void) => boolean
 * }} ClockShellApi
 */

/**
 * @typedef {{
 *   readonly settingsKey?: string,
 *   readonly currentFormat?: string,
 *   readonly pendingNativeFields?: Record<string, unknown> | null,
 *   readonly pendingCustomFormats?: readonly string[] | null
 * }} PersistClockFormatOptions
 */

/**
 * @typedef {{
 *   readonly settingsKey?: string,
 *   readonly pendingNativeFields?: Record<string, unknown> | null
 * }} PersistWeekStartOptions
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

/**
 * Weekday names matching JS Date.getDay(), QML Locale.Sunday..Saturday, and
 * Omarchy's `panels/clock/Model.js` WEEKDAY_NAMES.
 *
 * @type {readonly string[]}
 */
export const WEEKDAY_NAMES = [
  "sunday",
  "monday",
  "tuesday",
  "wednesday",
  "thursday",
  "friday",
  "saturday"
];

/**
 * Maximum number of user-defined custom formats retained under
 * `bar.islands.customClockFormats`. Keeps persistence bounded while
 * preserving custom formats across cycling and restart.
 */
export const MAX_CUSTOM_FORMATS = 8;

const MS_PER_DAY = 86400000;
const BAR_SECTIONS = ["left", "centerBegin", "center", "centerEnd", "right", "tray"];
const CONTROL_CHAR_RE = /[\u0000-\u001f\u007f]/;

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
 * Validates a horizontal clock format string without imposing an arbitrary
 * 64-character length cap. Rejects non-strings, blank strings, and control
 * characters.
 *
 * @param {unknown} value
 * @returns {string}
 */
export function validFormatString(value) {
  if (typeof value !== "string") return "";
  if (value.trim().length === 0) return "";
  if (CONTROL_CHAR_RE.test(value)) return "";
  return value;
}

/**
 * @param {string} format
 * @returns {boolean}
 */
export function isNativePreset(format) {
  return NATIVE_HORIZONTAL_FORMATS.indexOf(format) !== -1;
}

/**
 * Sanitizes a persisted custom format list: keeps only valid non-preset
 * formats that do not duplicate `formatAlt` or earlier entries, bounded to
 * `MAX_CUSTOM_FORMATS`.
 *
 * @param {unknown} raw
 * @param {string} [formatAlt]
 * @returns {string[]}
 */
export function sanitizeCustomFormats(raw, formatAlt) {
  if (!isList(raw)) return [];
  const alt = validFormatString(formatAlt);
  /** @type {string[]} */
  const out = [];
  for (let i = 0; i < raw.length && out.length < MAX_CUSTOM_FORMATS; i++) {
    const fmt = validFormatString(raw[i]);
    if (fmt === "" || isNativePreset(fmt) || fmt === alt || out.indexOf(fmt) !== -1) continue;
    out.push(fmt);
  }
  return out;
}

/**
 * Retains `formatToRetain` in the bounded custom-format list when it is a
 * valid user-defined format outside the native presets and `formatAlt`.
 * Ordinary clicks on native presets or `formatAlt` leave the list unchanged.
 *
 * @param {readonly string[] | null | undefined} existing
 * @param {string | null | undefined} formatToRetain
 * @param {string} [formatAlt]
 * @returns {string[]}
 */
export function retainCustomFormat(existing, formatToRetain, formatAlt) {
  const list = sanitizeCustomFormats(existing, formatAlt);
  const fmt = validFormatString(formatToRetain);
  const alt = validFormatString(formatAlt);
  if (fmt === "" || isNativePreset(fmt) || fmt === alt || list.indexOf(fmt) !== -1) {
    return list;
  }
  const next = list.concat([fmt]);
  return next.length > MAX_CUSTOM_FORMATS ? next.slice(next.length - MAX_CUSTOM_FORMATS) : next;
}

/**
 * Builds the deduplicated format ring in fixed native order: presets first,
 * followed by the configured alternate format, any retained custom formats,
 * and the active configured format. Mirrors Omarchy's `Model.clockFormatRing`
 * while retaining user-defined custom formats.
 *
 * @param {string | null | undefined} configured
 * @param {string | null | undefined} [configuredAlt]
 * @param {readonly (string | null | undefined)[]} [presets]
 * @param {readonly (string | null | undefined)[]} [customFormats]
 * @returns {string[]}
 */
export function formatRing(configured, configuredAlt, presets, customFormats) {
  /** @type {string[]} */
  const ring = [];
  const base = isList(presets) ? Array.prototype.slice.call(presets) : NATIVE_HORIZONTAL_FORMATS;
  /** @type {Array<string | null | undefined>} */
  const candidates = base.slice();
  candidates.push(configuredAlt);
  if (isList(customFormats)) {
    for (let c = 0; c < customFormats.length; c++) {
      candidates.push(customFormats[c]);
    }
  }
  candidates.push(configured);
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
 * Coerces a week-start setting (`"monday"`, `"sun"`, `0`..`7`, etc.) into a
 * 0..6 weekday index (`0 = Sunday .. 6 = Saturday`), or `null` when missing or
 * invalid. Mirrors Omarchy's `panels/clock/Model.js` `coerceWeekStart`.
 *
 * @param {unknown} value
 * @returns {number | null}
 */
export function coerceWeekStart(value) {
  if (value === undefined || value === null) return null;
  if (typeof value === "number") {
    return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null;
  }
  const text = String(value).replace(/^\s+|\s+$/g, "").toLowerCase();
  if (text === "") return null;

  for (let i = 0; i < WEEKDAY_NAMES.length; i++) {
    const name = WEEKDAY_NAMES[i];
    if (name !== undefined && (name === text || name.slice(0, 3) === text)) return i;
  }

  const parsed = parseInt(text, 10);
  return isFinite(parsed) ? ((parsed % 7) + 7) % 7 : null;
}

/**
 * Configured week start (`0..6`), falling back to the locale's first day of
 * week when missing or invalid, and to Monday (`1`) if the fallback is also
 * invalid. Mirrors Omarchy's `Model.normalizedWeekStart`.
 *
 * @param {unknown} value
 * @param {unknown} fallback
 * @returns {number}
 */
export function normalizedWeekStart(value, fallback) {
  const configured = coerceWeekStart(value);
  if (configured !== null) return configured;
  const fallbackStart = coerceWeekStart(fallback);
  return fallbackStart === null ? 1 : fallbackStart;
}

/**
 * Canonical setting string (`"sunday"`..`"saturday"`) for a week-start index.
 * Mirrors Omarchy's `Model.weekStartSettingName`.
 *
 * @param {unknown} index
 * @returns {string}
 */
export function weekStartSettingName(index) {
  const name = WEEKDAY_NAMES[normalizedWeekStart(index, 1)];
  return name === undefined ? "monday" : name;
}

/**
 * Native Monday/Sunday toggle semantics: Monday (`1`) toggles to Sunday (`0`);
 * Sunday or any other configured day (e.g. Saturday) toggles to Monday (`1`).
 * Mirrors Omarchy's `Model.toggledWeekStart`.
 *
 * @param {unknown} index
 * @returns {number}
 */
export function toggledWeekStart(index) {
  return normalizedWeekStart(index, 1) === 1 ? 0 : 1;
}

/**
 * Handles both native JS arrays and Qt QVariantList values passed through QML
 * `property var` boundaries.
 *
 * @param {unknown} value
 * @returns {value is readonly unknown[]}
 */
function isList(value) {
  if (Array.isArray(value)) return true;
  if (value === null || typeof value !== "object") return false;
  const candidate = /** @type {{ length?: unknown }} */ (value);
  return typeof candidate.length === "number" && candidate.length >= 0 && Math.floor(candidate.length) === candidate.length;
}

/**
 * @param {unknown} value
 * @returns {value is Record<string, unknown>}
 */
function isPlainObject(value) {
  return value !== null && typeof value === "object" && !isList(value);
}

/**
 * @param {unknown} value
 * @returns {string}
 */
export function canonicalWidgetId(value) {
  return String(value === undefined || value === null ? "" : value).trim();
}

/**
 * @param {unknown} entry
 * @returns {string}
 */
function entryId(entry) {
  if (typeof entry === "string") return canonicalWidgetId(entry);
  return isPlainObject(entry) && entry.id !== undefined && entry.id !== null ? canonicalWidgetId(entry.id) : "";
}

/**
 * @param {Record<string, unknown>} layout
 * @returns {{ section: string, index: number, entry: unknown, isObject: boolean } | null}
 */
function findClockEntry(layout) {
  for (let s = 0; s < BAR_SECTIONS.length; s++) {
    const sectionName = BAR_SECTIONS[s];
    if (sectionName === undefined) continue;
    const list = isList(layout[sectionName]) ? layout[sectionName] : [];
    for (let i = 0; i < list.length; i++) {
      if (entryId(list[i]) === "omarchy.clock") {
        return {
          section: sectionName,
          index: i,
          entry: list[i],
          isObject: isPlainObject(list[i])
        };
      }
    }
  }
  return null;
}

/**
 * @param {unknown} entry
 * @returns {Record<string, unknown>}
 */
function extractEntrySettings(entry) {
  /** @type {Record<string, unknown>} */
  const out = {};
  if (!isPlainObject(entry)) return out;
  const keys = Object.keys(entry);
  for (let i = 0; i < keys.length; i++) {
    const prop = keys[i];
    if (prop !== undefined && prop !== "id") {
      out[prop] = entry[prop];
    }
  }
  return out;
}

/**
 * @param {Record<string, unknown> | null | undefined} base
 * @param {Record<string, unknown> | null | undefined} overrides
 * @returns {Record<string, unknown>}
 */
function mergeSettings(base, overrides) {
  /** @type {Record<string, unknown>} */
  const out = {};
  if (isPlainObject(base)) {
    const baseKeys = Object.keys(base);
    for (let i = 0; i < baseKeys.length; i++) {
      const k = baseKeys[i];
      if (k !== undefined && k !== "id") out[k] = base[k];
    }
  }
  if (isPlainObject(overrides)) {
    const overrideKeys = Object.keys(overrides);
    for (let j = 0; j < overrideKeys.length; j++) {
      const k = overrideKeys[j];
      if (k !== undefined && k !== "id" && overrides[k] !== undefined) out[k] = overrides[k];
    }
  }
  return out;
}

/**
 * @param {readonly string[]} a
 * @param {readonly string[]} b
 * @returns {boolean}
 */
function stringArraysEqual(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

/**
 * Deterministic JSON equality ignoring object key order.
 *
 * @param {unknown} value
 * @returns {string}
 */
function canonicalJson(value) {
  if (isList(value)) {
    let items = "";
    for (let i = 0; i < value.length; i++) {
      if (i > 0) items += ",";
      items += canonicalJson(value[i]);
    }
    return "[" + items + "]";
  }
  if (isPlainObject(value)) {
    const keys = Object.keys(value).sort();
    let props = "";
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      if (k === undefined || value[k] === undefined) continue;
      if (props.length > 0) props += ",";
      props += JSON.stringify(k) + ":" + canonicalJson(value[k]);
    }
    return "{" + props + "}";
  }
  return JSON.stringify(value);
}

/**
 * Resolves the active clock format, native `omarchy.clock` entry metadata,
 * alternate format, legacy `bar.islands.timeFormat` override status, retained
 * custom formats, week-start setting, and deduplicated format ring from
 * `barConfig`.
 *
 * Read priority:
 * 1. Explicit `bar.<settingsKey>.timeFormat` (backwards compatibility / fallback when native entry is absent)
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

  const found = findClockEntry(layout);
  const nativeConfigured = found !== null;
  const nativeEntryIsObject = found !== null && found.isObject;
  const nativeSettings = found !== null ? extractEntrySettings(found.entry) : {};

  const nativeFormat = validFormatString(nativeSettings.format);
  const formatAlt = validFormatString(nativeSettings.formatAlt) || DEFAULT_ALT_FORMAT;

  const islandsRaw = isPlainObject(cfg[key]) ? cfg[key] : {};
  const hasLegacyTimeFormatKey = Object.prototype.hasOwnProperty.call(islandsRaw, "timeFormat");
  const legacyFormat = validFormatString(islandsRaw.timeFormat);
  const hasLegacyOverride = legacyFormat !== "";
  const format = legacyFormat || nativeFormat || DEFAULT_FORMAT;

  const customFormats = sanitizeCustomFormats(islandsRaw.customClockFormats, formatAlt);
  const hasLegacyWeekStart = Object.prototype.hasOwnProperty.call(islandsRaw, "weekStartDay");
  const weekStartDay =
    nativeSettings.weekStartDay !== undefined ? nativeSettings.weekStartDay : islandsRaw.weekStartDay;

  const baseRing = formatRing(nativeFormat || format, formatAlt, NATIVE_HORIZONTAL_FORMATS, customFormats);
  const ring = formatRing(format, formatAlt, baseRing, customFormats);

  return {
    format: format,
    formatAlt: formatAlt,
    nativeConfigured: nativeConfigured,
    nativeEntryIsObject: nativeEntryIsObject,
    nativeFormat: nativeFormat,
    nativeSettings: nativeSettings,
    hasLegacyOverride: hasLegacyOverride,
    hasLegacyTimeFormatKey: hasLegacyTimeFormatKey,
    customFormats: customFormats,
    weekStartDay: weekStartDay,
    hasLegacyWeekStart: hasLegacyWeekStart,
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
  return buildInlineClockEntryWithFields(nativeSettings, { format: nextClockFormat });
}

/**
 * Builds a merged `omarchy.clock` inline entry payload with arbitrary field
 * updates, preserving all unrelated keys.
 *
 * @param {Record<string, unknown> | null | undefined} nativeSettings
 * @param {Record<string, unknown>} fields
 * @returns {Record<string, unknown>}
 */
export function buildInlineClockEntryWithFields(nativeSettings, fields) {
  /** @type {Record<string, unknown>} */
  const entry = { id: "omarchy.clock" };
  const merged = mergeSettings(nativeSettings, fields);
  const keys = Object.keys(merged);
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    if (k !== undefined && k !== "id") {
      entry[k] = merged[k];
    }
  }
  return entry;
}

/**
 * Applies a coherent bar-config mutation for a clock format change:
 * updates (or upgrades from string-form) `omarchy.clock` in `bar.layout` when
 * present, clears legacy `bar.<settingsKey>.timeFormat`, falls back to
 * `bar.<settingsKey>.timeFormat` only when no native clock entry exists, and
 * persists retained custom formats under `bar.<settingsKey>.customClockFormats`.
 *
 * @param {Record<string, unknown>} config
 * @param {string} settingsKey
 * @param {string} nextClockFormat
 * @param {readonly string[]} nextCustomFormats
 * @param {Record<string, unknown> | null | undefined} [pendingNativeFields]
 */
export function applyClockFormatMutation(config, settingsKey, nextClockFormat, nextCustomFormats, pendingNativeFields) {
  const key = settingsKey || "islands";
  if (!isPlainObject(config.bar)) config.bar = {};
  const bar = /** @type {Record<string, unknown>} */ (config.bar);
  const layout = isPlainObject(bar.layout) ? bar.layout : null;
  const found = layout !== null ? findClockEntry(layout) : null;

  if (found !== null && layout !== null) {
    const list = /** @type {unknown[]} */ (layout[found.section]);
    const existingSettings = extractEntrySettings(found.entry);
    const merged = mergeSettings(existingSettings, pendingNativeFields);
    list[found.index] = buildInlineClockEntry(merged, nextClockFormat);
    if (isPlainObject(bar[key]) && Object.prototype.hasOwnProperty.call(bar[key], "timeFormat")) {
      delete bar[key].timeFormat;
    }
  } else {
    if (!isPlainObject(bar[key])) bar[key] = {};
    /** @type {Record<string, unknown>} */ (bar[key]).timeFormat = nextClockFormat;
  }

  if (nextCustomFormats.length > 0) {
    if (!isPlainObject(bar[key])) bar[key] = {};
    /** @type {Record<string, unknown>} */ (bar[key]).customClockFormats = nextCustomFormats.slice();
  }
}

/**
 * Applies a coherent bar-config mutation for a `weekStartDay` change:
 * updates (or upgrades from string-form) `omarchy.clock` in `bar.layout` when
 * present and clears any fallback `bar.<settingsKey>.weekStartDay`, or stores
 * `bar.<settingsKey>.weekStartDay` when no native clock entry exists.
 *
 * @param {Record<string, unknown>} config
 * @param {string} settingsKey
 * @param {string} nextWeekStartName
 * @param {Record<string, unknown> | null | undefined} [pendingNativeFields]
 */
export function applyWeekStartMutation(config, settingsKey, nextWeekStartName, pendingNativeFields) {
  const key = settingsKey || "islands";
  if (!isPlainObject(config.bar)) config.bar = {};
  const bar = /** @type {Record<string, unknown>} */ (config.bar);
  const layout = isPlainObject(bar.layout) ? bar.layout : null;
  const found = layout !== null ? findClockEntry(layout) : null;

  if (found !== null && layout !== null) {
    const list = /** @type {unknown[]} */ (layout[found.section]);
    const existingSettings = extractEntrySettings(found.entry);
    const merged = mergeSettings(existingSettings, pendingNativeFields);
    list[found.index] = buildInlineClockEntryWithFields(merged, { weekStartDay: nextWeekStartName });
    if (isPlainObject(bar[key]) && Object.prototype.hasOwnProperty.call(bar[key], "weekStartDay")) {
      delete bar[key].weekStartDay;
    }
  } else {
    if (!isPlainObject(bar[key])) bar[key] = {};
    /** @type {Record<string, unknown>} */ (bar[key]).weekStartDay = nextWeekStartName;
  }
}

/**
 * Persists a clock format change using the supported native shell contracts:
 * - Uses `shell.updateEntryInline("omarchy.clock", entry)` for straightforward
 *   single-entry updates on an object-form native entry when no `bar.islands`
 *   fields need to change.
 * - Detects unchanged native entries before calling `updateEntryInline` so an
 *   unchanged entry is never misclassified as rejected persistence.
 * - Uses a single coherent `shell.mutateShellConfig` call whenever legacy
 *   `bar.islands.timeFormat` migration, custom format retention, string-form
 *   entry upgrade, or missing-entry fallback is needed.
 *
 * Note: an `accepted: true` result confirms only that the host shell accepted
 * the in-memory configuration mutation and requested a write; durable disk
 * persistence is only confirmed when reloaded from disk (`durableConfirmed: false`).
 *
 * @param {ClockShellApi | null | undefined} shell
 * @param {ResolvedClockConfig} cfg
 * @param {string} nextClockFormat
 * @param {PersistClockFormatOptions} [options]
 * @returns {PersistOutcome}
 */
export function persistClockFormat(shell, cfg, nextClockFormat, options) {
  const opts = options || {};
  const settingsKey = opts.settingsKey || "islands";
  const currentFmt = opts.currentFormat !== undefined ? opts.currentFormat : cfg.format;
  const currentCustom =
    opts.pendingCustomFormats !== undefined && opts.pendingCustomFormats !== null
      ? sanitizeCustomFormats(opts.pendingCustomFormats, cfg.formatAlt)
      : cfg.customFormats;
  const nextCustom = retainCustomFormat(currentCustom, currentFmt, cfg.formatAlt);
  const customChanged = !stringArraysEqual(currentCustom, nextCustom);
  const needsLegacyCleanup = cfg.nativeConfigured && cfg.hasLegacyTimeFormatKey;
  const needsCoherentMutation =
    !cfg.nativeConfigured || !cfg.nativeEntryIsObject || needsLegacyCleanup || customChanged;

  const mergedNative = mergeSettings(cfg.nativeSettings, opts.pendingNativeFields);
  const nextEntry = buildInlineClockEntry(mergedNative, nextClockFormat);

  if (!needsCoherentMutation) {
    const currentEntry = buildInlineClockEntryWithFields(cfg.nativeSettings, {});
    if (canonicalJson(currentEntry) === canonicalJson(nextEntry)) {
      return { accepted: true, status: "unchanged", method: "none", durableConfirmed: false };
    }
    if (shell && typeof shell.updateEntryInline === "function") {
      const ok = shell.updateEntryInline("omarchy.clock", nextEntry) === true;
      return {
        accepted: ok,
        status: ok ? "persisted" : "rejected",
        method: "updateEntryInline",
        durableConfirmed: false
      };
    }
  }

  if (shell && typeof shell.mutateShellConfig === "function") {
    const ok =
      shell.mutateShellConfig(function (config) {
        applyClockFormatMutation(config, settingsKey, nextClockFormat, nextCustom, opts.pendingNativeFields);
      }) === true;
    return {
      accepted: ok,
      status: ok ? "persisted" : "rejected",
      method: "mutateShellConfig",
      durableConfirmed: false
    };
  }

  return { accepted: false, status: "unavailable", method: "none", durableConfirmed: false };
}

/**
 * Persists a `weekStartDay` change through the same supported shell contracts
 * as `persistClockFormat`, preserving `format`, `formatAlt`, and all unrelated
 * settings.
 *
 * @param {ClockShellApi | null | undefined} shell
 * @param {ResolvedClockConfig} cfg
 * @param {string} nextWeekStartName
 * @param {PersistWeekStartOptions} [options]
 * @returns {PersistOutcome}
 */
export function persistWeekStart(shell, cfg, nextWeekStartName, options) {
  const opts = options || {};
  const settingsKey = opts.settingsKey || "islands";
  const needsLegacyCleanup = cfg.nativeConfigured && cfg.hasLegacyWeekStart;
  const needsCoherentMutation = !cfg.nativeConfigured || !cfg.nativeEntryIsObject || needsLegacyCleanup;

  const mergedNative = mergeSettings(cfg.nativeSettings, opts.pendingNativeFields);
  const nextEntry = buildInlineClockEntryWithFields(mergedNative, { weekStartDay: nextWeekStartName });

  if (!needsCoherentMutation) {
    const currentEntry = buildInlineClockEntryWithFields(cfg.nativeSettings, {});
    if (canonicalJson(currentEntry) === canonicalJson(nextEntry)) {
      return { accepted: true, status: "unchanged", method: "none", durableConfirmed: false };
    }
    if (shell && typeof shell.updateEntryInline === "function") {
      const ok = shell.updateEntryInline("omarchy.clock", nextEntry) === true;
      return {
        accepted: ok,
        status: ok ? "persisted" : "rejected",
        method: "updateEntryInline",
        durableConfirmed: false
      };
    }
  }

  if (shell && typeof shell.mutateShellConfig === "function") {
    const ok =
      shell.mutateShellConfig(function (config) {
        applyWeekStartMutation(config, settingsKey, nextWeekStartName, opts.pendingNativeFields);
      }) === true;
    return {
      accepted: ok,
      status: ok ? "persisted" : "rejected",
      method: "mutateShellConfig",
      durableConfirmed: false
    };
  }

  return { accepted: false, status: "unavailable", method: "none", durableConfirmed: false };
}

/**
 * @typedef {{
 *   _localClockFormat: string,
 *   _localCustomClockFormats: readonly string[] | null,
 *   _localWeekStartDay: string,
 *   readonly clockFormat: string,
 *   readonly effectiveWeekStart: number
 * }} ClockBarState
 */

/**
 * Production orchestration helper used directly by `Bar.cycleClockFormat()`.
 * Advances the active format through the ring, applies optimistic state,
 * persists via `persistClockFormat`, and reconciles or reverts on rejection.
 *
 * @param {ClockBarState} state
 * @param {ClockShellApi | null | undefined} shell
 * @param {ResolvedClockConfig} cfg
 * @param {string} [settingsKey]
 * @returns {PersistOutcome}
 */
export function cycleClockFormatAction(state, shell, cfg, settingsKey) {
  const current = state.clockFormat;
  const activeCustom =
    state._localCustomClockFormats !== null ? state._localCustomClockFormats : cfg.customFormats;
  const ring = formatRing(current, cfg.formatAlt, NATIVE_HORIZONTAL_FORMATS, activeCustom);
  const next = nextFormat(ring, current);
  if (next === "" || next === current) {
    return { accepted: true, status: "unchanged", method: "none", durableConfirmed: false };
  }

  const nextCustom = retainCustomFormat(activeCustom, current, cfg.formatAlt);
  const prevLocalFormat = state._localClockFormat;
  const prevLocalCustom = state._localCustomClockFormats;
  const pendingNative = state._localWeekStartDay !== "" ? { weekStartDay: state._localWeekStartDay } : null;

  state._localClockFormat = next;
  state._localCustomClockFormats = nextCustom;

  const outcome = persistClockFormat(shell, cfg, next, {
    settingsKey: settingsKey || "islands",
    currentFormat: current,
    pendingNativeFields: pendingNative,
    pendingCustomFormats: activeCustom
  });
  if (!outcome.accepted) {
    state._localClockFormat = prevLocalFormat;
    state._localCustomClockFormats = prevLocalCustom;
  } else if (outcome.status === "unchanged") {
    state._localClockFormat = "";
    state._localCustomClockFormats = null;
  }
  return outcome;
}

/**
 * Production orchestration helper used directly by `Bar.toggleWeekStart()`.
 * Toggles Monday/Sunday using Omarchy's native semantics, applies optimistic
 * state, persists via `persistWeekStart`, and reconciles or reverts on rejection.
 *
 * @param {ClockBarState} state
 * @param {ClockShellApi | null | undefined} shell
 * @param {ResolvedClockConfig} cfg
 * @param {string} [settingsKey]
 * @returns {PersistOutcome}
 */
export function toggleWeekStartAction(state, shell, cfg, settingsKey) {
  const nextIndex = toggledWeekStart(state.effectiveWeekStart);
  const nextName = weekStartSettingName(nextIndex);
  const prevLocalWeekStart = state._localWeekStartDay;
  const pendingNative = state._localClockFormat !== "" ? { format: state._localClockFormat } : null;

  state._localWeekStartDay = nextName;
  const outcome = persistWeekStart(shell, cfg, nextName, {
    settingsKey: settingsKey || "islands",
    pendingNativeFields: pendingNative
  });
  if (!outcome.accepted) {
    state._localWeekStartDay = prevLocalWeekStart;
  } else if (outcome.status === "unchanged") {
    state._localWeekStartDay = "";
  }
  return outcome;
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
