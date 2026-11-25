import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./qmljs.mjs";

const C = load("logic/Calendar.js");
const CF = load("logic/ClockFormat.js");
const M = load("logic/Media.js");
const plain = (value) => JSON.parse(JSON.stringify(value));
const day = (year, month, d) => ({ year, month, day: d });

test("locale setting resolves to the design's tags, or the Omarchy language", () => {
  assert.equal(C.resolveLocale("en", "da-DK"), "en-GB");
  assert.equal(C.resolveLocale("es", ""), "es-ES");
  assert.equal(C.resolveLocale("ja", ""), "ja-JP");
  assert.equal(C.resolveLocale("auto", "pt-BR"), "pt-BR");
  assert.equal(C.resolveLocale("auto", "../../etc"), "en-GB");
});

test("QML's first day of week (0 = Sunday) is used as is", () => {
  assert.equal(C.weekStartFromLocale(1), 1); // Monday (en-GB, es-ES)
  assert.equal(C.weekStartFromLocale(0), 0); // Sunday (ja-JP, en-US)
  assert.equal(C.weekStartFromLocale(6), 6); // Saturday
  assert.equal(C.weekStartFromLocale(7), 0); // C++ Qt::Sunday
  assert.equal(C.weekStartFromLocale(undefined), 1);
  assert.equal(C.weekStartFromLocale(2.5), 1);
  assert.deepEqual(plain(C.weekdayOrder(0)), [0, 1, 2, 3, 4, 5, 6]);
  assert.deepEqual(plain(C.weekdayOrder(1)), [1, 2, 3, 4, 5, 6, 0]);
});

test("October 2026 grid: six weeks, leading days from September", () => {
  // 1 October 2026 is a Thursday.
  const monday = plain(C.monthGrid(2026, 9, 1, day(2026, 9, 28), day(2026, 9, 28)));
  assert.equal(monday.length, 42);
  assert.deepEqual(monday.slice(0, 4).map((c) => [c.month, c.day, c.outside]), [[8, 28, true], [8, 29, true], [8, 30, true], [9, 1, false]]);
  const sunday = plain(C.monthGrid(2026, 9, 0, null, null));
  assert.equal(sunday[4].day, 1);
  assert.equal(sunday[3].day, 30);
  const today = monday.filter((c) => c.today);
  assert.equal(today.length, 1);
  assert.equal(today[0].day, 28);
  assert.ok(today[0].selected);
  assert.deepEqual(monday.at(-1), { year: 2026, month: 10, day: 8, key: 20261108, outside: true, today: false, selected: false });
});

test("a month that fills exactly four weeks still shows six", () => {
  // February 2027 starts on a Monday and has 28 days.
  const grid = plain(C.monthGrid(2027, 1, 1, null, null));
  assert.equal(grid.length, 42);
  assert.equal(grid[0].day, 1);
  assert.equal(grid.filter((c) => !c.outside).length, 28);
});

test("keyboard movement across months and years", () => {
  const today = day(2026, 9, 28);
  assert.deepEqual(plain(C.move(day(2026, 9, 1), today, "left")), day(2026, 8, 30));
  assert.deepEqual(plain(C.move(day(2026, 11, 31), today, "right")), day(2027, 0, 1));
  assert.deepEqual(plain(C.move(day(2026, 9, 28), today, "down")), day(2026, 10, 4));
  assert.deepEqual(plain(C.move(day(2026, 0, 31), today, "nextMonth")), day(2026, 1, 28));
  assert.deepEqual(plain(C.move(day(2024, 2, 31), today, "previousMonth")), day(2024, 1, 29));
  assert.deepEqual(plain(C.move(day(2030, 5, 5), today, "today")), today);
  assert.deepEqual(plain(C.move(day(2026, 9, 5), today, "nonsense")), day(2026, 9, 5));
});

test("date patterns follow the design per language", () => {
  assert.equal(C.patterns("en-GB").longDate, "d MMMM");
  assert.equal(C.patterns("es-ES").monthTitle, "MMMM 'de' yyyy");
  assert.equal(C.patterns("ja-JP").monthTitle, "yyyy年M月");
  assert.equal(C.patterns("ja-JP").weekdayFormat, "short");
  assert.equal(C.patterns("da-DK").longDate, "d MMMM");
  assert.equal(C.patterns("ja-JP").shortDate, "M月d日");
  assert.equal(C.patterns("en-GB").shortDate, "d MMM");
});

const player = (fields) => ({ isPlaying: false, trackTitle: "", trackArtist: "", ...fields });

test("media state: unavailable, empty, playing, paused", () => {
  assert.equal(M.state(null, null), "unavailable");
  assert.equal(M.state({}, null), "empty");
  assert.equal(M.state({}, player({})), "empty");
  assert.equal(M.state({}, player({ trackTitle: "Slow Tide", isPlaying: true })), "playing");
  assert.equal(M.state({}, player({ trackArtist: "Hikari Ensemble" })), "paused");
});

test("track description falls back to the artist and stays plain", () => {
  assert.deepEqual(plain(M.describe(player({ trackTitle: " Slow\nTide ", trackArtist: "Hikari", canGoNext: true, canTogglePlaying: true }))),
    { title: "Slow Tide", artist: "Hikari", canPrevious: false, canNext: true, canPlayPause: true });
  assert.equal(M.describe(player({ trackArtist: "Only Artist" })).title, "Only Artist");
  assert.equal(M.describe(player({ trackArtist: "Only Artist" })).artist, "");
  assert.equal(M.describe(player({ trackTitle: "x".repeat(500) })).title.length, 200);
  assert.equal(M.describe(player({ trackTitle: "<b>x</b>" })).title, "<b>x</b>");
  assert.deepEqual(plain(M.describe(null)), { title: "", artist: "", canPrevious: false, canNext: false, canPlayPause: false });
});

test("progress is bounded and -1 when unknown", () => {
  assert.equal(M.progress(player({ position: 30, length: 120 })), 0.25);
  assert.equal(M.progress(player({ position: 500, length: 120 })), 1);
  assert.equal(M.progress(player({ position: 10, length: 0 })), -1);
  assert.equal(M.progress(player({ position: 10, length: 100, positionSupported: false })), -1);
  assert.equal(M.progress(null), -1);
});

test("clock format splitTimeText, withSeconds and stableDigits keep tick measurements invariant", () => {
  assert.deepEqual(plain(CF.splitTimeText("15:55", "15:55:42")), { prefix: "15:55", seconds: ":42", suffix: "", expandable: true });
  assert.deepEqual(plain(CF.splitTimeText("15:55", "15:55:55")), { prefix: "15:55", seconds: ":55", suffix: "", expandable: true });
  assert.deepEqual(plain(CF.splitTimeText("3:55 PM", "3:55:42 PM")), { prefix: "3:55", seconds: ":42", suffix: " PM", expandable: true });
  assert.deepEqual(plain(CF.splitTimeText("3:55 PM", "3:55:55 PM")), { prefix: "3:55", seconds: ":55", suffix: " PM", expandable: true });
  assert.deepEqual(plain(CF.splitTimeText("午後 3:55", "午後 3:55:42")), { prefix: "午後 3:55", seconds: ":42", suffix: "", expandable: true });
  assert.deepEqual(plain(CF.splitTimeText("15:55:42", "15:55:42")), { prefix: "15:55:42", seconds: "", suffix: "", expandable: false });
  assert.deepEqual(plain(CF.splitTimeText("15", "15")), { prefix: "15", seconds: "", suffix: "", expandable: false });
  assert.equal(CF.withSeconds("HH:mm"), "HH:mm:ss");
  assert.equal(CF.withSeconds("h:mm AP"), "h:mm:ss AP");
  assert.equal(CF.withSeconds("HH:mm:ss"), "HH:mm:ss");
  assert.equal(CF.withSeconds("HH"), "HH");
  assert.equal(CF.stableDigits("09:05"), "88:88");
  assert.equal(CF.stableDigits("09:05:00"), CF.stableDigits("09:05:59"));
  assert.equal(CF.stableDigits("9:05:01 AM"), CF.stableDigits("9:05:49 AM"));
  assert.equal(CF.stableDigits(""), "");
});
