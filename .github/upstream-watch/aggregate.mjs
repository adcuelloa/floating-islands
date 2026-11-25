// Actionable aggregation over the raw findings of a validated report
// (docs/UPSTREAM_WATCH.md §3.3). Raw findings are never dropped: every one
// belongs to exactly one item, and every item keeps all of its members'
// evidence. A few fixed rules, no generic event engine.
import { UPSTREAM, capsForPath, clean, hash16, indexInventory, link, rowTokens, span } from "./lib.mjs";

export const CATEGORIES = ["breaking", "new-capability", "modification", "uncertain", "informational"];
// Issue policy per category. Informational items stay in the run summary.
export const POLICY = {
  "breaking": { issue: true, labels: ["upstream", "compatibility", "breaking-change"] },
  "new-capability": { issue: true, labels: ["upstream", "design-review", "enhancement"] },
  "modification": { issue: true, labels: ["upstream", "compatibility"] },
  "uncertain": { issue: true, labels: ["upstream", "needs-triage"] },
  "informational": { issue: false, labels: [] },
};
const CHANGE_RANK = ["regression", "removed", "modified", "added", "migration", "refactor", "uncertain", "release", "restored"];
// Floating Islands owns SUPER+CTRL+1..9 and SUPER+CTRL+ALT+* (AGENTS.md invariant 2).
const OWN_SHORTCUTS = /^SUPER \+ CTRL \+ (ALT \+ .+|[1-9])$/;

const dirOf = (p) => p.slice(0, p.lastIndexOf("/") + 1);
// Dedicated directory for a manifest.json plugin; flat *.manifest.json files share a parent dir and own none.
const manifestDir = (p) => (p && /(?:^|\/)manifest\.json$/.test(p) && p.startsWith("shell/plugins/") ? dirOf(p) : null);
const PRIORITY = ["D1", "D3", "D2", "D7", "D5", "D4", "D6", "D8", "D9"];
const byPriority = (a, b) =>
  PRIORITY.indexOf(a.detector) - PRIORITY.indexOf(b.detector)
  || (a.fingerprint < b.fingerprint ? -1 : a.fingerprint > b.fingerprint ? 1 : a.ref < b.ref ? -1 : a.ref > b.ref ? 1 : 0);

/** Union-find over indices. */
function components(n, edges) {
  const parent = [...Array(n).keys()];
  const find = (i) => (parent[i] === i ? i : (parent[i] = find(parent[i])));
  for (const [a, b] of edges) parent[find(a)] = find(b);
  const out = new Map();
  for (let i = 0; i < n; i++) out.set(find(i), [...(out.get(find(i)) || []), i]);
  return [...out.values()];
}

/** Title text for issues: inventory ids, our own contract wording and validated identifiers only. */
export const safeTitle = (s) => clean(s, 200).replace(/[^A-Za-z0-9 ._:/()[\]+,=-]/g, "?");

function changeOf(f) {
  switch (f.kind) {
    case "regression": return "regression";
    case "restored": return "restored";
    case "api-removed": case "manifest-removed": case "path-removed": case "cli-removed": case "config-removed": case "shortcut-removed": return "removed";
    case "api-added": return f.symbol?.startsWith("_") ? "refactor" : "added";
    case "path-touched": return "refactor";
    case "possible-blocker-resolution": return "uncertain";
    default:
      if (f.detector === "D9") return "release";
      return /-added$/.test(f.kind) ? "added" : "modified";
  }
}

function item({ category, anchor, subsystem, members, note = null }) {
  members.sort(byPriority);
  const caps = [...new Set(members.flatMap((f) => f.capabilities))].sort();
  // Primary only when every member's explicit mapping agrees on one capability.
  const primaries = new Set(members.map((f) => f.primary));
  const primary = primaries.size === 1 && members[0].primary ? members[0].primary : null;
  const changes = [...new Set(members.map(changeOf))].sort((a, b) => CHANGE_RANK.indexOf(a) - CHANGE_RANK.indexOf(b));
  const certainty = members.some((f) => f.certainty === "confirmed") ? "confirmed"
    : members.every((f) => f.certainty === "uncertain") ? "uncertain" : "textual";
  return {
    topic: hash16([category, anchor].join("\u0000")), category, change: changes[0], changes, anchor, subsystem, note,
    primary, capabilities: caps, refs: [...new Set(members.map((f) => f.ref))].sort(),
    fingerprints: [...new Set(members.map((f) => f.fingerprint))].sort(), members,
  };
}

/**
 * Items from raw findings. `rows` are contractRows() from the trusted
 * checkout; the report must already have passed validateReport().
 */
export function aggregate(report, { inventory, rows }) {
  const idx = indexInventory(inventory);
  const detected = new Set(inventory.capabilities.filter((c) => c.origin === "detected").map((c) => c.id));
  const F = report.findings;
  const claimed = new Set();
  const items = [];
  const claim = (list) => {
    for (const f of list) {
      if (claimed.has(f)) throw new Error(`aggregate: raw finding assigned more than once (${f.ref} ${f.fingerprint})`);
      claimed.add(f);
    }
    return list;
  };

  // 1. Incompatibilities: a contract regression and the removals that explain it are one item.
  const removal = F.filter((f) => f.kind === "regression" || (["api-removed", "manifest-removed", "path-removed"].includes(f.kind)));
  const edges = [];
  for (let i = 0; i < removal.length; i++) for (let j = i + 1; j < removal.length; j++) {
    const [a, b] = [removal[i], removal[j]];
    if (a.ref !== b.ref) continue;
    const pair = (x, y) => {
      if (x.kind === "regression") {
        const row = rows.get(x.subject);
        if (!row) return false;
        if (y.kind === "api-removed") return y.path === row.path && rowTokens(row).includes(y.symbol);
        return y.kind === "path-removed" && y.path === row.path; // the checked file itself is gone
      }
      // a removed qmldir type and the removed file that implemented it
      if (x.kind === "api-removed" && x.path?.endsWith("qmldir") && y.kind === "path-removed")
        return y.symbol === x.symbol && dirOf(y.path) === dirOf(x.path);
      if (x.kind === "manifest-removed" && y.kind === "path-removed") return x.path === y.path;
      return false;
    };
    if (pair(a, b) || pair(b, a)) edges.push([i, j]);
  }
  for (const comp of components(removal.length, edges)) {
    const members = comp.map((i) => removal[i]);
    if (!members.some((f) => f.kind === "regression" || f.severity === "breaking")) continue; // plain removals are modifications
    // the same file merely changing is supporting evidence of this incompatibility
    const paths = new Set(members.map((f) => f.path));
    members.push(...F.filter((g) => g.kind === "path-touched" && g.ref === members[0].ref && paths.has(g.path) && !claimed.has(g) && !members.includes(g)));
    const lead = [...members].sort(byPriority)[0];
    const hasBreaking = members.some((f) => f.severity === "breaking");
    const optIn = !hasBreaking && members.some((f) => f.kind === "regression");
    items.push(item({ category: hasBreaking ? "breaking" : "modification", anchor: `${lead.subject}`, subsystem: lead.path ?? lead.scope,
      members: claim(members), note: optIn ? "Affects an opt-in feature only (conditional contract row)." : null }));
  }

  // 2. New capabilities: a manifest the inventory does not ship, plus what came with it.
  // Reserve independent manifest leaders before assigning supporting evidence so no leader can be claimed twice.
  const leaders = F.filter((f) => !claimed.has(f) && f.detector === "D3" && (f.kind === "capability-new" || (f.kind === "manifest-added" && detected.has(f.primary))));
  const leaderSet = new Set(leaders);
  for (const f of leaders) {
    if (claimed.has(f)) continue;
    const dir = manifestDir(f.path);
    const extra = F.filter((g) => !claimed.has(g) && !leaderSet.has(g) && g !== f && g.ref === f.ref && dir && g.path?.startsWith(dir));
    items.push(item({ category: "new-capability", anchor: `manifest ${f.symbol}`, subsystem: dir ?? f.path, members: claim([f, ...extra]),
      note: "A finding, not an approved feature. Integration and placement stay open for maintainer and community review." }));
  }

  // 3. Shortcuts: one item per migration context (files linked by a combination that moved between them).
  const sc = F.filter((f) => !claimed.has(f) && f.detector === "D5");
  for (const ref of [...new Set(sc.map((f) => f.ref))].sort()) {
    const mine = sc.filter((f) => f.ref === ref);
    const files = [...new Set(mine.map((f) => f.path))].sort();
    const links = [];
    for (const r of mine.filter((f) => f.kind === "shortcut-removed"))
      for (const a of mine.filter((f) => f.kind === "shortcut-added" && f.symbol === r.symbol && f.path !== r.path))
        links.push([files.indexOf(r.path), files.indexOf(a.path)]);
    for (const comp of components(files.length, links)) {
      const paths = comp.map((i) => files[i]).sort();
      const members = [...mine.filter((f) => paths.includes(f.path)),
        ...F.filter((g) => g.kind === "path-touched" && g.ref === ref && paths.includes(g.path) && !claimed.has(g))];
      const moved = paths.length > 1;
      const own = members.filter((f) => OWN_SHORTCUTS.test(f.symbol ?? ""));
      const mapped = members.some((f) => f.capabilities.length);
      const it = item({ category: own.length || mapped ? "modification" : "informational",
        anchor: `shortcuts ${paths.join(" ")}`, subsystem: `shortcuts: ${paths.map((p) => p.replace(/^default\/hypr\//, "")).join(", ")}`,
        members: claim(members),
        note: [moved ? "Bindings moved between these files." : null,
          own.length ? `Touches the SUPER+CTRL(+ALT) range Floating Islands uses (${own.length} bindings, listed below).` : null].filter(Boolean).join(" ") || null });
      if (moved) it.change = "migration";
      items.push(it);
    }
  }

  // 4. Possible blocker resolutions: always uncertain, one item per blocker.
  const d8 = F.filter((f) => !claimed.has(f) && f.detector === "D8");
  for (const id of [...new Set(d8.map((f) => f.subject.split(" ")[1]))].sort())
    items.push(item({ category: "uncertain", anchor: `blocker ${id}`, subsystem: `blocker ${id}`,
      members: claim(d8.filter((f) => f.subject.split(" ")[1] === id)), note: "Watch tokens appeared in added lines. Nothing is confirmed." }));

  // 5. Releases and restored contract rows: informational, one each.
  for (const f of F.filter((f) => !claimed.has(f) && (f.detector === "D9" || f.kind === "restored")))
    items.push(item({ category: "informational", anchor: f.subject, subsystem: f.scope, members: claim([f]) }));

  // 6. Everything else: one item per file (subsystem). Pure refactors are informational.
  const rest = F.filter((f) => !claimed.has(f));
  for (const key of [...new Set(rest.map((f) => f.path ?? f.scope))].sort()) {
    const members = claim(rest.filter((f) => (f.path ?? f.scope) === key));
    const it = item({ category: "modification", anchor: `subsystem ${key}`, subsystem: key, members });
    if (it.change === "refactor") it.category = "informational";
    else if (it.certainty === "uncertain") it.category = "uncertain";
    if (it.category !== "modification") it.topic = hash16([it.category, it.anchor].join("\u0000"));
    items.push(it);
  }

  if (claimed.size !== F.length) throw new Error("aggregate: a raw finding was not assigned"); // never drop evidence
  // One topic per item across refs: the same break on trunk and the release line is one item.
  const merged = new Map();
  for (const it of items) {
    const prev = merged.get(it.topic);
    if (!prev) { merged.set(it.topic, it); continue; }
    merged.set(it.topic, { ...item({ category: it.category, anchor: it.anchor, subsystem: it.subsystem, members: [...prev.members, ...it.members], note: it.note }), change: prev.change });
  }
  const out = [...merged.values()].sort((a, b) => CATEGORIES.indexOf(a.category) - CATEGORIES.indexOf(b.category) || (a.subsystem < b.subsystem ? -1 : a.subsystem > b.subsystem ? 1 : a.topic < b.topic ? -1 : 1));
  const counts = new Map();
  for (const it of out) for (const f of it.members) counts.set(f, (counts.get(f) || 0) + 1);
  if (counts.size !== F.length || F.some((f) => counts.get(f) !== 1))
    throw new Error("aggregate: every raw finding must belong to exactly one item");
  return out;
}

export function itemTitle(it) {
  const caps = it.capabilities.length ? it.capabilities.join(", ") : "unmapped";
  const what = it.category === "breaking" ? `Upstream breaking change: ${it.anchor.replace(/^\[[\w-]+(?:#[0-9a-f]+)?\] /, "")}`
    : it.category === "new-capability" ? `New upstream capability: ${it.anchor.replace(/^manifest /, "")}`
    : it.category === "uncertain" ? `Upstream triage: ${it.anchor}`
    : `Upstream ${it.change} in ${it.subsystem}`;
  return safeTitle(`${what} [${caps}]`);
}

const ATTRIBUTION = {
  "first-commit-touching-file": "first commit in the range that touched the file; not verified as the commit that made this change",
  "first-seen-at-head": "history was rewritten; head where it was first seen",
  "recorded-in-state": "recorded by an earlier run",
  "release-ref": "release ref",
  "unavailable": "unavailable",
};

// Every finding comes from a static source or contract check; none is a demonstrated runtime failure.
export const CERTAINTY = {
  confirmed: "static check failed (runtime impact not demonstrated)",
  textual: "textual source diff",
  uncertain: "uncertain",
};

/** Markdown for one item's evidence: every member, every evidence line. Upstream text only in code. */
export function renderEvidence(it) {
  const out = [];
  for (const f of it.members) {
    const attr = f.attribution.sha ? `${f.attribution.sha.slice(0, 12)} (${ATTRIBUTION[f.attribution.basis]})` : ATTRIBUTION.unavailable;
    out.push(`- ${f.detector} ${f.kind}, ${f.severity}, ${CERTAINTY[f.certainty]}, on ${span(f.ref)}: ${span(f.subject)}`,
      `  - fingerprint \`${f.fingerprint}\`; attribution ${attr}`);
    for (const e of f.evidence) out.push(`  - ${link(e)}${e.text ? ` ${span(e.text)}` : ""}`);
  }
  return out;
}

export function renderSummary(report, items) {
  const out = [`## Upstream watch dry-run (${UPSTREAM})`, "",
    `Baseline ${span(report.baseline.ref)} \`${report.baseline.sha.slice(0, 12)}\`. Release line ${span(report.discovery.release_line)}, latest tag ${span(report.discovery.latest_tag ?? "none")}. Nothing was filed.`, "",
    "| Target | Role | Base | Head | Status |", "|---|---|---|---|---|"];
  for (const t of report.targets)
    out.push(`| ${span(t.ref)} | ${t.role} | ${t.base ? `\`${t.base.slice(0, 12)}\`` : "-"} | ${t.head ? `\`${t.head.slice(0, 12)}\`` : "-"} | ${t.status}${t.error ? `: ${span(t.error)}` : ""} |`);
  const count = (c) => items.filter((i) => i.category === c).length;
  out.push("", `Raw findings: ${report.findings.length} (${report.totals.breaking} breaking, ${report.totals.review} review, ${report.totals.info} info).`,
    `Items: ${CATEGORIES.map((c) => `${count(c)} ${c}`).join(", ")}. Issue candidates (non-informational items): ${items.filter((i) => POLICY[i.category].issue).length}.`,
    "Issue writes are planned by the reporter against existing issues and per-run bounds; this summary files nothing.");
  for (const c of CATEGORIES) {
    const list = items.filter((i) => i.category === c);
    if (!list.length) continue;
    out.push("", `### ${c} (${list.length})`);
    for (const it of list) {
      out.push("", `#### ${span(itemTitle(it))}`, "",
        `topic \`${it.topic}\` · change ${it.change}${it.changes.length > 1 ? ` (also ${it.changes.slice(1).join(", ")})` : ""} · refs ${it.refs.map(span).join(", ")} · primary ${it.primary ? span(it.primary) : "none"} · ${it.members.length} raw findings`);
      if (it.note) out.push("", `> ${clean(it.note, 400)}`);
      out.push("", ...renderEvidence(it));
    }
  }
  return out.join("\n") + "\n";
}
