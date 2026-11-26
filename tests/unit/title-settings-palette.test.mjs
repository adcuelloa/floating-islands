import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./qmljs.mjs";
import { readFileSync } from "node:fs";
import * as Clock from "../../plugin/logic/ClockFormat.mjs";

const Title = load("logic/Title.js");
const Settings = load("logic/Settings.js");
const Palette = load("theme/Palette.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

test("titles are flattened, trimmed, bounded, and fall back to the app id", () => {
  assert.equal(Title.displayTitle("  nvim\n— file.qml\t ", "kitty"), "nvim — file.qml");
  assert.equal(Title.displayTitle("", "org.gnome.Nautilus"), "org.gnome.Nautilus");
  assert.equal(Title.displayTitle("x".repeat(2000), "").length, 512);
  // Markup-shaped titles stay literal text (the label is Text.PlainText too).
  assert.equal(Title.displayTitle('<img src="https://example.invalid/t">', ""), '<img src="https://example.invalid/t">');
});

test("app kinds pick the design's icons", () => {
  assert.equal(Title.appKind("Alacritty"), "terminal");
  assert.equal(Title.appKind("com.mitchellh.ghostty"), "terminal");
  assert.equal(Title.appKind("brave-browser"), "browser");
  assert.equal(Title.appKind("chromium"), "browser");
  assert.equal(Title.appKind("code"), "code");
  assert.equal(Title.appKind("obsidian"), "note");
  assert.equal(Title.appKind("org.gnome.Nautilus"), "window");
  assert.equal(Title.appKind(""), "window");
});

test("settings fall back to defaults on missing or malformed values", () => {
  assert.deepEqual(plain(Settings.read({}, "islands")), {
    density: "compact", tier: "auto", timeFormat: "HH:mm", showTitle: true, hostWidgets: true, hosted: null, extraHosted: [], trialInstance: "",
    locale: "auto", showMedia: true, mediaEqualizer: "animated", launcherIcon: "omarchy", titleIcon: "app", controlCenter: false,
  });
  assert.equal(Settings.read({ islands: { controlCenter: true } }, "islands").controlCenter, true);
  assert.equal(Settings.read({ islands: { controlCenter: "yes" } }, "islands").controlCenter, false, "only a real true turns it on");
  const read = plain(Settings.read({ islands: { density: "huge", tier: "minimal", timeFormat: "", showTitle: false, hosted: ["ok.id", "../x", 3, { id: "obj.id" }, "ok.id"] } }, "islands"));
  assert.equal(read.density, "compact");
  assert.equal(read.tier, "minimal");
  assert.equal(read.timeFormat, "HH:mm");
  assert.equal(read.showTitle, false);
  assert.deepEqual(read.hosted, ["ok.id", "obj.id"]);
  assert.equal(plain(Settings.read({ islands: [] }, "islands")).density, "compact");
});

test("hosted widgets come from the stock right section, minus natively drawn ones", () => {
  const barConfig = {
    layout: {
      left: [{ id: "omarchy.menu" }],
      right: [
        { id: "omarchy.tray" },
        { id: "omarchy.clock", format: "HH:mm" },
        { id: "vpn", type: "command", exec: "x" },
        { id: "user.audio", step: 5 },
        "omarchy.power",
      ],
      tray: [{ id: "omarchy.bluetooth" }],
    },
  };
  const entries = plain(Settings.hostedEntries(barConfig, Settings.read(barConfig, "islands")));
  assert.deepEqual(entries, [
    { id: "omarchy.tray", settings: {} },
    { id: "user.audio", settings: { step: 5 } },
    { id: "omarchy.power", settings: {} },
  ]);
  const picked = plain(Settings.hostedEntries(barConfig, Settings.read({ islands: { hosted: ["omarchy.bluetooth", "missing.id"] } }, "islands")));
  assert.deepEqual(picked, [{ id: "omarchy.bluetooth", settings: {} }]);
  assert.deepEqual(plain(Settings.hostedEntries(barConfig, Settings.read({ islands: { hostWidgets: false } }, "islands"))), []);
});

// The live layout's shape: World clock and weather sit in the centre, which
// this bar does not host unless asked.
const stockLayout = {
  layout: {
    left: ["omarchy.menu", "omarchy.workspaces"],
    centerBegin: ["omarchy.indicators"],
    center: [{ id: "omarchy.clock", format: "ddd d MMM h:mm AP" }],
    centerEnd: [{ id: "omarchy.elsewhen", cities: ["Tokyo"] }, "omarchy.media", "omarchy.weather", "omarchy.system-update"],
    right: ["omarchy.tray", "omarchy.keyboard-layout", "omarchy.bluetooth", "omarchy.network", "omarchy.audio", "omarchy.power"],
  },
};
const ids = (entries) => entries.map((entry) => entry.id);

test("extraHosted adds centre widgets after the right section without displacing it", () => {
  const right = stockLayout.layout.right;
  const plainEntries = plain(Settings.hostedEntries(stockLayout, Settings.read({}, "islands")));
  assert.deepEqual(ids(plainEntries), right, "default: the right section only");
  assert.deepEqual(plain(Settings.unnumberedIds(plainEntries)), []);

  const read = Settings.read({ islands: { extraHosted: ["omarchy.weather", "omarchy.elsewhen", "omarchy.weather", "../x"] } }, "islands");
  assert.deepEqual(plain(read.extraHosted), ["omarchy.weather", "omarchy.elsewhen"], "validated and deduplicated");
  const entries = plain(Settings.hostedEntries(stockLayout, read));
  assert.deepEqual(ids(entries), right.concat(["omarchy.weather", "omarchy.elsewhen"]));
  assert.deepEqual(entries.slice(0, right.length).map((entry) => entry.extra), right.map(() => undefined));
  assert.deepEqual(entries[right.length + 1], { id: "omarchy.elsewhen", settings: { cities: ["Tokyo"] }, extra: true }, "its own entry settings");
  assert.deepEqual(plain(Settings.unnumberedIds(entries)), ["omarchy.weather", "omarchy.elsewhen"]);
});

test("extraHosted skips natives, duplicates, unplaced ids and a disabled host", () => {
  const read = (extraHosted, more = {}) => Settings.read({ islands: Object.assign({ extraHosted }, more) }, "islands");
  // Already hosted: stays where it is and keeps its hotkey number.
  const dup = plain(Settings.hostedEntries(stockLayout, read(["omarchy.audio"])));
  assert.deepEqual(ids(dup), stockLayout.layout.right);
  assert.deepEqual(plain(Settings.unnumberedIds(dup)), []);
  // Drawn natively, or not in bar.layout (the shell would not grant it an API).
  assert.deepEqual(ids(plain(Settings.hostedEntries(stockLayout, read(["omarchy.clock", "omarchy.media", "user.missing"])))), stockLayout.layout.right);
  // Also adds to an explicit `hosted` list.
  assert.deepEqual(ids(plain(Settings.hostedEntries(stockLayout, read(["omarchy.weather"], { hosted: ["omarchy.power"] })))), ["omarchy.power", "omarchy.weather"]);
  assert.deepEqual(plain(Settings.hostedEntries(stockLayout, read(["omarchy.weather"], { hostWidgets: false }))), []);
  assert.deepEqual(plain(Settings.read({ islands: { extraHosted: "omarchy.weather" } }, "islands").extraHosted), []);
});

test("palette helpers", () => {
  const black = { r: 0, g: 0, b: 0, a: 1 };
  const white = { r: 1, g: 1, b: 1, a: 1 };
  assert.deepEqual(plain(Palette.mix(black, white, 0.5)), { r: 0.5, g: 0.5, b: 0.5, a: 1 });
  assert.equal(Math.round(Palette.contrast(black, white)), 21);
  const amber = { r: 232 / 255, g: 184 / 255, b: 104 / 255, a: 1 };
  const bg = { r: 23 / 255, g: 22 / 255, b: 20 / 255, a: 1 };
  const fg = { r: 239 / 255, g: 232 / 255, b: 220 / 255, a: 1 };
  assert.deepEqual(Palette.readableOn(amber, bg, fg), bg);
  const navy = { r: 0.05, g: 0.1, b: 0.3, a: 1 };
  assert.deepEqual(Palette.readableOn(navy, bg, fg), fg);
});

test("clock parts per tier", () => {
  assert.deepEqual(plain(Clock.partsFor("full")), { date: true, weekday: true });
  assert.deepEqual(plain(Clock.partsFor("compact")), { date: true, weekday: false });
  assert.deepEqual(plain(Clock.partsFor("minimal")), { date: false, weekday: false });
});

test("the detailed time adds seconds after the minutes, and keeps formats that cannot take them", () => {
  assert.equal(Clock.withSeconds("HH:mm"), "HH:mm:ss");
  assert.equal(Clock.withSeconds("h:mm AP"), "h:mm:ss AP");
  assert.equal(Clock.withSeconds("ddd d MMM h:mm ap"), "ddd d MMM h:mm:ss ap");
  assert.equal(Clock.withSeconds("HH:mm:ss"), "HH:mm:ss", "already has seconds");
  assert.equal(Clock.withSeconds("HH"), "HH", "no minutes to follow");
});

test("launcher and title icon styles", () => {
  const read = (islands) => plain(Settings.read({ islands }, "islands"));
  assert.equal(read({ launcherIcon: "grid" }).launcherIcon, "grid");
  assert.equal(read({ launcherIcon: "refresh" }).launcherIcon, "omarchy");
  assert.equal(read({ titleIcon: "symbol" }).titleIcon, "symbol");
  assert.equal(read({ titleIcon: 1 }).titleIcon, "app");
});

// The title island's app icon: the desktop entry's icon, resolved through
// the icon theme (Quickshell.iconPath, passed in), or "" for the fallback symbol.
test("app icons resolve through the desktop entry, else fall back", () => {
  const themed = { firefox: "image://icon/firefox", kitty: "image://icon/kitty" };
  const lookup = (name) => themed[name] || "";
  assert.equal(Title.appIconSource({ icon: "firefox" }, lookup), "image://icon/firefox");
  assert.equal(Title.appIconSource({ icon: "/opt/app/icon.png" }, lookup), "file:///opt/app/icon.png");
  assert.equal(Title.appIconSource({ icon: "file:///opt/app/icon.svg" }, lookup), "file:///opt/app/icon.svg");
  assert.equal(Title.appIconSource({ icon: "missing-icon" }, lookup), "", "not in the theme");
  assert.equal(Title.appIconSource({ icon: "" }, lookup), "");
  assert.equal(Title.appIconSource(null, lookup), "", "no desktop entry");
  assert.equal(Title.appIconSource({ icon: "javascript:alert(1)" }, lookup), "", "only names, paths and file URLs");
});

// Failure text (theme.dangerText) is the theme's urgent colour moved toward
// its foreground only as far as 4.5:1 needs, on every surface it is drawn
// on: the Control Center card, a tile on the card, and a hovered tile.
// The palettes are the installed Omarchy themes plus the active custom one
// (fixtures/omarchy-themes.json, read the way Commons.Color reads colors.toml).
test("failure text is readable in every theme", () => {
  const themes = JSON.parse(readFileSync(new URL("./fixtures/omarchy-themes.json", import.meta.url), "utf8"));
  const hex = (s) => ({ r: parseInt(s.slice(1, 3), 16) / 255, g: parseInt(s.slice(3, 5), 16) / 255, b: parseInt(s.slice(5, 7), 16) / 255, a: 1 });
  let moved = 0;
  for (const [name, t] of Object.entries(themes)) {
    const fg = hex(t.foreground), bg = hex(t.background), urgent = hex(t.urgent);
    // As Theme.qml builds them (no theme ships shell.toml, so the bar and
    // card backgrounds are the theme background).
    const surface = Palette.mix(bg, fg, 0.045);
    const grounds = [bg, surface, Palette.mix(bg, fg, 0.08)];
    const text = Palette.readable(urgent, fg, grounds);
    for (const g of grounds) assert.ok(Palette.contrast(text, g) >= 4.5, `${name}: ${Palette.contrast(text, g).toFixed(2)}:1`);
    const already = grounds.every((g) => Palette.contrast(urgent, g) >= 4.5);
    if (already) assert.deepEqual(plain(text), plain(urgent), `${name}: a readable urgent colour is kept`);
    else moved++;
    assert.notDeepEqual(plain(text), plain(fg), `${name}: failure stays distinct from ordinary text`);
  }
  assert.ok(moved > 0, "some installed themes need the correction");
});

test("readable() edge cases", () => {
  const black = { r: 0, g: 0, b: 0, a: 1 }, white = { r: 1, g: 1, b: 1, a: 1 };
  const grey = { r: 0.5, g: 0.5, b: 0.5, a: 1 };
  assert.deepEqual(plain(Palette.readable(white, white, [black])), plain(white), "already readable");
  // Even the foreground cannot reach 4.5:1: the foreground is the best it can do.
  assert.deepEqual(plain(Palette.readable(grey, grey, [grey])), plain(grey));
});

// Secondary text (theme.secondaryText) is the theme's muted colour made
// readable the same way, on the same three surfaces, and stays weaker than
// ordinary text so the hierarchy holds.
test("secondary text is readable and below ordinary text in every theme", () => {
  const themes = JSON.parse(readFileSync(new URL("./fixtures/omarchy-themes.json", import.meta.url), "utf8"));
  const hex = (s) => ({ r: parseInt(s.slice(1, 3), 16) / 255, g: parseInt(s.slice(3, 5), 16) / 255, b: parseInt(s.slice(5, 7), 16) / 255, a: 1 });
  for (const [name, t] of Object.entries(themes)) {
    const fg = hex(t.foreground), bg = hex(t.background), muted = hex(t.muted);
    const grounds = [bg, Palette.mix(bg, fg, 0.045), Palette.mix(bg, fg, 0.08)];
    const text = Palette.readable(muted, fg, grounds);
    for (const g of grounds) {
      assert.ok(Palette.contrast(text, g) >= 4.5, `${name}: ${Palette.contrast(text, g).toFixed(2)}:1`);
      assert.ok(Palette.contrast(text, g) < Palette.contrast(fg, g), `${name}: secondary is weaker than ordinary text`);
    }
    if (grounds.every((g) => Palette.contrast(muted, g) >= 4.5)) assert.deepEqual(plain(text), plain(muted), `${name}: kept`);
  }
});

// Text on a lit control (theme.accentForeground = textOn(accent, ...)):
// at least 4.5:1 on the accent in every theme; a theme whose background or
// foreground already reads keeps it; the worst fill (mid grey) still works.
test("text on the accent reaches 4.5:1 in every theme", () => {
  const themes = JSON.parse(readFileSync(new URL("./fixtures/omarchy-themes.json", import.meta.url), "utf8"));
  const hex = (s) => ({ r: parseInt(s.slice(1, 3), 16) / 255, g: parseInt(s.slice(3, 5), 16) / 255, b: parseInt(s.slice(5, 7), 16) / 255, a: 1 });
  for (const [name, t] of Object.entries(themes)) {
    const fg = hex(t.foreground), bg = hex(t.background), accent = hex(t.accent);
    const text = Palette.textOn(accent, bg, fg);
    assert.ok(Palette.contrast(text, accent) >= 4.5, `${name}: ${Palette.contrast(text, accent).toFixed(2)}:1`);
    const start = Palette.readableOn(accent, bg, fg);
    if (Palette.contrast(start, accent) >= 4.5) assert.deepEqual(plain(text), plain(start), `${name}: kept`);
  }
  const grey = { r: 0.46, g: 0.46, b: 0.46, a: 1 };
  assert.ok(Palette.contrast(Palette.textOn(grey, grey, grey), grey) >= 4.5, "mid grey");
});
