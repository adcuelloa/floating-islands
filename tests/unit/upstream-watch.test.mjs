// Read-only upstream watcher (.github/upstream-watch): detectors, ranges,
// state, report validation and rendering, all on synthetic fixtures. The real
// upstream is never contacted here.
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  clean, fence, nextState, parseLsRemote, parseState, planTarget, releaseFindings, span, validateInventory,
} from "../../.github/upstream-watch/lib.mjs";
import { lstatSync, mkdirSync, readdirSync, symlinkSync, writeFileSync } from "node:fs";
import { LIMITS, main, materialize, prepareClone } from "../../.github/upstream-watch/inspect.mjs";

import {
  sha, A, B, C, D, X1, X2, X3, ch, cap, inventory, capabilityIds, rows, contractOut, api, baseFiles, target, run, edit, only, report, lsRemote, renderSummary, validate,
} from "./upstream-fixtures.mjs";

test("unchanged upstream revision: no range, no findings", () => {
  const git = { has: () => true, isAncestor: () => true, mergeBase: () => C };
  assert.equal(planTarget({ ref: "quattro", role: "trunk", head: C, cursor: C, baseline: A }, git).status, "unchanged");
  assert.equal(planTarget({ ref: "quattro", role: "trunk", head: A, cursor: undefined, baseline: A }, git).status, "unchanged");
  assert.deepEqual(run(baseFiles()), []);
});

test("manifests: added, removed and modified; an unmapped id is a potential new capability", () => {
  const fs = only(run(edit((m) => {
    m.set("shell/plugins/bar/widgets/clock.manifest.json", JSON.stringify({ id: "omarchy.clock", kind: "widget", entryPoints: { bar: "Clock2.qml" } }));
    m.delete("shell/plugins/old/manifest.json");
    m.set("shell/plugins/local-models/manifest.json", JSON.stringify({ id: "omarchy.local-models", kind: "service" }));
  })), "D3");
  const by = Object.fromEntries(fs.map((f) => [f.kind, f]));
  assert.deepEqual(Object.keys(by).sort(), ["capability-new", "manifest-changed", "manifest-removed"]);
  assert.equal(by["manifest-changed"].scope, "omarchy.clock");
  assert.match(by["manifest-changed"].evidence[1].text, /changed keys: entryPoints/);
  assert.equal(by["manifest-removed"].severity, "breaking");
  assert.equal(by["capability-new"].scope, "unmapped:omarchy.local-models");
  assert.equal(by["capability-new"].severity, "review");
  assert.equal(by["capability-new"].evidence[0].path, "shell/plugins/local-models/manifest.json");
});

test("multiple independent changes to one capability: one group, separate fingerprints", () => {
  const fs = only(run(edit((m) => m.set("shell/Ui/PluginBarApi.qml",
    api("property var _hide: null", "property var _optIn: null", "function show(a, b, c) {}", "signal opened(string id)")))), "D2");
  assert.deepEqual(fs.map((f) => f.kind).sort(), ["api-added", "api-changed", "api-removed"]);
  assert.ok(fs.every((f) => f.scope === "host.widget-facade"));
  assert.equal(new Set(fs.map((f) => f.fingerprint)).size, 3);
  const removed = fs.find((f) => f.kind === "api-removed");
  assert.equal(removed.severity, "review", "no contract row names _gone: the inventory's PluginBarApi._* prose is not enough");
  assert.equal(only(run(edit((m) => m.set("shell/Ui/PluginBarApi.qml", api("property var _optIn: null", "property var _gone: null", "function show(a, b) {}")))), "D2")[0].severity,
    "breaking", "a contract row names _hide");
  assert.deepEqual(removed.evidence.map((e) => [e.sha, e.path, e.line]), [[A, "shell/Ui/PluginBarApi.qml", 4]]);
  assert.equal(fs.find((f) => f.kind === "api-changed").evidence[1].text, "function show(a,b,c)");
});

test("contract: required regression is breaking, opt-in is review, restoration is info", () => {
  const [hide, optIn, ws] = [...rows.keys()];
  assert.equal(rows.size, 4, "rows on the pinned Quickshell runtime are not upstream");
  const fs = only(run(baseFiles(), { contract: { base: contractOut([ws]), head: contractOut([hide], [optIn]) } }), "D1");
  const by = Object.fromEntries(fs.map((f) => [f.subject, f]));
  assert.equal(by[hide].kind, "regression"); assert.equal(by[hide].severity, "breaking");
  assert.equal(by[hide].certainty, "confirmed"); assert.equal(by[hide].scope, "host.widget-facade");
  assert.deepEqual(by[hide].evidence.map((e) => [e.sha, e.line]), [[A, 2], [C, 2]]);
  assert.equal(by[optIn].severity, "review");
  assert.equal(by[ws].kind, "restored"); assert.equal(by[ws].severity, "info"); assert.equal(by[ws].scope, "hypr.monitor-workspaces");
  assert.equal(only(run(baseFiles(), { contract: null }), "D1").length, 0, "no contract result, no D1 claims");
});

test("shortcuts, CLI headers, default bar options and moved inventory paths", () => {
  const fs = run(edit((m) => {
    m.set("default/hypr/bindings/utilities.lua", 'o.bind("SUPER+CTRL+1", "Panel one", "x")\no.bind_hold("ALT + Alt_R", "Talk", "a", "b")');
    m.set("bin/omarchy-bar", "#!/bin/bash\n# omarchy:summary=Configure the bar\n# omarchy:subcommand=use <id>\n");
    m.set("config/omarchy/shell.json", JSON.stringify({ bar: { position: "top", layout: { right: ["b", "a"] }, background: "glassy" } }));
    m.delete("default/hypr/monitor-workspaces.lua");
  }));
  const kinds = (d) => only(fs, d).map((f) => `${f.kind} ${f.subject}`).sort();
  assert.deepEqual(kinds("D5"), [
    "shortcut-added default/hypr/bindings/utilities.lua shortcut ALT + ALT_R",
    "shortcut-changed default/hypr/bindings/utilities.lua shortcut SUPER + CTRL + 1",
    "shortcut-removed default/hypr/bindings/utilities.lua shortcut SUPER + K"]);
  assert.deepEqual(kinds("D4"), ["cli-changed cli omarchy-bar"]);
  assert.deepEqual(kinds("D6"), ["config-added option bar.background", "config-changed option bar.layout.right"]);
  assert.ok(kinds("D7").includes("path-removed path default/hypr/monitor-workspaces.lua"));
});

test("blocker watch tokens: only added lines in the capability's files, always uncertain", () => {
  const fs = only(run(edit((m) => {
    m.set("shell/plugins/notifications/Panel.qml", "Item {\n  property var notificationHistory: []\n}");
    m.set("shell/plugins/clipboard/Main.qml", "Item { property var notificationHistory }");
  })), "D8");
  assert.equal(fs.length, 1);
  assert.equal(fs[0].scope, "omarchy.notifications");
  assert.equal(fs[0].certainty, "uncertain");
  assert.deepEqual([fs[0].evidence[0].path, fs[0].evidence[0].line], ["shell/plugins/notifications/Panel.qml", 2]);
});

test("removal, restoration and recurrence are three reports; the recurrence gets a new fingerprint", () => {
  const removed = edit((m) => m.set("shell/Ui/PluginBarApi.qml", api("property var _hide: null", "property var _optIn: null", "function show(a, b) {}")));
  const r1 = only(run(removed, { t: target({ base: A, head: B, status: "changed" }), intro: () => X1 }), "D2");
  const r2 = only(run(baseFiles(), { base: removed, t: target({ base: B, head: C, status: "changed" }), intro: () => X2 }), "D2");
  const r3 = only(run(removed, { t: target({ base: C, head: D, status: "changed" }), intro: () => X3 }), "D2");
  assert.deepEqual([r1, r2, r3].map((r) => r.map((f) => f.kind)), [["api-removed"], ["api-added"], ["api-removed"]]);
  assert.notEqual(r1[0].fingerprint, r3[0].fingerprint);
  assert.equal(r1[0].key, r3[0].key, "same content, different introducing commit");
  // a rerun of the same range is stable
  assert.equal(only(run(removed, { t: target({ base: A, head: B, status: "changed" }), intro: () => X1 }), "D2")[0].fingerprint, r1[0].fingerprint);
  // state keeps first_seen only for the last range's findings, so the recurrence is not masked
  const discovery = parseLsRemote(lsRemote());
  const s1 = nextState(null, discovery, [target({ head: B, status: "changed" })], r1);
  const s2 = nextState(s1, discovery, [target({ head: C, status: "changed" })], r2);
  assert.equal(s2.refs.quattro.first_seen[r1[0].key], undefined);
  assert.equal(s2.refs.quattro.processed, C);
});

test("history rewrite: diff from the merge-base, findings uncertain, fingerprints stable via first_seen", () => {
  const git = { has: (s) => s !== X3, isAncestor: () => false, mergeBase: (a, b) => (a === B ? A : null) };
  assert.deepEqual(planTarget({ ref: "quattro", role: "trunk", head: C, cursor: B, baseline: A }, git),
    { ref: "quattro", role: "trunk", base: A, head: C, status: "history-rewrite", rangeBase: A });
  assert.equal(planTarget({ ref: "quattro", role: "trunk", head: C, cursor: X3, baseline: A }, git).base, A, "lost cursor falls back to the baseline");
  const head = edit((m) => m.set("shell/Ui/PluginBarApi.qml", api("property var _hide: null", "property var _optIn: null", "function show(a, b) {}")));
  const t = target({ status: "history-rewrite", head: D });
  const [f] = only(run(head, { t }), "D2");
  assert.equal(f.certainty, "uncertain");
  assert.deepEqual(f.attribution, { sha: D, basis: "first-seen-at-head" });
  const [again] = only(run(head, { t: { ...t, head: sha("e") }, firstSeen: { [f.key]: D } }), "D2");
  assert.equal(again.fingerprint, f.fingerprint);
});

test("failed or incomplete fetch: target failed, no cursor moves", () => {
  const git = { has: () => false, isAncestor: () => false, mergeBase: () => null };
  assert.equal(planTarget({ ref: "quattro", role: "trunk", head: undefined, cursor: B, baseline: A }, git).status, "failed");
  assert.equal(planTarget({ ref: "quattro", role: "trunk", head: C, cursor: undefined, baseline: A }, git).error, "baseline revision not fetched");
  const discovery = parseLsRemote(lsRemote());
  const prev = { schema: 1, repo: "omacom/omarchy", refs: { quattro: { processed: B, first_seen: {} } }, tags_seen: [], release_branches_seen: [], reset: null };
  const next = nextState(prev, discovery, [{ ref: "quattro", head: C, status: "failed" }], []);
  assert.equal(next.refs.quattro.processed, B);
});

test("missing or corrupted baseline and state fail closed", () => {
  assert.throws(() => validateInventory({ ...inventory, revisions: { ...inventory.revisions, baseline: undefined } }), /revisions.baseline/);
  assert.throws(() => validateInventory({ ...inventory, revisions: { ...inventory.revisions, trunk: { ref: "quattro", sha: "abc" } } }), /revisions.trunk/);
  assert.equal(parseState(null), null);
  const good = { schema: 1, repo: "omacom/omarchy", refs: { quattro: { processed: B, first_seen: { "0123456789abcdef": C } } }, tags_seen: ["v4.5.0"], release_branches_seen: ["v4-5-1"], reset: null };
  assert.deepEqual(parseState(JSON.stringify(good)), good);
  for (const [why, bad] of [
    ["not JSON", "{"], ["foreign repo", JSON.stringify({ ...good, repo: "someone/fork" })],
    ["keys", JSON.stringify({ ...good, extra: 1 })], ["processed", JSON.stringify({ ...good, refs: { quattro: { processed: "HEAD", first_seen: {} } } })],
    ["ref name", JSON.stringify({ ...good, refs: { "../x": { processed: B, first_seen: {} } } })],
    ["64 KB", JSON.stringify({ ...good, tags_seen: Array(9000).fill("v4.5.0") })],
  ]) assert.throws(() => parseState(bad), new RegExp(why.replace(/[.]/g, "\\.")), why);
});

test("discovery: default branch and release line are read, never assumed", () => {
  const d = parseLsRemote(lsRemote(`${X1}\trefs/heads/v4-6-0\n${X2}\trefs/tags/v4.6.0-rc1`));
  assert.equal(d.defaultBranch, "quattro");
  assert.equal(d.tags.get("v4.5.0"), A, "annotated tags resolve to the peeled commit");
  assert.equal(d.releaseLine, "v4-6-0", "highest release branch without a final tag");
  assert.deepEqual(d.releaseBranches, ["v4-5-0", "v4-5-1", "v4-6-0"]);
  assert.throws(() => parseLsRemote(lsRemote().replace(/^ref: .*$/m, "")), /no default branch/);
  assert.throws(() => parseLsRemote(lsRemote().replace(/refs\/heads\/v4-5-[01]/g, "refs/heads/dev")), /no release branch/);
  const rel = releaseFindings(d, { tags_seen: ["v4.5.0"], release_branches_seen: ["v4-5-0", "v4-5-1", "v4-4-9"] }, "v4.5.0");
  assert.deepEqual(rel.map((f) => f.subject), ["prerelease v4.6.0-rc1", "release-branch-added v4-6-0", "release-branch-gone v4-4-9"]);
  assert.deepEqual(releaseFindings(d, null, "v4.5.0").map((f) => f.subject),
    ["prerelease v4.6.0-rc1", "release-branch-added v4-5-1", "release-branch-added v4-6-0"]);
});

test("malformed or oversized reports are rejected", () => {
  const fs = run(edit((m) => m.delete("shell/plugins/old/manifest.json")));
  const good = report(fs);
  assert.doesNotThrow(() => validate(good));
  const mut = (fn) => { const r = JSON.parse(JSON.stringify(good)); fn(r); return r; };
  for (const [why, r, bytes] of [
    ["larger than", good, (1 << 20) + 1],
    ["keys", mut((r) => { r.findings[0].note = "x"; })],
    ["keys", mut((r) => { r.extra = 1; })],
    ["sha", mut((r) => { r.findings[0].evidence[0].sha = "HEAD"; })],
    ["path", mut((r) => { r.findings[0].evidence[0].path = "../../etc/passwd"; })],
    ["scope", mut((r) => { r.findings[0].scope = "omarchy.unknown"; })],
    ["attribution", mut((r) => { r.findings[0].attribution = { sha: null, basis: "first-commit-touching-file" }; })],
    ["primary", mut((r) => { r.findings[0].primary = "omarchy.clock"; })],
    ["state_digest", mut((r) => { r.state_digest = "x"; })],
    ["severity", mut((r) => { r.findings[0].severity = "critical"; })],
    ["count", mut((r) => { r.findings = Array(501).fill(r.findings[0]); })],
    ["duplicate", mut((r) => { r.findings.push(r.findings[0]); r.totals.breaking++; })],
    ["unsafe", mut((r) => { r.findings[0].subject = `x${ch(0x202e)}y`; })],
    ["unsafe", mut((r) => { r.findings[0].subject = "<!-- fi-upstream:group=x -->"; })],
    ["totals", mut((r) => { r.totals.info = 99; })],
  ]) assert.throws(() => validate(r, bytes), new RegExp(why), why);
});

test("malicious upstream text renders inert: fences, mentions, links, markers, control and bidi characters", () => {
  const evil = "``` @octocat #123 [x](https://evil.example) <!-- fi-upstream:group=x --> " + ch(0x202e) + ch(0x1b) + "[31m" + ch(0x2028) + "z";
  assert.equal(clean(evil).includes("<!--"), false);
  assert.equal(/[\x00-\x1f\x7f-\x9f]/.test(clean(evil)), false);
  assert.equal([0x202e, 0x2028].some((c) => clean(evil).includes(ch(c))), false);
  assert.equal(Array.from(clean("x".repeat(500))).length, 200);
  assert.match(span(evil), /^```` .* ````$/, "span delimiter outruns the text's backticks");
  assert.match(fence(["a ```` b"]), /^`````text\n/);
  // end to end: a hostile manifest id and key reach the report and summary only as inert text
  const fs = run(edit((m) => m.set("shell/plugins/hostile/manifest.json", JSON.stringify({ id: evil, kind: "widget" }))));
  const r = report(fs);
  assert.doesNotThrow(() => validate(r));
  const f = r.findings.find((x) => x.kind === "capability-new");
  assert.match(f.scope, /^unmapped:manifest-[0-9a-f]{16}$/);
  const md = renderSummary(r);
  assert.equal(md.includes("<!--"), false);
  assert.equal(/[\x00-\x09\x0b-\x1f\x7f-\x9f]/.test(md), false);
  for (const line of md.split("\n").filter((l) => l.includes("@octocat"))) {
    const m = /```` (.*@octocat.*) ````/.exec(line);
    assert.ok(m && !m[1].includes("````"), "mention stays inside one code span");
  }
  const outsideCode = md.replace(/(`+) .*? \1/g, "");
  assert.equal(outsideCode.includes("evil"), false, "upstream text appears only inside code spans");
  for (const url of outsideCode.match(/\]\((https?:[^)]+)\)/g) ?? []) assert.match(url, /^\]\(https:\/\/github\.com\/omacom\/omarchy\/(blob|commit)\/[0-9a-f]{40}/);
});

test("output is deterministic regardless of input order", () => {
  const head = edit((m) => {
    m.delete("shell/plugins/old/manifest.json");
    m.set("shell/Ui/PluginBarApi.qml", api("property var _optIn: null", "signal a()", "signal b()"));
  });
  const reversed = (m) => new Map([...m].reverse());
  const one = JSON.stringify(report(run(head)));
  const two = JSON.stringify(report(run(reversed(head), { base: reversed(baseFiles()) })));
  assert.equal(one, two);
  assert.equal(renderSummary(JSON.parse(one)), renderSummary(JSON.parse(two)));
});

test("inspect fails closed without writing when the upstream lacks the inventory baseline", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "fi-watch-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const g = (...a) => execFileSync("git", ["-C", join(dir, "up"), ...a], { env: { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" }, stdio: "pipe" });
  execFileSync("git", ["init", "-q", "-b", "quattro", join(dir, "up")]);
  g("-c", "user.name=t", "-c", "user.email=t", "commit", "-q", "--allow-empty", "-m", "x");
  g("branch", "v4-5-1");
  g("tag", "v4.5.0");
  const out = join(dir, "report.json");
  assert.throws(() => main(["--work", join(dir, "work"), "--url", `file://${join(dir, "up")}`, "--report", out]), /baseline v4\.5\.0 [0-9a-f]{40} cannot be fetched/);
  assert.equal(existsSync(out), false);
  assert.throws(() => main(["--work", join(dir, "work"), "--url", `file://${join(dir, "missing")}`]), /git ls-remote failed/);
});

test("symlinks in the upstream tree are never followed or created", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "fi-watch-ln-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const up = join(dir, "up");
  const env = { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" };
  const g = (...a) => execFileSync("git", ["-C", up, ...a], { env, stdio: "pipe" }).toString();
  mkdirSync(join(up, "shell"), { recursive: true });
  writeFileSync(join(dir, "outside.txt"), "SECRET");
  writeFileSync(join(up, "shell", "ok.qml"), "Item {}");
  symlinkSync(join(dir, "outside.txt"), join(up, "shell", "leak.qml"));
  symlinkSync(dir, join(up, "shell", "dirlink"));
  execFileSync("git", ["init", "-q", "-b", "quattro", up], { env });
  g("add", "-A");
  g("-c", "user.name=t", "-c", "user.email=t", "commit", "-q", "-m", "x");
  const sha = g("rev-parse", "HEAD").trim();
  const clone = join(dir, "clone");
  prepareClone(`file://${up}`, clone, "quattro");
  const files = materialize(clone, sha);
  assert.deepEqual([...files.keys()], ["shell/ok.qml"]);
  assert.ok([...files.values()].every((v) => !v.includes("SECRET")));
  for (const name of readdirSync(join(clone, "shell"))) assert.equal(lstatSync(join(clone, "shell", name)).isSymbolicLink(), false, name);
});

test("resource limits: an oversized tree or object store fails closed and writes nothing", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "fi-watch-big-"));
  const saved = { ...LIMITS };
  t.after(() => { Object.assign(LIMITS, saved); rmSync(dir, { recursive: true, force: true }); });
  const up = join(dir, "up");
  const env = { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" };
  const g = (...a) => execFileSync("git", ["-C", up, ...a], { env, stdio: "pipe" }).toString();
  mkdirSync(join(up, "shell"), { recursive: true });
  for (const n of ["a", "b", "c"]) writeFileSync(join(up, "shell", `${n}.qml`), "Item {}\n".repeat(50));
  execFileSync("git", ["init", "-q", "-b", "quattro", up], { env });
  g("add", "-A");
  g("-c", "user.name=t", "-c", "user.email=t", "commit", "-q", "-m", "x");
  g("branch", "v4-5-1");
  const sha = g("rev-parse", "HEAD").trim();
  const clone = join(dir, "work", "omarchy");
  prepareClone(`file://${up}`, clone, "quattro");
  LIMITS.files = 2;
  assert.throws(() => materialize(clone, sha), /exceeds 2 files/);
  Object.assign(LIMITS, saved, { treeBytes: 500 });
  assert.throws(() => materialize(clone, sha), /exceeds 5000 files or 500 bytes/);
  Object.assign(LIMITS, saved, { objectsKiB: 0 });
  const out = { report: join(dir, "r.json"), state: join(dir, "s.json") };
  assert.throws(() => main(["--work", join(dir, "work"), "--url", `file://${up}`, "--report", out.report, "--emit-state", out.state]), /refusing to analyse/);
  assert.equal(existsSync(out.report) || existsSync(out.state), false);
});
