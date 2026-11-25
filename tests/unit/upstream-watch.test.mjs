// Read-only upstream watcher (.github/upstream-watch): detectors, ranges,
// state, report validation and rendering, all on synthetic fixtures. The real
// upstream is never contacted here.
import { test } from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  analyze, clean, contractRows, fence, isDetectorInput, nextState, parseContract, parseLsRemote, parseState, planTarget, releaseFindings, safeErrorText, span, validateInventory,
} from "../../.github/upstream-watch/lib.mjs";
import { aggregate } from "../../.github/upstream-watch/aggregate.mjs";
import { LIMITS, main, materialize, objectStoreKiB, prepareClone } from "../../.github/upstream-watch/inspect.mjs";

import {
  sha, A, B, C, D, X1, X2, X3, ch, cap, inventory, capabilityIds, rows, contractOut, contractPorcelain, api, baseFiles, target, run, edit, only, report, lsRemote, renderSummary, validate,
} from "./upstream-fixtures.mjs";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

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

// ---------- independent review regressions (F1-F6 + stderr sanitization)

test("F1: actual check-contract.sh distinguishes KeyboardPanel anchorItem and bar rows independently", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "fi-watch-f1-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const realRows = contractRows(readFileSync(join(repoRoot, "tests/contract/contract.tsv"), "utf8"));
  const kpRows = [...realRows.entries()].filter(([, r]) => r.area === "panel" && r.reason === "given at construction (setSource)");
  assert.equal(kpRows.length, 2, "both KeyboardPanel construction rows must have distinct identities");
  const [[anchorKey, anchorRow], [barKey, barRow]] = kpRows;
  assert.notEqual(anchorKey, barKey);
  assert.match(anchorRow.pattern, /anchorItem/);
  assert.match(barRow.pattern, /QtObject bar/);

  const runChecker = (qml) => {
    const tree = join(dir, "omarchy");
    mkdirSync(join(tree, "shell/Ui"), { recursive: true });
    writeFileSync(join(tree, "shell/Ui/KeyboardPanel.qml"), qml);
    try {
      return execFileSync(join(repoRoot, "tests/contract/check-contract.sh"), ["--advisory", "--porcelain"],
        { env: { ...process.env, OMARCHY_PATH: tree }, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    } catch (e) {
      assert.equal(e.status, 1);
      return e.stdout;
    }
  };

  const fullQml = "Item {\n  required property Item anchorItem\n  required property QtObject bar\n}\n";
  const noAnchorQml = "Item {\n  required property QtObject bar\n}\n";
  const noBarQml = "Item {\n  required property Item anchorItem\n}\n";
  const baseContract = parseContract(runChecker(fullQml), realRows);
  const noAnchorContract = parseContract(runChecker(noAnchorQml), realRows);
  const noBarContract = parseContract(runChecker(noBarQml), realRows);

  assert.equal(baseContract.get(anchorKey), "ok");
  assert.equal(baseContract.get(barKey), "ok");
  assert.equal(noAnchorContract.get(anchorKey), "FAIL");
  assert.equal(noAnchorContract.get(barKey), "ok");
  assert.equal(noBarContract.get(anchorKey), "ok");
  assert.equal(noBarContract.get(barKey), "FAIL");

  const d1Anchor = only(analyze({
    inventory, target: target(), rows: realRows, introducing: () => X1,
    files: { base: new Map([["shell/Ui/KeyboardPanel.qml", fullQml]]), head: new Map([["shell/Ui/KeyboardPanel.qml", noAnchorQml]]) },
    contract: { base: baseContract, head: noAnchorContract },
  }), "D1");
  const d1AnchorBreaking = d1Anchor.filter((f) => f.severity === "breaking");
  assert.equal(d1AnchorBreaking.length, 1);
  assert.equal(d1AnchorBreaking[0].subject, anchorKey);
  assert.equal(d1Anchor.some((f) => f.subject === barKey), false, "removing anchorItem must not trip the bar row");

  const d1Bar = only(analyze({
    inventory, target: target(), rows: realRows, introducing: () => X1,
    files: { base: new Map([["shell/Ui/KeyboardPanel.qml", fullQml]]), head: new Map([["shell/Ui/KeyboardPanel.qml", noBarQml]]) },
    contract: { base: baseContract, head: noBarContract },
  }), "D1");
  assert.equal(d1Bar.length, 1);
  assert.equal(d1Bar[0].subject, barKey);
  assert.equal(d1Bar[0].severity, "breaking");
});

test("F1: incomplete, duplicated, mismatched or missing contract results fail closed", () => {
  const valid = contractPorcelain();
  const lines = valid.split("\n");
  // missing summary
  assert.throws(() => parseContract(lines.slice(0, -1).join("\n"), rows), /missing summary/);
  // missing row (with summary adjusted)
  assert.throws(() => parseContract([...lines.slice(1, -1), "contract: 3 passed, 0 failed, 0 conditional warnings"].join("\n"), rows), /missing result/);
  // duplicate row line number
  assert.throws(() => parseContract([lines[0], ...lines].join("\n"), rows), /duplicate result/);
  // mismatched summary count
  assert.throws(() => parseContract([...lines.slice(0, -1), "contract: 99 passed, 0 failed, 0 conditional warnings"].join("\n"), rows), /disagree with summary/);
  // mismatched area/reason metadata
  assert.throws(() => parseContract([lines[0].replace("widgets", "other"), ...lines.slice(1)].join("\n"), rows), /mismatched metadata/);
  // D1 never treats a missing map entry as "ok"
  const partial = new Map(contractOut());
  partial.delete([...rows.keys()][0]);
  assert.throws(() => run(baseFiles(), { contract: { base: contractOut(), head: partial } }), /missing contract result/);
});

test("F2: identical fingerprints across different refs validate and aggregate; same-ref duplicates still fail", () => {
  const head = edit((m) => m.set("shell/Ui/PluginBarApi.qml", api("property var _optIn: null", "property var _gone: null", "function show(a, b) {}")));
  const contract = { base: contractOut(), head: contractOut([[...rows.keys()][0]]) };
  const trunk = run(head, { contract, t: target({ ref: "quattro", role: "trunk" }), intro: () => X1 });
  const rl = run(head, { contract, t: target({ ref: "v4-5-1", role: "release-line" }), intro: () => X1 });
  // Same finding + same attribution SHA => identical fingerprints on both refs.
  assert.deepEqual(trunk.map((f) => f.fingerprint).sort(), rl.map((f) => f.fingerprint).sort());
  const r = report([...trunk, ...rl], [target({ ref: "quattro", role: "trunk" }), target({ ref: "v4-5-1", role: "release-line" })]);
  assert.doesNotThrow(() => validate(r));
  const its = aggregate(r, { inventory, rows });
  const brk = its.filter((i) => i.category === "breaking");
  assert.equal(brk.length, 1);
  assert.deepEqual(brk[0].refs, ["quattro", "v4-5-1"]);
  assert.equal(brk[0].members.length, 2 * trunk.length);
  // Same-ref duplicate fingerprint is still rejected.
  const dup = JSON.parse(JSON.stringify(r));
  dup.findings.push({ ...dup.findings[0] });
  dup.totals[dup.findings[0].severity]++;
  assert.throws(() => validate(dup), /duplicate fingerprint for ref/);
});

test("F3: headerless CLI addition and removing the last header emit null evidence text and validate", () => {
  const fs = run(edit((m) => {
    m.set("bin/omarchy-shell-extra", "#!/bin/bash\necho hi\n");
    m.set("bin/omarchy-bar", "#!/bin/bash\n# plain comment, no omarchy header\n");
  }));
  const d4 = only(fs, "D4");
  const added = d4.find((f) => f.subject === "cli omarchy-shell-extra");
  const changed = d4.find((f) => f.subject === "cli omarchy-bar");
  assert.ok(added && changed);
  assert.equal(added.kind, "cli-added");
  assert.deepEqual(added.evidence, [{ sha: C, path: "bin/omarchy-shell-extra", line: null, text: null }]);
  assert.equal(changed.kind, "cli-changed");
  assert.equal(changed.evidence[0].text, "# omarchy:summary=Configure the bar");
  assert.deepEqual(changed.evidence[1], { sha: C, path: "bin/omarchy-bar", line: null, text: null });
  const r = report(fs);
  assert.doesNotThrow(() => validate(r));
  assert.doesNotThrow(() => renderSummary(r));
  // Schema requirement is NOT weakened: empty string evidence text is still rejected.
  const bad = JSON.parse(JSON.stringify(r));
  bad.findings[0].evidence[0].text = "";
  assert.throws(() => validate(bad), /evidence\[0\]\.text: string/);
});

test("F4: D2 removal referenced only by a conditional contract row stays review, not breaking", () => {
  const onlyConditional = only(run(edit((m) => m.set("shell/Ui/PluginBarApi.qml",
    api("property var _hide: null", "property var _gone: null", "function show(a, b) {}")))), "D2");
  assert.equal(onlyConditional.length, 1);
  assert.equal(onlyConditional[0].kind, "api-removed");
  assert.equal(onlyConditional[0].symbol, "_optIn");
  assert.equal(onlyConditional[0].severity, "review", "conditional contract row must not promote D2 removal to breaking");
});

test("F6: oversized detector input marks affected target failed (exit 3) while preserving healthy target; late object growth fails closed (exit 2)", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "fi-watch-f6-"));
  const saved = { ...LIMITS };
  t.after(() => { Object.assign(LIMITS, saved); rmSync(dir, { recursive: true, force: true }); });
  const up = join(dir, "up");
  const env = { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" };
  const g = (...a) => execFileSync("git", ["-C", up, ...a], { env, stdio: "pipe" }).toString().trim();

  // Build synthetic upstream with baseline commit, healthy v4-5-1, and oversized detector input on quattro.
  mkdirSync(join(up, "shell/Ui"), { recursive: true });
  mkdirSync(join(up, "shell/assets"), { recursive: true });
  mkdirSync(join(up, "bin"), { recursive: true });
  writeFileSync(join(up, "shell/Ui/PluginBarApi.qml"), api("property var _hide: null"));
  writeFileSync(join(up, "bin/omarchy-bar"), "#!/bin/bash\n# omarchy:summary=Bar\n");
  execFileSync("git", ["init", "-q", "-b", "quattro", up], { env });
  g("add", "-A");
  g("-c", "user.name=t", "-c", "user.email=t", "commit", "-q", "-m", "baseline");
  const baseSha = g("rev-parse", "HEAD");
  g("tag", "v4.5.0");

  // Branch v4-5-1: small healthy CLI change + non-detector large asset (skipped safely).
  g("checkout", "-q", "-b", "v4-5-1");
  writeFileSync(join(up, "bin/omarchy-bar"), "#!/bin/bash\n# omarchy:summary=Bar v2\n");
  writeFileSync(join(up, "shell/assets/banner.bin"), "x".repeat(4000));
  g("add", "-A");
  g("-c", "user.name=t", "-c", "user.email=t", "commit", "-q", "-m", "healthy release line");
  const rlSha = g("rev-parse", "HEAD");

  // Branch quattro: oversized detector input (shell/Ui/PluginBarApi.qml).
  g("checkout", "-q", "quattro");
  writeFileSync(join(up, "shell/Ui/PluginBarApi.qml"), api("property var _hide: null") + "\n// " + "y".repeat(4000) + "\n");
  g("add", "-A");
  g("-c", "user.name=t", "-c", "user.email=t", "commit", "-q", "-m", "oversized api file");
  const trunkSha = g("rev-parse", "HEAD");

  const invPath = join(dir, "capabilities.json");
  const synInv = {
    ...inventory,
    revisions: {
      baseline: { ref: "v4.5.0", sha: baseSha },
      release_line: { ref: "v4-5-1", sha: rlSha },
      trunk: { ref: "quattro", sha: trunkSha },
    },
  };
  writeFileSync(invPath, JSON.stringify(synInv));

  // Verify detector-input classification directly.
  assert.equal(isDetectorInput("shell/Ui/PluginBarApi.qml", { inventory: synInv, rows }), true);
  assert.equal(isDetectorInput("shell/assets/banner.bin", { inventory: synInv, rows }), false);

  // Run main with fileBytes = 1000: quattro fails (oversized detector input), v4-5-1 succeeds (exit 3, no state emitted).
  LIMITS.fileBytes = 1000;
  const out = { report: join(dir, "report.json"), summary: join(dir, "summary.md"), state: join(dir, "state.json") };
  const code = main(["--work", join(dir, "work1"), "--url", `file://${up}`, "--report", out.report, "--summary", out.summary, "--emit-state", out.state], { inventoryPath: invPath });
  assert.equal(code, 3, "partial inspection failure must exit 3");
  assert.equal(existsSync(out.state), false, "incomplete inspection must not emit state");
  const rep = JSON.parse(readFileSync(out.report, "utf8"));
  const trunkT = rep.targets.find((x) => x.ref === "quattro");
  const rlT = rep.targets.find((x) => x.ref === "v4-5-1");
  assert.equal(trunkT.status, "failed");
  assert.match(trunkT.error, /detector input shell\/Ui\/PluginBarApi\.qml.*exceeds 1000 bytes/);
  assert.equal(rlT.status, "cumulative");
  assert.ok(rep.findings.some((f) => f.ref === "v4-5-1" && f.detector === "D4"), "healthy target findings are preserved");
  assert.equal(rep.findings.some((f) => f.ref === "quattro"), false, "failed target emits no partial findings");

  // Late object growth during blob hydration: set objectsKiB just above blobless fetch size, below hydrated checkout size.
  Object.assign(LIMITS, saved);
  const bigUp = join(dir, "big-up");
  mkdirSync(join(bigUp, "shell/Ui"), { recursive: true });
  writeFileSync(join(bigUp, "shell/Ui/PluginBarApi.qml"), api("property var _hide: null"));
  execFileSync("git", ["init", "-q", "-b", "quattro", bigUp], { env });
  const bg = (...a) => execFileSync("git", ["-C", bigUp, ...a], { env, stdio: "pipe" }).toString().trim();
  bg("config", "uploadpack.allowFilter", "true");
  bg("config", "uploadpack.allowAnySHA1InWant", "true");
  bg("add", "-A");
  bg("-c", "user.name=t", "-c", "user.email=t", "commit", "-q", "-m", "base");
  const bigBase = bg("rev-parse", "HEAD");
  bg("tag", "v4.5.0");
  bg("branch", "v4-5-1");
  // Add an incompressible ~200 KiB file so blob hydration grows the object store well past blobless fetch.
  const noise = randomBytes(120_000).toString("base64");
  writeFileSync(join(bigUp, "shell/Ui/PluginBarApi.qml"), `${api("property var _hide: null")}\n// ${noise}\n`);
  bg("add", "-A");
  bg("-c", "user.name=t", "-c", "user.email=t", "commit", "-q", "-m", "large blob");
  const bigHead = bg("rev-parse", "HEAD");

  const bigInvPath = join(dir, "big-capabilities.json");
  writeFileSync(bigInvPath, JSON.stringify({
    ...inventory,
    revisions: {
      baseline: { ref: "v4.5.0", sha: bigBase },
      release_line: { ref: "v4-5-1", sha: bigBase },
      trunk: { ref: "quattro", sha: bigHead },
    },
  }));
  // Measure blobless clone size vs hydrated size to place the limit strictly between them.
  const probeClone = join(dir, "probe");
  prepareClone(`file://${bigUp}`, probeClone, "quattro");
  const bloblessKiB = objectStoreKiB(probeClone);
  materialize(probeClone, bigHead);
  const hydratedKiB = objectStoreKiB(probeClone);
  assert.ok(hydratedKiB > bloblessKiB, `expected hydration to grow object store (${bloblessKiB} -> ${hydratedKiB} KiB)`);

  LIMITS.objectsKiB = bloblessKiB + Math.floor((hydratedKiB - bloblessKiB) / 2);
  const out2 = { report: join(dir, "r2.json"), summary: join(dir, "s2.md"), state: join(dir, "st2.json") };
  assert.throws(
    () => main(["--work", join(dir, "work2"), "--url", `file://${bigUp}`, "--report", out2.report, "--summary", out2.summary, "--emit-state", out2.state], { inventoryPath: bigInvPath }),
    /after blob hydration.*refusing to analyse/,
  );
  assert.equal(existsSync(out2.report) || existsSync(out2.summary) || existsSync(out2.state), false, "late object growth must write nothing");
});

test("untrusted Git error output cannot inject GitHub Actions workflow commands", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "fi-watch-err-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const sanitized = safeErrorText("::error file=a::boom\n::add-mask::secret\x1b[31m<!--x-->");
  assert.equal(sanitized.includes("::"), false);
  assert.equal(sanitized.includes("\n"), false);
  assert.equal(sanitized.includes("<!--"), false);
  assert.throws(
    () => main(["--work", join(dir, "work"), "--url", `file://${join(dir, "::error::injected")}`]),
    (err) => {
      assert.match(err.message, /git ls-remote failed/);
      assert.equal(err.message.includes("::"), false, "workflow command syntax must be neutralized");
      return true;
    },
  );
});
