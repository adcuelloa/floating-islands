// Actionable aggregation (.github/upstream-watch/aggregate.mjs) on synthetic
// fixtures: correlation, grouping, classification, evidence preservation.
import { test } from "node:test";
import assert from "node:assert/strict";
import { aggregate, itemTitle, renderSummary } from "../../.github/upstream-watch/aggregate.mjs";
import { C, X1, api, contractOut, edit, inventory, report, rows, run, target } from "./upstream-fixtures.mjs";

const [hide, optIn, , moveGuard] = [...rows.keys()];
const items = (findings, targets) => aggregate(report(findings, targets), { inventory, rows });
const evidenceCount = (fs) => fs.reduce((n, f) => n + f.evidence.length, 0);

test("a contract regression and the API removal behind it are one breaking item, all evidence kept", () => {
  const fs = run(edit((m) => m.set("shell/Ui/PluginBarApi.qml", api("property var _optIn: null", "property var _gone: null", "function show(a, b) {}"))),
    { contract: { base: contractOut(), head: contractOut([hide]) } });
  const its = items(fs);
  const brk = its.filter((i) => i.category === "breaking");
  assert.equal(brk.length, 1);
  assert.deepEqual(brk[0].members.map((f) => `${f.detector} ${f.kind}`), ["D1 regression", "D2 api-removed", "D7 path-touched"]);
  assert.equal(brk[0].primary, "host.widget-facade");
  assert.equal(its.reduce((n, i) => n + i.members.length, 0), fs.length, "every raw finding lands in exactly one item");
  assert.equal(evidenceCount(its.flatMap((i) => i.members)), evidenceCount(fs));
  assert.match(itemTitle(brk[0]), /^Upstream breaking change: facade callback _hide \[host\.widget-facade\]$/);
});

test("a removed qmldir type, its file and the contract row correlate; several capabilities, no primary", () => {
  const fs = run(edit((m) => {
    m.set("shell/Ui/qmldir", "module qs.Ui\nPluginBarApi 1.0 PluginBarApi.qml");
    m.delete("shell/Ui/ScreenMoveRemap.qml");
  }), { contract: { base: contractOut(), head: contractOut([moveGuard]) } });
  const [brk, ...others] = items(fs).filter((i) => i.category === "breaking");
  assert.equal(others.length, 0);
  assert.deepEqual(brk.members.map((f) => `${f.detector} ${f.kind} ${f.symbol ?? ""}`.trim()),
    ["D1 regression", "D2 api-removed ScreenMoveRemap", "D7 path-removed ScreenMoveRemap", "D7 path-touched qmldir"]);
  assert.deepEqual(brk.capabilities, ["host.widget-facade", "ui.screen-move-remap"]);
  assert.equal(brk.primary, null, "qmldir maps to two capabilities: no primary is invented");
});

test("independent failures in one file stay separate items; uncorrelated removals are modifications", () => {
  const fs = run(edit((m) => m.set("shell/Ui/PluginBarApi.qml", api("property var _gone: null", "function show(a, b) {}"))),
    { contract: { base: contractOut(), head: contractOut([hide], [optIn]) } });
  const its = items(fs);
  const brk = its.filter((i) => i.category === "breaking");
  assert.equal(brk.length, 2);
  assert.notEqual(brk[0].topic, brk[1].topic);
  assert.deepEqual(brk.map((i) => i.note).sort(), [null, "Affects an opt-in feature only (conditional contract row)."].sort());
  const gone = edit((m) => m.set("shell/Ui/PluginBarApi.qml", api("property var _hide: null", "property var _optIn: null", "function show(a, b) {}")));
  const mod = items(run(gone)).find((i) => i.subsystem === "shell/Ui/PluginBarApi.qml");
  assert.equal(mod.category, "modification");
  assert.equal(mod.change, "removed");
});

test("shortcuts: bindings that moved between files form one migration item with every binding listed", () => {
  const fs = run(edit((m) => {
    m.set("default/hypr/bindings/utilities.lua", 'o.bind("SUPER + CTRL + 1", "Panel one", "x")');
    m.set("default/hypr/bindings/regions/global.lua", 'o.bind("SUPER + K", "Keys", "y")\no.bind("SUPER + SHIFT + Q", "Quit", "z")');
    m.set("default/hypr/bindings/media.lua", 'o.bind("XF86AudioMute", "Mute", "m")');
  }));
  const sc = items(fs).filter((i) => i.subsystem.startsWith("shortcuts"));
  assert.deepEqual(sc.map((i) => [i.subsystem, i.category, i.change]), [
    ["shortcuts: bindings/regions/global.lua, bindings/utilities.lua", "modification", "migration"],
    ["shortcuts: bindings/media.lua", "informational", "added"],
  ]);
  const mig = sc[0];
  assert.deepEqual(mig.members.filter((f) => f.detector === "D5").map((f) => `${f.kind} ${f.symbol}`).sort(), [
    "shortcut-added SUPER + K", "shortcut-added SUPER + SHIFT + Q", "shortcut-changed SUPER + CTRL + 1", "shortcut-removed SUPER + K"]);
  assert.match(mig.note, /moved between these files.*SUPER\+CTRL\(\+ALT\) range Floating Islands uses \(1 bindings/);
});

test("new capability vs added API vs internal refactor", () => {
  const fs = run(edit((m) => {
    m.set("shell/plugins/local-models/manifest.json", JSON.stringify({ id: "omarchy.local-models", kind: "service" }));
    m.set("shell/plugins/local-models/Main.qml", "Item {}");
    m.set("shell/Ui/PluginBarApi.qml", api("property var _hide: null", "property var _optIn: null", "property var _gone: null", "function show(a, b) {}", "function open() {}"));
    m.set("shell/Commons/Style.qml", api("property int _cache: 0"));
  }));
  const its = items(fs);
  const nc = its.find((i) => i.category === "new-capability");
  assert.equal(nc.anchor, "manifest omarchy.local-models");
  assert.match(nc.note, /not an approved feature/);
  assert.equal(its.find((i) => i.subsystem === "shell/Ui/PluginBarApi.qml").change, "added");
  const style = its.find((i) => i.subsystem === "shell/Commons/Style.qml");
  assert.deepEqual([style.category, style.change], ["informational", "refactor"]);
});

test("the same incompatibility on trunk and the release line is one item; refs are listed", () => {
  const head = edit((m) => m.set("shell/Ui/PluginBarApi.qml", api("property var _optIn: null", "property var _gone: null", "function show(a, b) {}")));
  const contract = { base: contractOut(), head: contractOut([hide]) };
  const trunk = run(head, { contract });
  const rl = run(head, { contract, t: target({ ref: "v4-5-1", role: "release-line" }), intro: () => C });
  const brk = items([...trunk, ...rl], [target(), target({ ref: "v4-5-1", role: "release-line" })]).filter((i) => i.category === "breaking");
  assert.equal(brk.length, 1);
  assert.deepEqual(brk[0].refs, ["quattro", "v4-5-1"]);
  const one = items(trunk).find((i) => i.category === "breaking").members.length;
  assert.equal(brk[0].members.length, 2 * one, "both refs' evidence is kept");
});

test("attribution is qualified: the first commit touching a file is never called the introducing commit", () => {
  const head = edit((m) => m.set("default/hypr/bindings/utilities.lua", 'o.bind("SUPER + K", "Keys", "y")'));
  const touched = renderSummary(report(run(head)), items(run(head)));
  assert.match(touched, new RegExp(`${X1.slice(0, 12)} \\(first commit in the range that touched the file; not verified as the commit that made this change\\)`));
  const none = run(head, { intro: () => null });
  assert.ok(none.every((f) => f.attribution.basis === "unavailable" && f.attribution.sha === null));
  assert.match(renderSummary(report(none), items(none)), /attribution unavailable/);
});
