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
