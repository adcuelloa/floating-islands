// Validates docs/upstream/capabilities.json: the machine-readable map of
// Omarchy capabilities to their Floating Islands integration. Structure and
// allowed states are checked always; upstream source references are checked
// against the installed (pinned) Omarchy tree, $OMARCHY_PATH or
// /usr/share/omarchy, and skipped visibly when that tree is absent.
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const inventory = JSON.parse(readFileSync(join(repo, "docs/upstream/capabilities.json"), "utf8"));
const caps = inventory.capabilities;
const tree = process.env.OMARCHY_PATH || "/usr/share/omarchy";
const haveTree = existsSync(join(tree, "shell/shell.qml"));

const STRATEGIES = ["native", "hosted", "partial", "delegated", "planned", "blocked", "pending-review", "not-applicable"];
const KINDS = ["host", "api", "shortcut", "config", "ipc", "theme", "runtime", "widget", "panel", "overlay", "service"];
const APPROVALS = ["approved", "open", "not-applicable"];
const BASELINE_COMPAT = ["ok", "broken", "unknown"];
const TRUNK_COMPAT = ["ok", "broken", "changed", "unknown", "absent"];
const SHA = /^[0-9a-f]{40}$/;
const ID = /^[a-z][a-z0-9-]*(\.[a-z0-9-]+)+$/;
const UPSTREAM_PATH = /^(?!\/)(?!.*(^|\/)\.\.?(\/|$))[A-Za-z0-9._\/+-]+$/;
const RFC = /^Q[1-9]$/;

function keys(obj, expected, where) {
  assert.deepEqual(Object.keys(obj).sort(), [...expected].sort(), `${where}: keys`);
}
function strings(list, where) {
  assert.ok(Array.isArray(list), `${where}: array`);
  for (const s of list) assert.ok(typeof s === "string" && s.length > 0 && s.length <= 300, `${where}: non-empty string`);
}

test("inventory: top-level shape, revisions and product rule", () => {
  keys(inventory, ["schema", "product_rules", "revisions", "capabilities"], "inventory");
  assert.equal(inventory.schema, 1);
  strings(inventory.product_rules, "product_rules");
  assert.ok(inventory.product_rules.some((r) => /one unified system-control entry point/i.test(r)), "single entry point rule kept");
  keys(inventory.revisions, ["baseline", "release_line", "trunk"], "revisions");
  for (const [name, rev] of Object.entries(inventory.revisions)) {
    assert.ok(SHA.test(rev.sha), `revisions.${name}.sha is a full SHA`);
    assert.ok(typeof rev.ref === "string" && rev.ref.length > 0, `revisions.${name}.ref`);
  }
  assert.ok(Array.isArray(caps) && caps.length > 0);
});

test("inventory: every capability has exactly the schema's fields and allowed states", () => {
  const shas = Object.values(inventory.revisions).map((r) => r.sha);
  for (const c of caps) {
    const w = c.id;
    keys(c, ["id", "title", "kind", "origin", "upstream", "depends_on", "integration", "placement", "compat",
      "contract_areas", "fi_files", "blockers", "issue", "reviewed"], w);
    assert.ok(ID.test(c.id), `${w}: id format`);
    assert.ok(typeof c.title === "string" && c.title.length > 0, `${w}: title`);
    assert.ok(KINDS.includes(c.kind), `${w}: kind ${c.kind}`);
    assert.ok(["baseline", "detected"].includes(c.origin), `${w}: origin`);
    keys(c.upstream, ["ids", "paths", "api"], `${w}.upstream`);
    strings(c.upstream.ids, `${w}.upstream.ids`);
    strings(c.upstream.paths, `${w}.upstream.paths`);
    strings(c.upstream.api, `${w}.upstream.api`);
    for (const p of c.upstream.paths) assert.ok(UPSTREAM_PATH.test(p), `${w}: upstream path ${p} is relative and clean`);
    strings(c.depends_on, `${w}.depends_on`);
    keys(c.integration, ["current", "intended"], `${w}.integration`);
    assert.ok(STRATEGIES.includes(c.integration.current), `${w}: integration.current ${c.integration.current}`);
    assert.ok(STRATEGIES.includes(c.integration.intended), `${w}: integration.intended ${c.integration.intended}`);
    keys(c.placement, ["current", "proposed", "approval", "rfc"], `${w}.placement`);
    for (const k of ["current", "proposed"]) assert.ok(c.placement[k] === null || typeof c.placement[k] === "string", `${w}: placement.${k}`);
    assert.ok(APPROVALS.includes(c.placement.approval), `${w}: placement.approval`);
    assert.ok(c.placement.rfc === null || RFC.test(c.placement.rfc), `${w}: placement.rfc`);
    keys(c.compat, ["baseline", "trunk", "evidence"], `${w}.compat`);
    assert.ok(BASELINE_COMPAT.includes(c.compat.baseline), `${w}: compat.baseline`);
    assert.ok(TRUNK_COMPAT.includes(c.compat.trunk), `${w}: compat.trunk`);
    strings(c.compat.evidence, `${w}.compat.evidence`);
    strings(c.contract_areas, `${w}.contract_areas`);
    strings(c.fi_files, `${w}.fi_files`);
    assert.ok(Array.isArray(c.blockers), `${w}: blockers`);
    for (const b of c.blockers) {
      keys(b, ["id", "summary", "upstream_ref", "watch"], `${w}.blocker`);
      assert.ok(/^[a-z0-9-]+$/.test(b.id) && b.summary.length > 0, `${w}: blocker id/summary`);
      assert.ok(b.upstream_ref === null || typeof b.upstream_ref === "string", `${w}: blocker upstream_ref`);
      strings(b.watch, `${w}.blocker.watch`);
    }
    assert.ok(c.issue === null || /^#[0-9]+$/.test(c.issue), `${w}: issue`);
    assert.ok(shas.includes(c.reviewed), `${w}: reviewed is one of the recorded revisions`);
  }
});

test("inventory: identifiers are unique and dependencies resolve", () => {
  const ids = caps.map((c) => c.id);
  assert.deepEqual(ids.filter((id, i) => ids.indexOf(id) !== i), [], "duplicate capability ids");
  const upstreamIds = caps.flatMap((c) => c.upstream.ids);
  assert.deepEqual(upstreamIds.filter((id, i) => upstreamIds.indexOf(id) !== i), [], "an upstream id mapped twice");
  for (const c of caps) for (const d of c.depends_on) {
    assert.ok(ids.includes(d), `${c.id}: depends_on ${d} exists`);
    assert.notEqual(d, c.id, `${c.id}: depends on itself`);
  }
});

test("inventory: design decisions stay open where the RFC has not decided", () => {
  for (const c of caps) {
    const w = c.id;
    // A capability seen only on a newer upstream is a finding, not an approved feature.
    if (c.origin === "detected") {
      assert.ok(["pending-review", "not-applicable"].includes(c.integration.current), `${w}: detected, current`);
      assert.ok(["pending-review", "not-applicable"].includes(c.integration.intended), `${w}: detected, intended`);
      assert.notEqual(c.placement.approval, "approved", `${w}: detected capability cannot carry an approved placement`);
    }
    // RFC questions are open until a decision lands in docs/CONTROL_CENTER_RFC.md.
    if (c.placement.rfc !== null) assert.equal(c.placement.approval, "open", `${w}: RFC ${c.placement.rfc} is still open`);
    // An approved placement is one that already ships; nothing new is proposed under it.
    if (c.placement.approval === "approved") {
      assert.ok(c.placement.current, `${w}: approved placement names where it ships`);
      assert.equal(c.placement.proposed, null, `${w}: approved placement has no pending proposal`);
    }
    if (c.placement.approval === "not-applicable") assert.equal(c.placement.proposed, null, `${w}: nothing proposed`);
    if (c.integration.current === "blocked") assert.ok(c.blockers.length > 0, `${w}: blocked names its blocker`);
    if (c.compat.trunk === "broken" || c.compat.trunk === "changed")
      assert.ok(c.compat.evidence.length > 0 || c.depends_on.length > 0, `${w}: trunk ${c.compat.trunk} cites evidence`);
  }
});

test("inventory: Floating Islands files and contract areas exist", () => {
  const areas = new Set(readFileSync(join(repo, "tests/contract/contract.tsv"), "utf8").split("\n")
    .filter((l) => l && !l.startsWith("#")).map((l) => l.split("\t")[0]));
  for (const c of caps) {
    for (const f of c.fi_files) assert.ok(existsSync(join(repo, f)), `${c.id}: ${f} exists`);
    for (const a of c.contract_areas) assert.ok(areas.has(a), `${c.id}: contract area ${a} exists`);
  }
});

function manifestIds(dir, out = new Map()) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) manifestIds(path, out);
    else if (name === "manifest.json" || name.endsWith(".manifest.json")) {
      const id = JSON.parse(readFileSync(path, "utf8")).id;
      if (typeof id === "string") out.set(id, path.slice(tree.length + 1));
    }
  }
  return out;
}

test("inventory: upstream references exist in the pinned Omarchy tree", { skip: !haveTree && `no Omarchy tree at ${tree}` }, () => {
  for (const c of caps.filter((c) => c.origin === "baseline")) {
    for (const p of c.upstream.paths) assert.ok(existsSync(join(tree, p)), `${c.id}: upstream path ${p} exists`);
  }
  const shipped = manifestIds(join(tree, "shell"));
  for (const c of caps.filter((c) => c.origin === "baseline")) {
    for (const id of c.upstream.ids) assert.ok(shipped.has(id), `${c.id}: upstream id ${id} is a shipped manifest`);
  }
  for (const c of caps.filter((c) => c.origin === "detected")) {
    for (const id of c.upstream.ids) assert.ok(!shipped.has(id), `${c.id}: detected id ${id} already ships; mark it baseline`);
  }
});

test("inventory: every shipped Omarchy manifest is inventoried", { skip: !haveTree && `no Omarchy tree at ${tree}` }, () => {
  const mapped = new Set(caps.flatMap((c) => c.upstream.ids));
  const missing = [...manifestIds(join(tree, "shell"))].filter(([id]) => !mapped.has(id)).map(([id, p]) => `${id} (${p})`);
  assert.deepEqual(missing, [], "manifests without a capability entry");
});
