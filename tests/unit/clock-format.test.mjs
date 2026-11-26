import { test } from "node:test";
import assert from "node:assert/strict";
import * as ClockFormat from "../../plugin/logic/ClockFormat.mjs";

const EXPECTED_NATIVE_PRESETS = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "dddd HH:mm:ss",
  "dddd h:mm:ss AP",
  "HH:mm",
  "h:mm AP",
  "ddd d MMM HH:mm",
  "ddd d MMM h:mm AP",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm",
];

test("native horizontal preset ring matches Omarchy 4.5.0-3 order verbatim", () => {
  assert.deepEqual(ClockFormat.NATIVE_HORIZONTAL_FORMATS, EXPECTED_NATIVE_PRESETS);
  assert.deepEqual(ClockFormat.formatRing("dddd HH:mm", "d MMMM 'W'ww yyyy"), EXPECTED_NATIVE_PRESETS);
});

test("formatRing preserves custom configured and alternate formats, deduplicates, and rejects empty entries", () => {
  const ring = ClockFormat.formatRing("HH:mm 'UTC'", "yyyy 'W'ww", EXPECTED_NATIVE_PRESETS);
  assert.equal(ring.length, EXPECTED_NATIVE_PRESETS.length + 2);
  assert.deepEqual(ring.slice(0, EXPECTED_NATIVE_PRESETS.length), EXPECTED_NATIVE_PRESETS);
  assert.equal(ring[EXPECTED_NATIVE_PRESETS.length], "yyyy 'W'ww");
  assert.equal(ring[EXPECTED_NATIVE_PRESETS.length + 1], "HH:mm 'UTC'");

  // Duplicates and empty/null/undefined entries are filtered cleanly.
  const deduped = ClockFormat.formatRing("HH:mm", "", ["", null, "HH:mm", undefined, "h:mm AP", "HH:mm"]);
  assert.deepEqual(deduped, ["HH:mm", "h:mm AP"]);

  // All-empty candidates fall back to DEFAULT_FORMAT.
  assert.deepEqual(ClockFormat.formatRing("", "", ["", null, undefined]), [ClockFormat.DEFAULT_FORMAT]);
});

test("nextFormat cycles every entry, wraps around, and handles unknown or empty inputs", () => {
  const ring = ClockFormat.formatRing("HH:mm 'UTC'", "yyyy 'W'ww");
  let current = ring[0] ?? "";
  /** @type {string[]} */
  const visited = [current];
  for (let i = 0; i < ring.length; i++) {
    current = ClockFormat.nextFormat(ring, current);
    visited.push(current);
  }
  assert.equal(visited.length, ring.length + 1);
  assert.deepEqual(visited.slice(0, ring.length), ring);
  assert.equal(visited[ring.length], ring[0], "wraps back to the first preset");

  assert.equal(ClockFormat.nextFormat(ring, "custom-not-in-ring"), ring[0], "unknown format starts at top");
  assert.equal(ClockFormat.nextFormat([], "HH:mm"), "", "empty ring yields empty string");
});

test("quoted literals do not trigger seconds, date/weekday, or minute insertion", () => {
  assert.equal(ClockFormat.stripQuotedLiterals("'Sat' HH:mm"), " HH:mm");
  assert.equal(ClockFormat.stripQuotedLiterals("'W'ww"), "ww");
  assert.equal(ClockFormat.stripQuotedLiterals("HH:mm 'unclosed s d M y"), "HH:mm ");

  assert.equal(ClockFormat.hasSecondsToken("'Sat' HH:mm"), false);
  assert.equal(ClockFormat.hasSecondsToken("'sec' HH:mm"), false);
  assert.equal(ClockFormat.hasSecondsToken("HH:mm 's'"), false);
  assert.equal(ClockFormat.hasSecondsToken("HH:mm 'unclosed s"), false);
  assert.equal(ClockFormat.hasSecondsToken("HH:mm:ss"), true);
  assert.equal(ClockFormat.hasSecondsToken("dddd h:mm:ss AP"), true);

  assert.equal(ClockFormat.hasDateOrWeekdayToken("HH:mm"), false);
  assert.equal(ClockFormat.hasDateOrWeekdayToken("h:mm AP"), false);
  assert.equal(ClockFormat.hasDateOrWeekdayToken("'Wed' HH:mm"), false);
  assert.equal(ClockFormat.hasDateOrWeekdayToken("'May' HH:mm"), false);
  assert.equal(ClockFormat.hasDateOrWeekdayToken("dddd HH:mm"), true);
  assert.equal(ClockFormat.hasDateOrWeekdayToken("ddd d MMM HH:mm"), true);
  assert.equal(ClockFormat.hasDateOrWeekdayToken("d MMMM 'W'ww yyyy"), true);
  assert.equal(ClockFormat.hasDateOrWeekdayToken("yyyy-MM-dd HH:mm"), true);
  assert.equal(ClockFormat.hasDateOrWeekdayToken("'W'ww"), true);

  assert.equal(ClockFormat.withSeconds("'Sat' HH:mm"), "'Sat' HH:mm:ss");
  assert.equal(ClockFormat.withSeconds("'mm' HH"), "'mm' HH");
  assert.equal(ClockFormat.withSeconds("'mm' HH:mm"), "'mm' HH:mm:ss");
  assert.equal(ClockFormat.withSeconds("d MMMM 'W'ww yyyy"), "d MMMM 'W'ww yyyy");
  assert.equal(ClockFormat.withSeconds("dddd HH:mm"), "dddd HH:mm:ss");
  assert.equal(ClockFormat.withSeconds("dddd h:mm AP"), "dddd h:mm:ss AP");
  assert.equal(ClockFormat.withSeconds("dddd HH:mm:ss"), "dddd HH:mm:ss");
  assert.equal(ClockFormat.withSeconds("yyyy-MM-dd HH:mm"), "yyyy-MM-dd HH:mm:ss");
});

test("partsFor suppresses supplementary date/weekday whenever format already includes them", () => {
  for (const fmt of ["HH:mm", "h:mm AP", "HH:mm:ss", "'UTC' HH:mm", "HH"]) {
    assert.deepEqual(ClockFormat.partsFor("full", fmt), { date: true, weekday: true }, fmt);
    assert.deepEqual(ClockFormat.partsFor("compact", fmt), { date: true, weekday: false }, fmt);
    assert.deepEqual(ClockFormat.partsFor("minimal", fmt), { date: false, weekday: false }, fmt);
  }
  for (const fmt of [
    "dddd HH:mm",
    "dddd h:mm AP",
    "dddd HH:mm:ss",
    "dddd h:mm:ss AP",
    "ddd d MMM HH:mm",
    "ddd d MMM h:mm AP",
    "d MMMM 'W'ww yyyy",
    "yyyy-MM-dd HH:mm",
    "yyyy-MM-dd",
  ]) {
    assert.deepEqual(ClockFormat.partsFor("full", fmt), { date: false, weekday: false }, fmt);
    assert.deepEqual(ClockFormat.partsFor("compact", fmt), { date: false, weekday: false }, fmt);
    assert.deepEqual(ClockFormat.partsFor("minimal", fmt), { date: false, weekday: false }, fmt);
  }
});

test("ISO week calculation and token expansion handle year boundaries, digit localization, and quoted literals", () => {
  assert.equal(ClockFormat.isoWeekLiteral(2026, 9, 28), "44");
  assert.equal(ClockFormat.isoWeekLiteral(2026, 0, 1), "01");
  assert.equal(ClockFormat.isoWeekLiteral(2025, 11, 29), "01");
  assert.equal(ClockFormat.isoWeekLiteral(2020, 11, 31), "53");
  assert.equal(ClockFormat.isoWeekLiteral(2023, 0, 1), "52");

  const oct28 = new Date(2026, 9, 28, 9, 5, 42);
  assert.equal(ClockFormat.expandIsoWeek("d MMMM 'W'ww yyyy", oct28), "d MMMM 'W'44 yyyy");
  assert.equal(ClockFormat.expandIsoWeek("'www' 'W'ww", oct28), "'www' 'W'44");
  assert.equal(ClockFormat.expandIsoWeek("HH:mm", oct28), "HH:mm");

  /** @type {Record<string, string>} */
  const arabicDigits = { "0": "٠", "1": "١", "2": "٢", "3": "٣", "4": "٤", "5": "٥", "6": "٦", "7": "٧", "8": "٨", "9": "٩" };
  assert.equal(
    ClockFormat.expandIsoWeek("d MMMM 'W'ww yyyy", oct28, (d) => arabicDigits[d] ?? d),
    "d MMMM 'W'٤٤ yyyy"
  );
});

test("resolveClockConfig and buildInlineClockEntry preserve native settings, legacy overrides, and unrelated keys", () => {
  // 1. Standard Omarchy config: reads omarchy.clock.format and formatAlt.
  const nativeOnly = ClockFormat.resolveClockConfig({
    layout: {
      center: [{ id: "omarchy.clock", format: "dddd HH:mm", formatAlt: "yyyy 'W'ww", weekStartDay: "monday", birthYear: 1990 }],
    },
    islands: { density: "comfortable" },
  }, "islands");
  assert.equal(nativeOnly.nativeConfigured, true);
  assert.equal(nativeOnly.format, "dddd HH:mm");
  assert.equal(nativeOnly.formatAlt, "yyyy 'W'ww");
  assert.equal(nativeOnly.hasLegacyOverride, false);
  assert.ok(nativeOnly.ring.includes("yyyy 'W'ww"));

  const updatedEntry = ClockFormat.buildInlineClockEntry(nativeOnly.nativeSettings, "dddd h:mm AP");
  assert.deepEqual(updatedEntry, {
    id: "omarchy.clock",
    format: "dddd h:mm AP",
    formatAlt: "yyyy 'W'ww",
    weekStartDay: "monday",
    birthYear: 1990,
  });

  // 2. Legacy bar.islands.timeFormat override takes read priority until cycled.
  const withLegacy = ClockFormat.resolveClockConfig({
    layout: {
      center: [{ id: "omarchy.clock", format: "dddd HH:mm" }],
    },
    islands: { timeFormat: "HH:mm 'UTC'" },
  }, "islands");
  assert.equal(withLegacy.nativeConfigured, true);
  assert.equal(withLegacy.format, "HH:mm 'UTC'");
  assert.equal(withLegacy.nativeFormat, "dddd HH:mm");
  assert.equal(withLegacy.hasLegacyOverride, true);
  assert.ok(withLegacy.ring.includes("HH:mm 'UTC'"));

  // 3. String entry in bar.layout marks nativeConfigured without a stored format.
  const stringEntry = ClockFormat.resolveClockConfig({
    layout: { center: ["omarchy.clock"] },
  }, "islands");
  assert.equal(stringEntry.nativeConfigured, true);
  assert.equal(stringEntry.format, ClockFormat.DEFAULT_FORMAT);

  // 4. Absent omarchy.clock entry falls back cleanly.
  const absent = ClockFormat.resolveClockConfig({ islands: {} }, "islands");
  assert.equal(absent.nativeConfigured, false);
  assert.equal(absent.format, ClockFormat.DEFAULT_FORMAT);
  assert.equal(absent.formatAlt, ClockFormat.DEFAULT_ALT_FORMAT);
});

test("F4: valid custom formats longer than 64 characters are preserved while control chars and blanks are rejected", () => {
  const longFormat = "dddd', 'd' of 'MMMM' 'yyyy' — Week ''W'ww' — Local Time 'HH:mm:ss' (UTC+00:00)'";
  const longAlt = "'Archive Calendar Snapshot: 'dddd d MMMM yyyy 'ISO-W'ww 'at' h:mm:ss AP";
  assert.ok(longFormat.length > 64, `expected >64 chars, got ${longFormat.length}`);
  assert.ok(longAlt.length > 64, `expected >64 chars, got ${longAlt.length}`);

  const resolved = ClockFormat.resolveClockConfig({
    layout: { center: [{ id: "omarchy.clock", format: longFormat, formatAlt: longAlt }] },
  }, "islands");
  assert.equal(resolved.format, longFormat);
  assert.equal(resolved.formatAlt, longAlt);
  assert.ok(resolved.ring.includes(longFormat));
  assert.ok(resolved.ring.includes(longAlt));

  // Invalid inputs (blank, control chars, non-strings) still rejected cleanly.
  assert.equal(ClockFormat.validFormatString(""), "");
  assert.equal(ClockFormat.validFormatString("   "), "");
  assert.equal(ClockFormat.validFormatString("HH:mm\n"), "");
  assert.equal(ClockFormat.validFormatString("HH:mm\u0000"), "");
  assert.equal(ClockFormat.validFormatString(42), "");
});

test("F6: custom format retention deduplicates, bounds growth, excludes presets, and preserves formatAlt", () => {
  assert.deepEqual(ClockFormat.retainCustomFormat([], "HH:mm", "yyyy 'W'ww"), [], "native preset not retained");
  assert.deepEqual(ClockFormat.retainCustomFormat([], "yyyy 'W'ww", "yyyy 'W'ww"), [], "formatAlt not duplicated");

  let retained = ClockFormat.retainCustomFormat([], "HH:mm 'UTC'", "yyyy 'W'ww");
  assert.deepEqual(retained, ["HH:mm 'UTC'"]);
  retained = ClockFormat.retainCustomFormat(retained, "HH:mm 'UTC'", "yyyy 'W'ww");
  assert.deepEqual(retained, ["HH:mm 'UTC'"], "deduplicated");

  // Bounded to MAX_CUSTOM_FORMATS (8), keeping most recent entries.
  for (let i = 1; i <= 12; i++) {
    retained = ClockFormat.retainCustomFormat(retained, `HH:mm 'TZ${i}'`, "yyyy 'W'ww");
  }
  assert.equal(retained.length, ClockFormat.MAX_CUSTOM_FORMATS);
  assert.equal(retained[retained.length - 1], "HH:mm 'TZ12'");
  assert.equal(retained[0], "HH:mm 'TZ5'");
});

test("F7: weekStartDay normalization, toggling, and persistence match Omarchy semantics", () => {
  assert.equal(ClockFormat.coerceWeekStart(null), null);
  assert.equal(ClockFormat.coerceWeekStart(""), null);
  assert.equal(ClockFormat.coerceWeekStart("monday"), 1);
  assert.equal(ClockFormat.coerceWeekStart("MON"), 1);
  assert.equal(ClockFormat.coerceWeekStart("sun"), 0);
  assert.equal(ClockFormat.coerceWeekStart("saturday"), 6);
  assert.equal(ClockFormat.coerceWeekStart(7), 0);
  assert.equal(ClockFormat.coerceWeekStart(-1), 6);
  assert.equal(ClockFormat.coerceWeekStart("bogus"), null);

  assert.equal(ClockFormat.normalizedWeekStart(null, 0), 0, "falls back to locale Sunday");
  assert.equal(ClockFormat.normalizedWeekStart("invalid", 1), 1, "falls back to locale Monday");
  assert.equal(ClockFormat.normalizedWeekStart("saturday", 0), 6, "explicit overrides locale");

  assert.equal(ClockFormat.toggledWeekStart(1), 0, "Monday toggles to Sunday");
  assert.equal(ClockFormat.toggledWeekStart(0), 1, "Sunday toggles to Monday");
  assert.equal(ClockFormat.toggledWeekStart(6), 1, "Saturday toggles to Monday");
  assert.equal(ClockFormat.weekStartSettingName(0), "sunday");
  assert.equal(ClockFormat.weekStartSettingName(1), "monday");
});

test("F1-F2: persistClockFormat and persistWeekStart distinguish unchanged vs rejected and mark durableConfirmed false", () => {
  const cfg = ClockFormat.resolveClockConfig({
    layout: { center: [{ id: "omarchy.clock", format: "HH:mm", weekStartDay: "monday" }] },
  }, "islands");

  // Unchanged native entry: returns accepted + unchanged without calling shell.
  let inlineCalls = 0;
  let mutateCalls = 0;
  const spyShell = {
    updateEntryInline: () => { inlineCalls++; return false; },
    mutateShellConfig: () => { mutateCalls++; return false; },
  };
  const unchanged = ClockFormat.persistClockFormat(spyShell, cfg, "HH:mm");
  assert.equal(unchanged.accepted, true);
  assert.equal(unchanged.status, "unchanged");
  assert.equal(unchanged.method, "none");
  assert.equal(unchanged.durableConfirmed, false);
  assert.equal(inlineCalls, 0);
  assert.equal(mutateCalls, 0);

  // Changed entry rejected by shell: classified as rejected, not unchanged.
  const rejected = ClockFormat.persistClockFormat(spyShell, cfg, "h:mm AP");
  assert.equal(rejected.accepted, false);
  assert.equal(rejected.status, "rejected");
  assert.equal(rejected.method, "updateEntryInline");
  assert.equal(rejected.durableConfirmed, false);
  assert.equal(inlineCalls, 1);

  // Unchanged weekStartDay returns unchanged; changed + rejected returns rejected.
  const wsUnchanged = ClockFormat.persistWeekStart(spyShell, cfg, "monday");
  assert.equal(wsUnchanged.accepted, true);
  assert.equal(wsUnchanged.status, "unchanged");
  const wsRejected = ClockFormat.persistWeekStart(spyShell, cfg, "sunday");
  assert.equal(wsRejected.accepted, false);
  assert.equal(wsRejected.status, "rejected");
});

test("pending-state persistence compares against accepted pending fields before barConfig reload", () => {
  const staleCfg = ClockFormat.resolveClockConfig({
    layout: { center: [{ id: "omarchy.clock", format: "HH:mm", weekStartDay: "monday" }] },
  }, "islands");

  /** @type {Record<string, unknown>} */
  let stored = { id: "omarchy.clock", format: "HH:mm", weekStartDay: "monday" };
  let rejectNext = false;
  let inlineCalls = 0;
  const shell = {
    /**
     * @param {string} _id
     * @param {Record<string, unknown>} entry
     */
    updateEntryInline: (_id, entry) => {
      inlineCalls++;
      if (rejectNext) return false;
      stored = { ...entry };
      return true;
    },
  };

  const state = {
    _localClockFormat: "",
    _localCustomClockFormats: /** @type {readonly string[] | null} */ (null),
    _localWeekStartDay: "",
    get clockFormat() {
      return this._localClockFormat !== "" ? this._localClockFormat : staleCfg.format;
    },
    get effectiveWeekStart() {
      const raw = this._localWeekStartDay !== "" ? this._localWeekStartDay : staleCfg.weekStartDay;
      return ClockFormat.normalizedWeekStart(raw, 1);
    },
  };

  // Toggle week start twice without reloading staleCfg.
  const ws1 = ClockFormat.toggleWeekStartAction(state, shell, staleCfg, "islands");
  assert.equal(ws1.status, "persisted");
  assert.equal(stored.weekStartDay, "sunday");

  const ws2 = ClockFormat.toggleWeekStartAction(state, shell, staleCfg, "islands");
  assert.equal(ws2.status, "persisted");
  assert.equal(ws2.method, "updateEntryInline");
  assert.equal(stored.weekStartDay, "monday");

  // Cycle full ring back to "HH:mm" without reloading staleCfg.
  for (let i = 0; i < staleCfg.ring.length; i++) {
    const out = ClockFormat.cycleClockFormatAction(state, shell, staleCfg, "islands");
    assert.equal(out.accepted, true);
    assert.equal(out.status, "persisted");
  }
  assert.equal(state.clockFormat, "HH:mm");
  assert.equal(stored.format, "HH:mm");
  assert.equal(inlineCalls, 2 + staleCfg.ring.length);

  // Rejection after a prior accepted pending write rolls back to the prior accepted state.
  const firstStep = ClockFormat.cycleClockFormatAction(state, shell, staleCfg, "islands");
  assert.equal(firstStep.status, "persisted");
  assert.equal(state.clockFormat, "h:mm AP");
  rejectNext = true;
  const rejectedStep = ClockFormat.cycleClockFormatAction(state, shell, staleCfg, "islands");
  assert.equal(rejectedStep.accepted, false);
  assert.equal(rejectedStep.status, "rejected");
  assert.equal(state.clockFormat, "h:mm AP");
});
