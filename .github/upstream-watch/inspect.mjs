#!/usr/bin/env node
// Read-only upstream watcher, inspect step (docs/UPSTREAM_WATCH.md §3).
// Discovers upstream refs, fetches them blobless, diffs the relevant trees and
// writes a validated JSON report plus a Markdown dry-run summary. It never
// writes issues, never executes upstream files, and needs no credentials.
//
// Usage: node .github/upstream-watch/inspect.mjs --work <dir>
//          [--url <git url>] [--state <file>] [--emit-state <file>]
//          [--report <file>] [--summary <file>]
// Exit: 0 report written; 3 report written but a target failed (incomplete);
//       2 fail closed (bad baseline, state, discovery or report), nothing written.
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  PATH, SHA, analyze, buildReport, isDetectorInput, nextState, parseContract, parseLsRemote, parseState,
  planTarget, releaseFindings, contractRows, safeErrorText, validateInventory, validateReport,
} from "./lib.mjs";
import { aggregate, renderSummary } from "./aggregate.mjs";

const repo = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const SPARSE = ["shell", "bin", "config/omarchy", "default/hypr"];
// Practical bounds (real upstream, 2026-11: 17 MiB of objects, ~900 relevant files, ~9 MiB).
// Exceeding one fails the target or the run; it never advances state.
export const LIMITS = { files: 5000, treeBytes: 64 << 20, fileBytes: 1 << 20, objectsKiB: 1 << 20 };

class ObjectLimitError extends Error {}

// Upstream content is data: no user/system git config (no credential helpers,
// filters or hooks), symlinks checked out as plain files, no prompts.
const GIT_ENV = { ...Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith("GIT_"))), GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1", GIT_TERMINAL_PROMPT: "0", GIT_ASKPASS: "/bin/false" };
const GIT_FLAGS = ["-c", "core.symlinks=false", "-c", "core.hooksPath=/dev/null", "-c", "protocol.ext.allow=never", "-c", "advice.detachedHead=false"];

function git(dir, args, { timeout = 120_000, allowFail = false } = {}) {
  try {
    return execFileSync("git", [...GIT_FLAGS, ...(dir ? ["-C", dir] : []), ...args],
      { env: GIT_ENV, encoding: "utf8", timeout, maxBuffer: 64 << 20, stdio: ["ignore", "pipe", "pipe"] });
  } catch (e) {
    if (allowFail) return null;
    throw new Error(`git ${args[0]} failed: ${safeErrorText(String(e.stderr || e.message).split("\n")[0], 160)}`);
  }
}

export function objectStoreKiB(clone) {
  return git(clone, ["count-objects", "-v"]).match(/^(?:size|size-pack): (\d+)$/gm)?.reduce((n, l) => n + Number(l.split(" ")[1]), 0) ?? Infinity;
}

export function assertObjectStoreLimit(clone, phase) {
  const kib = objectStoreKiB(clone);
  if (kib > LIMITS.objectsKiB)
    throw new ObjectLimitError(`upstream objects use ${kib} KiB after ${phase}, above ${LIMITS.objectsKiB}; refusing to analyse`);
}

function args(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 2) {
    const k = argv[i];
    if (!["--work", "--url", "--state", "--emit-state", "--report", "--summary"].includes(k) || argv[i + 1] == null)
      throw new Error(`usage: inspect.mjs --work <dir> [--url u] [--state f] [--emit-state f] [--report f] [--summary f] (bad ${k})`);
    out[k.slice(2)] = argv[i + 1];
  }
  if (!out.work) throw new Error("--work is required");
  return out;
}

/** Relevant upstream files at one revision, read from a sparse checkout. Symlinks and odd paths are skipped. */
export function materialize(clone, sha, { isDetector } = {}) {
  git(clone, ["checkout", "--quiet", "--force", "--detach", sha], { timeout: 600_000 });
  assertObjectStoreLimit(clone, "blob hydration");
  const files = new Map();
  let bytes = 0;
  for (const entry of git(clone, ["ls-tree", "-r", "-z", "--full-tree", sha, "--", ...SPARSE]).split("\0")) {
    const m = /^(100644|100755) blob [0-9a-f]{40}\t(.+)$/.exec(entry);
    if (!m || !PATH.test(m[2])) continue;
    const abs = join(clone, m[2]);
    if (!existsSync(abs)) continue;
    const size = statSync(abs).size;
    if (size > LIMITS.fileBytes) {
      if (!isDetector || isDetector(m[2]))
        throw new Error(`detector input ${m[2]} at ${sha.slice(0, 12)} exceeds ${LIMITS.fileBytes} bytes`);
      continue;
    }
    if (files.size + 1 > LIMITS.files || (bytes += size) > LIMITS.treeBytes)
      throw new Error(`upstream tree at ${sha.slice(0, 12)} exceeds ${LIMITS.files} files or ${LIMITS.treeBytes} bytes`);
    files.set(m[2], readFileSync(abs, "utf8"));
  }
  return files;
}

function runContract(clone) {
  try {
    return execFileSync(join(repo, "tests/contract/check-contract.sh"), ["--advisory", "--porcelain"],
      { env: { ...process.env, OMARCHY_PATH: clone }, encoding: "utf8", timeout: 120_000, stdio: ["ignore", "pipe", "pipe"] });
  } catch (e) {
    if (e.status === 1 && typeof e.stdout === "string") return e.stdout; // failed rows: still a complete result
    throw new Error(`contract check did not complete: ${safeErrorText(e.message, 160)}`);
  }
}

/** Blobless, single-branch, sparse clone, created once and reused. */
export function prepareClone(url, clone, branch) {
  if (existsSync(join(clone, ".git"))) return;
  git(null, ["clone", "--quiet", "--filter=blob:none", "--no-checkout", "--single-branch", "--branch", branch, "--", url, clone], { timeout: 900_000 });
  git(clone, ["sparse-checkout", "set", ...SPARSE]);
}

export function main(argv, { inventoryPath = join(repo, "docs/upstream/capabilities.json") } = {}) {
  const opt = args(argv);
  const url = opt.url ?? "https://github.com/omacom/omarchy.git";
  const inventory = validateInventory(JSON.parse(readFileSync(inventoryPath, "utf8")));
  const state = parseState(opt.state && existsSync(opt.state) ? readFileSync(opt.state, "utf8") : null);
  const rows = contractRows(readFileSync(join(repo, "tests/contract/contract.tsv"), "utf8"));
  const baseline = inventory.revisions.baseline;

  // Discovery: branch and release names are never hardcoded.
  const discovery = parseLsRemote(git(null, ["ls-remote", "--symref", url, "HEAD", "refs/heads/*", "refs/tags/*"], { timeout: 120_000 }));
  const wanted = [
    { ref: discovery.defaultBranch, role: "trunk" },
    { ref: discovery.releaseLine, role: "release-line" },
  ];

  // Blobless clone, reused between runs; only the needed refs are fetched.
  mkdirSync(opt.work, { recursive: true });
  const clone = join(opt.work, "omarchy");
  prepareClone(url, clone, discovery.defaultBranch);
  const refspecs = wanted.map((w) => `+refs/heads/${w.ref}:refs/remotes/origin/${w.ref}`);
  const baselineTag = discovery.tags.has(baseline.ref) ? [`+refs/tags/${baseline.ref}:refs/tags/${baseline.ref}`] : [];
  const fetchError = git(clone, ["fetch", "--quiet", "--filter=blob:none", "--no-tags", "origin", ...refspecs, ...baselineTag], { timeout: 900_000, allowFail: true }) === null;
  assertObjectStoreLimit(clone, "fetch");
  const has = (sha) => SHA.test(sha ?? "") && git(clone, ["cat-file", "-e", `${sha}^{commit}`], { allowFail: true }) !== null;
  if (!has(baseline.sha)) {
    git(clone, ["fetch", "--quiet", "--filter=blob:none", "--no-tags", "origin", baseline.sha], { allowFail: true, timeout: 900_000 });
    assertObjectStoreLimit(clone, "baseline fetch");
  }
  if (!has(baseline.sha)) throw new Error(`inventory baseline ${baseline.ref} ${baseline.sha} cannot be fetched`);

  const ops = {
    has,
    isAncestor: (a, b) => git(clone, ["merge-base", "--is-ancestor", a, b], { allowFail: true }) !== null,
    mergeBase: (a, b) => { const m = git(clone, ["merge-base", a, b], { allowFail: true })?.trim(); return SHA.test(m ?? "") ? m : null; },
  };
  const isDetector = (p) => isDetectorInput(p, { inventory, rows });
  const trees = new Map();
  const tree = (sha) => trees.get(sha) ?? (trees.set(sha, { files: materialize(clone, sha, { isDetector }), contract: parseContract(runContract(clone), rows) }), trees.get(sha));

  const targets = [], findings = [];
  for (const w of wanted) {
    const head = discovery.heads.get(w.ref);
    let t = planTarget({ ...w, head, cursor: state?.refs?.[w.ref]?.processed, baseline: baseline.sha }, ops);
    if (t.status !== "failed" && !has(head)) t = { ...t, status: "failed", error: fetchError ? "fetch failed" : "incomplete fetch: head missing" };
    targets.push(t);
    if (t.status === "failed" || t.status === "unchanged") continue;
    try {
      const a = tree(t.base), b = tree(t.head);
      const cache = new Map();
      const introducing = (path) => {
        if (!t.rangeBase || !path) return null;
        if (!cache.has(path)) {
          const c = git(clone, ["log", "--format=%H", "--reverse", `${t.rangeBase}..${t.head}`, "--", path], { allowFail: true })?.split("\n")[0];
          cache.set(path, SHA.test(c ?? "") ? c : null);
        }
        return cache.get(path);
      };
      findings.push(...analyze({ inventory, target: t, rows, introducing, firstSeen: state?.refs?.[w.ref]?.first_seen ?? {},
        files: { base: a.files, head: b.files }, contract: { base: a.contract, head: b.contract } }));
    } catch (e) {
      if (e instanceof ObjectLimitError) throw e;
      Object.assign(t, { status: "failed", error: safeErrorText(e.message, 190) });
      for (let i = findings.length - 1; i >= 0; i--) if (findings[i].ref === w.ref) findings.splice(i, 1);
    }
  }
  findings.push(...releaseFindings(discovery, state, baseline.ref));

  assertObjectStoreLimit(clone, "inspection");
  const report = buildReport({ inventory, discovery, targets, findings, state });
  const json = JSON.stringify(report, null, 2) + "\n";
  validateReport(JSON.parse(json), { bytes: Buffer.byteLength(json), capabilityIds: new Set(inventory.capabilities.map((c) => c.id)) });
  if (opt.report) writeFileSync(opt.report, json);
  const summary = renderSummary(report, aggregate(report, { inventory, rows }));
  if (opt.summary) writeFileSync(opt.summary, summary); else process.stdout.write(summary);
  const incomplete = targets.some((t) => t.status === "failed");
  // A run with a failed target never advances any cursor.
  if (opt["emit-state"] && !incomplete) writeFileSync(opt["emit-state"], JSON.stringify(nextState(state, discovery, targets, findings), null, 2) + "\n");
  return incomplete ? 3 : 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try { process.exitCode = main(process.argv.slice(2)); }
  catch (e) { process.stderr.write(`upstream-watch: ${safeErrorText(e.message, 240)}\n`); process.exitCode = 2; }
}
