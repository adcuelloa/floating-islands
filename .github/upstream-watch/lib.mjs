// Pure part of the read-only upstream watcher (docs/UPSTREAM_WATCH.md §3).
// No I/O here: inspect.mjs reads git and runs the contract check, then hands
// plain data to these functions. Everything upstream is untrusted data.
import { createHash } from "node:crypto";

export const SCHEMA = 1;
export const UPSTREAM = "omacom/omarchy";
export const LIMITS = { bytes: 1 << 20, findings: 500, evidence: 50, text: 200, list: 200 };
export const SHA = /^[0-9a-f]{40}$/;
export const PATH = /^(?!\/)(?!.*(^|\/)\.\.?(\/|$))[A-Za-z0-9._/+-]{1,300}$/;
export const REF = /^(?!.*\.\.)(?![./-])[A-Za-z0-9._/-]{1,100}$/;
const FP = /^[0-9a-f]{16}$/;
const RANGES = [[0x00, 0x1f], [0x7f, 0x9f], [0x200e, 0x200f], [0x2028, 0x2029], [0x202a, 0x202e], [0x2066, 0x2069]];
// Control, bidi and line-separator characters (built from code points so the source stays plain ASCII).
const UNSAFE = new RegExp(`[${RANGES.map(([a, b]) => `${String.fromCharCode(a)}-${String.fromCharCode(b)}`).join("")}]`, "g");

// ---------- hashing and safe text

export const hash16 = (s) => createHash("sha256").update(s).digest("hex").slice(0, 16);
export const digest = (text) => (text == null ? "absent" : hash16(text));

/** One line of untrusted text: no control/bidi characters, no marker opener, capped. */
export function clean(text, max = LIMITS.text) {
  const s = String(text).replace(UNSAFE, " ").replace(/<!--/g, "<! --").trim();
  const cps = Array.from(s);
  return cps.length > max ? cps.slice(0, max - 1).join("") + "…" : s;
}

const longestRun = (s) => Math.max(0, ...(s.match(/`+/g) || []).map((r) => r.length));

/** Inline code span that the text cannot close: mentions, links and #refs stay inert. */
export function span(text) {
  const s = clean(text);
  const tick = "`".repeat(longestRun(s) + 1);
  return `${tick} ${s} ${tick}`;
}

/** Fenced block longer than any backtick run inside. */
export function fence(lines) {
  const body = lines.map((l) => clean(l, 400)).join("\n");
  const tick = "`".repeat(Math.max(3, longestRun(body) + 1));
  return `${tick}text\n${body}\n${tick}`;
}

export function fingerprint(f) {
  return hash16([f.group, f.detector, f.subject, f.before, f.after, f.introducing ?? "none"].join("\u0000"));
}
/** Same change, whatever commit introduced it: keys state.first_seen. */
export const contentKey = (f) => hash16([f.group, f.detector, f.subject, f.before, f.after].join("\u0000"));

// ---------- extractors (text -> Map(subject -> { sig, line }))

function collect(text, match) {
  const out = new Map();
  text.split("\n").forEach((raw, i) => {
    const hit = match(raw.trim());
    if (!hit) return;
    const [subject, sig] = hit;
    const prev = out.get(subject);
    if (!prev) out.set(subject, { sig, line: i + 1 });
    else if (!prev.sig.split(" | ").includes(sig)) prev.sig = [...prev.sig.split(" | "), sig].sort().join(" | ");
  });
  return out;
}

/** QML API surface: property/signal/function signatures (not values), IPC targets; qmldir types. */
export function apiSymbols(path, text) {
  if (path.endsWith("qmldir"))
    return collect(text, (l) => {
      const m = /^(?:singleton\s+)?([A-Z]\w*)\s+(\d+\.\d+)\s+(\S+)$/.exec(l);
      return m && [`type ${m[1]}`, l.replace(/\s+/g, " ")];
    });
  return collect(text, (l) => {
    let m;
    if ((m = /^((?:(?:readonly|required|default)\s+)*)property\s+([\w.<>]+)\s+(\w+)/.exec(l)))
      return [`property ${m[3]}`, `${m[1].replace(/\s+/g, " ")}property ${m[2]} ${m[3]}`];
    if ((m = /^signal\s+(\w+)\s*(\([^)]*\))?/.exec(l))) return [`signal ${m[1]}`, `signal ${m[1]}${(m[2] || "()").replace(/\s+/g, "")}`];
    if ((m = /^function\s+(\w+)\s*\(([^)]*)\)/.exec(l))) return [`function ${m[1]}`, `function ${m[1]}(${m[2].replace(/\s+/g, "")})`];
    if ((m = /^target:\s*"([^"]+)"/.exec(l))) return [`ipc-target ${m[1]}`, `target ${m[1]}`];
    return null;
  });
}

/** `# omarchy:key=value` header of a shell CLI script. */
export function cliHeader(text) {
  return text.split("\n").filter((l) => /^# omarchy:\w+=/.test(l)).join("\n");
}

const combo = (s) => s.toUpperCase().replace(/\s*\+\s*/g, " + ").replace(/\s+/g, " ").trim();
/** `o.bind("COMBO", "Description", ...)` and `o.bind_hold(...)` in Hyprland Lua bindings. */
export function shortcuts(text) {
  return collect(text, (l) => {
    const m = /^o\.bind(?:_hold)?\(\s*"([^"]+)"\s*,\s*"([^"]*)"(.*)$/.exec(l);
    return m && [`shortcut ${combo(m[1])}`, `${m[2]}${m[3].replace(/\s+/g, " ")}`];
  });
}

export const stable = (v) =>
  Array.isArray(v) ? `[${v.map(stable).join(",")}]`
  : v && typeof v === "object" ? `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${stable(v[k])}`).join(",")}}`
  : JSON.stringify(v);

/** Leaves of the default shell.json `.bar` subtree; arrays are one leaf (their order matters). */
export function barOptions(text) {
  const out = new Map();
  let root;
  try { root = JSON.parse(text); } catch { return null; }
  const walk = (v, key) => {
    if (v && typeof v === "object" && !Array.isArray(v)) for (const k of Object.keys(v).sort()) walk(v[k], `${key}.${k}`);
    else out.set(`option ${key}`, { sig: stable(v), line: null });
  };
  if (root && typeof root.bar === "object") walk(root.bar, "bar");
  return out;
}

/** Manifest id -> canonical JSON; unparseable files are reported by path. */
export function manifests(files) {
  const out = new Map();
  for (const [path, text] of files) {
    if (!/^shell\/.*manifest\.json$/.test(path)) continue;
    let m;
    try { m = JSON.parse(text); } catch { m = null; }
    if (m && typeof m.id === "string" && m.id) out.set(m.id, { path, json: m, sig: stable(m) });
    else out.set(`invalid:${path}`, { path, json: null, sig: digest(text) });
  }
  return out;
}

/** Contract output (`check-contract.sh [--advisory]`, not --quiet) -> Map("[area] reason" -> ok|FAIL|WARN). */
export function parseContract(output) {
  const out = new Map();
  for (const l of output.split("\n")) {
    const m = /^(ok  |FAIL|WARN) (\[[\w-]+\]) (?:\(conditional\) )?(.+)$/.exec(l);
    if (m) out.set(`${m[2]} ${m[3]}`, m[1].trim());
  }
  return out;
}

/** contract.tsv rows on the upstream tree -> Map(key -> { area, path, mode, pattern }). */
export function contractRows(tsv) {
  const out = new Map();
  for (const l of tsv.split("\n")) {
    if (!l.trim() || l.startsWith("#")) continue;
    const [area, file, mode, pattern, reason] = l.split("\t");
    if (!file.startsWith("$OMARCHY/")) continue; // Quickshell rows use the pinned runtime, never upstream
    out.set(`[${area}] ${reason}`, { area, path: file.slice(9), mode: mode.replace("?", ""), pattern, conditional: mode.endsWith("?") });
  }
  return out;
}

function rowLine(row, text) {
  if (text == null) return null;
  let re = null;
  if (row.mode === "E") try { re = new RegExp(row.pattern); } catch { return null; }
  const i = text.split("\n").findIndex((l) => (re ? re.test(l) : l.includes(row.pattern)));
  return i < 0 ? null : i + 1;
}

/** Identifiers a contract row's pattern names (used to correlate evidence). */
export const rowTokens = (row) => row.pattern.match(/[A-Za-z_]\w*/g) || [];

// ---------- inventory

export function validateInventory(inv) {
  const bad = (why) => { throw new Error(`inventory baseline unusable: ${why}`); };
  if (!inv || inv.schema !== 1 || !Array.isArray(inv.capabilities)) bad("schema");
  for (const name of ["baseline", "release_line", "trunk"]) {
    const r = inv.revisions?.[name];
    if (!r || !SHA.test(r.sha) || !REF.test(r.ref)) bad(`revisions.${name}`);
  }
  return inv;
}

export function indexInventory(inv) {
  const byId = new Map(), byPath = new Map(), byArea = new Map();
  const add = (map, k, id) => map.set(k, [...(map.get(k) || []), id]);
  for (const c of inv.capabilities) {
    for (const id of c.upstream.ids) byId.set(id, c.id);
    for (const p of c.upstream.paths) add(byPath, p, c.id);
    for (const a of c.contract_areas) add(byArea, a, c.id);
  }
  const blockers = inv.capabilities.flatMap((c) => c.blockers.map((b) => ({ cap: c.id, id: b.id, watch: b.watch })));
  return { byId, byPath, byArea, blockers };
}

/** Capabilities a path belongs to: exact inventory path, else the same plugin directory. */
export function capsForPath(idx, path) {
  if (idx.byPath.has(path)) return [...new Set(idx.byPath.get(path))].sort();
  const dir = /^shell\/plugins\/(?:[^/]+\/)?[^/]+\//.exec(path)?.[0];
  if (!dir) return [];
  return [...new Set([...idx.byPath].filter(([p]) => p.startsWith(dir)).flatMap(([, ids]) => ids))].sort();
}

// ---------- detectors

const API_FILE = /^shell\/(shell\.qml|services\/Plugin\w*\.qml|Ui\/(PluginBarApi|KeyboardPanel)\.qml|(Ui|Commons)\/qmldir|Commons\/(Color|Style|ShellIpc|IpcRegistry|Util)\.qml)$/;
const CLI_FILE = /^bin\/omarchy-(bar|shell[\w-]*|plugin-[\w-]+|toggle-bar)$/;
const BIND_FILE = /^default\/hypr\/.*\.lua$/;
const CONFIG_FILE = "config/omarchy/shell.json";

function diffMaps(a, b) {
  const out = [];
  for (const k of new Set([...a.keys(), ...b.keys()])) {
    const x = a.get(k), y = b.get(k);
    if (x?.sig !== y?.sig) out.push({ subject: k, before: x ?? null, after: y ?? null });
  }
  return out;
}

const kindFor = (prefix, d) => `${prefix}-${!d.before ? "added" : !d.after ? "removed" : "changed"}`;

/**
 * Findings for one target. `files.{base,head}` map upstream paths to text;
 * `contract.{base,head}` are parseContract() maps (or null when not run);
 * `introducing(path)` returns the first commit in range touching the path.
 */
export function analyze({ inventory, target, files, contract, rows, introducing, firstSeen = {} }) {
  const idx = indexInventory(inventory);
  const raw = [];
  const uncertain = target.status === "history-rewrite";
  const emit = (f) => raw.push(f);
  const ev = (side, path, line, text) => ({ sha: side === "base" ? target.base : target.head, path, line: line ?? null, text: text == null ? null : clean(text) });
  const both = (path, d) => [
    ...(d.before ? [ev("base", path, d.before.line, d.before.sig)] : []),
    ...(d.after ? [ev("head", path, d.after.line, d.after.sig)] : []),
  ];

  // D1 contract
  if (contract?.base && contract?.head) {
    for (const [key, row] of rows) {
      const was = contract.base.get(key) ?? "ok", now = contract.head.get(key) ?? "ok";
      if ((was === "ok") === (now === "ok")) continue;
      const byArea = idx.byArea.get(row.area) || [];
      const narrowed = byArea.filter((c) => capsForPath(idx, row.path).includes(c));
      const caps = [...new Set(narrowed.length ? narrowed : byArea)].sort();
      const regressed = now !== "ok";
      emit({
        detector: "D1", kind: regressed ? "regression" : "restored", caps, fallback: `contract:${row.area}`, symbol: null,
        severity: regressed ? (now === "FAIL" ? "breaking" : "review") : "info",
        certainty: "confirmed", subject: key, path: row.path,
        before: was, after: now,
        evidence: [ev("base", row.path, rowLine(row, files.base.get(row.path)), row.pattern),
          ev("head", row.path, rowLine(row, files.head.get(row.path)), regressed ? `${now}: not found` : "found")],
      });
    }
  }

  // D2 API surface
  // Breaking only when a contract row on the same file names the symbol: the
  // inventory's prose api (e.g. "PluginBarApi._* callbacks") is too coarse.
  const named = (path, name) => [...rows.values()].some((r) => r.path === path && rowTokens(r).includes(name));
  for (const path of [...new Set([...files.base.keys(), ...files.head.keys()])].filter((p) => API_FILE.test(p)).sort()) {
    const a = files.base.has(path) ? apiSymbols(path, files.base.get(path)) : new Map();
    const b = files.head.has(path) ? apiSymbols(path, files.head.get(path)) : new Map();
    for (const d of diffMaps(a, b)) {
      const kind = kindFor("api", d);
      const name = d.subject.split(" ")[1];
      emit({
        detector: "D2", kind, caps: capsForPath(idx, path), fallback: `unmapped:${path}`,
        severity: kind === "api-removed" && named(path, name) ? "breaking" : "review",
        certainty: "textual", subject: `${path} ${d.subject}`, path, symbol: name,
        before: d.before?.sig ?? null, after: d.after?.sig ?? null, evidence: both(path, d),
      });
    }
  }

  // D3 manifests: added, removed, changed; unmapped ids are potential new functionality
  const ma = manifests(files.base), mb = manifests(files.head);
  for (const id of [...new Set([...ma.keys(), ...mb.keys()])].sort()) {
    const x = ma.get(id), y = mb.get(id);
    if (x?.sig === y?.sig) continue;
    const mapped = idx.byId.get(id);
    const safeId = /^[A-Za-z0-9._-]{1,100}$/.test(id) ? id : `manifest-${hash16(id)}`;
    const kind = !x ? (mapped ? "manifest-added" : "capability-new") : !y ? "manifest-removed" : "manifest-changed";
    const changed = x?.json && y?.json
      ? [...new Set([...Object.keys(x.json), ...Object.keys(y.json)])].filter((k) => stable(x.json[k]) !== stable(y.json[k])).sort()
      : [];
    emit({
      detector: "D3", kind, caps: mapped ? [mapped] : [], fallback: `unmapped:${safeId}`, symbol: safeId,
      severity: kind === "manifest-removed" && mapped ? "breaking" : "review",
      certainty: id.startsWith("invalid:") ? "uncertain" : "confirmed", subject: `manifest ${id}`, path: (y || x).path,
      before: x?.sig ?? null, after: y?.sig ?? null,
      evidence: [...(x ? [ev("base", x.path, 1, changed.length ? `changed keys: ${changed.join(", ")}` : x.json?.kind ?? null)] : []),
        ...(y ? [ev("head", y.path, 1, changed.length ? `changed keys: ${changed.join(", ")}` : stable(y.json?.kinds ?? y.json?.kind ?? null))] : [])],
    });
  }

  // D4 CLI headers, D5 shortcuts
  for (const path of [...new Set([...files.base.keys(), ...files.head.keys()])].sort()) {
    if (CLI_FILE.test(path)) {
      const a = files.base.get(path), b = files.head.get(path);
      const x = a == null ? null : cliHeader(a), y = b == null ? null : cliHeader(b);
      if (x === y) continue;
      const d = { before: x == null ? null : { sig: x, line: 1 }, after: y == null ? null : { sig: y, line: 1 } };
      emit({ detector: "D4", kind: kindFor("cli", d), caps: capsForPath(idx, path), fallback: `unmapped:${path}`,
        severity: "review", certainty: "textual", subject: `cli ${path.slice(4)}`, path, symbol: path.slice(4), before: x, after: y, evidence: both(path, d) });
    } else if (BIND_FILE.test(path)) {
      const a = files.base.has(path) ? shortcuts(files.base.get(path)) : new Map();
      const b = files.head.has(path) ? shortcuts(files.head.get(path)) : new Map();
      for (const d of diffMaps(a, b))
        emit({ detector: "D5", kind: kindFor("shortcut", d), caps: capsForPath(idx, path), fallback: "unmapped:shortcuts",
          severity: "review", certainty: "textual", subject: `${path} ${d.subject}`, path, symbol: d.subject.slice(9),
          before: d.before?.sig ?? null, after: d.after?.sig ?? null, evidence: both(path, d) });
    }
  }

  // D6 default bar configuration
  if (files.base.has(CONFIG_FILE) || files.head.has(CONFIG_FILE)) {
    const a = barOptions(files.base.get(CONFIG_FILE) ?? "{}"), b = barOptions(files.head.get(CONFIG_FILE) ?? "{}");
    if (!a || !b) emit({ detector: "D6", kind: "config-invalid", caps: capsForPath(idx, CONFIG_FILE), fallback: "unmapped:config",
      severity: "review", certainty: "uncertain", subject: `${CONFIG_FILE} unparseable`, path: CONFIG_FILE,
      before: digest(files.base.get(CONFIG_FILE)), after: digest(files.head.get(CONFIG_FILE)), evidence: [ev(a ? "head" : "base", CONFIG_FILE, null, null)] });
    else for (const d of diffMaps(a, b))
      emit({ detector: "D6", kind: kindFor("config", d), caps: capsForPath(idx, CONFIG_FILE), fallback: "unmapped:config",
        severity: "review", certainty: "textual", subject: d.subject, path: CONFIG_FILE, symbol: d.subject.slice(7),
        before: d.before?.sig ?? null, after: d.after?.sig ?? null, evidence: both(CONFIG_FILE, { before: d.before && { ...d.before, sig: `${d.subject.slice(7)} = ${d.before.sig}` }, after: d.after && { ...d.after, sig: `${d.subject.slice(7)} = ${d.after.sig}` } }) });
  }

  // D7 inventoried paths that moved away or changed; new plugin directories
  for (const path of [...idx.byPath.keys()].sort()) {
    const a = files.base.get(path), b = files.head.get(path);
    if (a === b || (a == null && b == null)) continue;
    const kind = b == null ? "path-removed" : a == null ? "path-added" : "path-touched";
    emit({ detector: "D7", kind, caps: capsForPath(idx, path), fallback: `unmapped:${path}`,
      severity: kind === "path-removed" ? "review" : "info", certainty: "textual", subject: `path ${path}`, path,
      symbol: path.split("/").pop().replace(/\.[^.]*$/, ""),
      before: digest(a), after: digest(b), evidence: [ev(b == null ? "base" : "head", path, null, null)] });
  }
  const dirs = (m) => new Set([...m.keys()].map((p) => /^shell\/plugins\/[^/]+\/[^/]+\//.exec(p)?.[0]).filter(Boolean));
  const oldDirs = dirs(files.base);
  for (const dir of [...dirs(files.head)].filter((d) => !oldDirs.has(d)).sort()) {
    if ([...files.head.keys()].some((p) => p.startsWith(dir) && p.endsWith("manifest.json"))) continue; // D3 reports it
    const path = [...files.head.keys()].filter((p) => p.startsWith(dir)).sort()[0];
    emit({ detector: "D7", kind: "unmapped", caps: [], fallback: `unmapped:${dir.slice(0, -1)}`, severity: "review",
      certainty: "textual", subject: `directory ${dir}`, path, before: null, after: "present", evidence: [ev("head", path, null, null)] });
  }

  // D8 blocker watch tokens in added lines (never confirmed)
  for (const path of [...files.head.keys()].filter((p) => p.startsWith("shell/")).sort()) {
    const a = files.base.get(path) ?? "", b = files.head.get(path);
    if (a === b) continue;
    const old = new Set(a.split("\n").map((l) => l.trim()));
    const added = b.split("\n").map((l, i) => [l.trim(), i + 1]).filter(([l]) => l && !old.has(l));
    const caps = capsForPath(idx, path);
    // Only the blocker's own capability files and the host API files: watch tokens are short words.
    for (const bl of idx.blockers.filter((b) => caps.includes(b.cap) || API_FILE.test(path))) for (const token of bl.watch) {
      const word = new RegExp(`(^|[^A-Za-z0-9_])${token.replace(/[^A-Za-z0-9_]/g, "")}($|[^A-Za-z0-9_])`);
      const hit = added.find(([l]) => word.test(l));
      if (!hit) continue;
      emit({ detector: "D8", kind: "possible-blocker-resolution", caps: [bl.cap], fallback: bl.cap, severity: "review",
        certainty: "uncertain", subject: `blocker ${bl.id} token ${token} in ${path}`, path, symbol: token, before: null, after: hit[0],
        evidence: [ev("head", path, hit[1], hit[0])] });
    }
  }

  // finalize: scope, qualified attribution, fingerprint
  const seen = new Set();
  return raw.flatMap((f) => {
    const caps = [...new Set(f.caps)].sort();
    // A primary capability only when the mapping names exactly one (manifest id, or a single inventory path/area).
    const primary = caps.length === 1 ? caps[0] : null;
    const scope = primary ?? (caps.length ? "multi" : f.fallback);
    const base = { group: caps.length ? caps.join(",") : f.fallback, detector: f.detector, subject: clean(f.subject), before: digest(f.before), after: digest(f.after) };
    const key = contentKey(base);
    const attribution = firstSeen[key] ? { sha: firstSeen[key], basis: "recorded-in-state" }
      : uncertain ? { sha: target.head, basis: "first-seen-at-head" }
      : (() => { const c = introducing(f.path); return c ? { sha: c, basis: "first-commit-touching-file" } : { sha: null, basis: "unavailable" }; })();
    const fp = fingerprint({ ...base, introducing: attribution.sha });
    if (seen.has(fp)) return [];
    seen.add(fp);
    return [{
      fingerprint: fp, key, scope, primary, capabilities: caps.slice(0, LIMITS.list), detector: f.detector, kind: f.kind,
      severity: f.severity, certainty: uncertain && f.certainty !== "confirmed" ? "uncertain" : f.certainty,
      ref: target.ref, subject: base.subject, path: f.path && PATH.test(f.path) ? f.path : null,
      symbol: f.symbol == null ? null : clean(f.symbol), attribution, evidence: f.evidence.slice(0, LIMITS.evidence),
    }];
  });
}

// ---------- ranges, state, releases

/**
 * Decide the range for one ref. `git` answers has(sha), isAncestor(a, b),
 * mergeBase(a, b) (null when none). Without a cursor the range is cumulative
 * from the human-reviewed baseline.
 */
export function planTarget({ ref, role, head, cursor, baseline }, git) {
  if (!head) return { ref, role, base: cursor ?? baseline, head: null, status: "failed", error: "ref not found upstream" };
  if (!cursor) {
    if (!git.has(baseline)) return { ref, role, base: baseline, head, status: "failed", error: "baseline revision not fetched" };
    return { ref, role, base: baseline, head, status: baseline === head ? "unchanged" : "cumulative", rangeBase: git.mergeBase(baseline, head) };
  }
  if (cursor === head) return { ref, role, base: cursor, head, status: "unchanged", rangeBase: cursor };
  if (git.has(cursor) && git.isAncestor(cursor, head)) return { ref, role, base: cursor, head, status: "changed", rangeBase: cursor };
  const mb = git.has(cursor) ? git.mergeBase(cursor, head) : null;
  return { ref, role, base: mb ?? baseline, head, status: "history-rewrite", rangeBase: mb };
}

const version = (name) => {
  const m = /^v(\d+)[.-](\d+)[.-](\d+)(?:-rc(\d+))?$/.exec(name);
  return m ? [+m[1], +m[2], +m[3], m[4] == null ? Infinity : +m[4]] : null;
};
export const compareVersions = (a, b) => {
  const x = version(a), y = version(b);
  for (let i = 0; i < 4; i++) if (x[i] !== y[i]) return x[i] < y[i] ? -1 : 1;
  return 0;
};

/** Upstream discovery from `git ls-remote --symref <url> HEAD 'refs/heads/*' 'refs/tags/*'`. */
export function parseLsRemote(text) {
  const heads = new Map(), tags = new Map();
  let defaultBranch = null;
  for (const l of text.split("\n")) {
    let m;
    if ((m = /^ref: refs\/heads\/(\S+)\tHEAD$/.exec(l))) defaultBranch = m[1];
    else if ((m = /^([0-9a-f]{40})\trefs\/heads\/(\S+)$/.exec(l))) heads.set(m[2], m[1]);
    else if ((m = /^([0-9a-f]{40})\trefs\/tags\/(\S+?)(\^\{\})?$/.exec(l))) { if (m[3] || !tags.has(m[2])) tags.set(m[2], m[1]); }
  }
  if (!defaultBranch || !REF.test(defaultBranch) || !heads.has(defaultBranch)) throw new Error("discovery: no default branch");
  const releaseBranches = [...heads.keys()].filter((b) => /^v\d+-\d+-\d+$/.test(b)).sort(compareVersions);
  if (!releaseBranches.length) throw new Error("discovery: no release branch");
  const releaseTags = [...tags.keys()].filter((t) => /^v\d+\.\d+\.\d+(-rc\d+)?$/.test(t)).sort(compareVersions);
  const tagged = new Set(releaseTags.map((t) => t.replace(/-rc\d+$/, "").replace(/\./g, "-")).filter((t, i) => !/-rc\d+$/.test(releaseTags[i])));
  const releaseLine = [...releaseBranches].reverse().find((b) => !tagged.has(b)) ?? releaseBranches.at(-1);
  return { defaultBranch, heads, tags, releaseBranches, releaseTags, releaseLine };
}

/** D9: new tags and release branches since the state (or newer than the baseline tag without state). */
export function releaseFindings(discovery, state, baselineRef) {
  const out = [];
  const known = (name, seen) => (seen ? seen.includes(name) : version(name) && compareVersions(name, baselineRef) <= 0);
  for (const t of discovery.releaseTags)
    if (!known(t, state?.tags_seen)) out.push({ kind: t.includes("-rc") ? "prerelease" : "release", name: t, sha: discovery.tags.get(t) });
  for (const b of discovery.releaseBranches)
    if (!known(b, state?.release_branches_seen)) out.push({ kind: "release-branch-added", name: b, sha: discovery.heads.get(b) });
  for (const b of state?.release_branches_seen ?? [])
    if (!discovery.heads.has(b)) out.push({ kind: "release-branch-gone", name: b, sha: null });
  return out.map((r) => {
    const base = { group: `release:${r.name}`, detector: "D9", subject: `${r.kind} ${r.name}`, before: "absent", after: r.sha ?? "absent" };
    return { fingerprint: fingerprint({ ...base, introducing: r.sha }), key: contentKey(base), scope: base.group, primary: null, capabilities: [],
      detector: "D9", kind: r.kind, severity: "info", certainty: "confirmed", ref: r.name, subject: base.subject, path: null, symbol: r.name,
      attribution: r.sha ? { sha: r.sha, basis: "release-ref" } : { sha: null, basis: "unavailable" },
      evidence: r.sha ? [{ sha: r.sha, path: null, line: null, text: null }] : [] };
  });
}

/** Digest of a parsed state, recorded by inspect and re-checked by the reporter. */
export const stateDigest = (state) => (state ? hash16(stable(state)) : "absent");

/** Local state file (emulates the future state issue). Missing -> null; anything wrong -> throw (fail closed). */
export function parseState(text) {
  if (text == null) return null;
  if (text.length > 64 * 1024) throw new Error("state: larger than 64 KB");
  let s;
  try { s = JSON.parse(text); } catch { throw new Error("state: not JSON"); }
  const fail = (why) => { throw new Error(`state: ${why}`); };
  exactKeys(s, ["schema", "repo", "refs", "tags_seen", "release_branches_seen", "reset"], "state", fail);
  if (s.reset !== null) {
    exactKeys(s.reset, ["run_id", "mode"], "state.reset", fail);
    if (!Number.isSafeInteger(s.reset.run_id) || s.reset.run_id < 0 || !["from-inventory", "to-head"].includes(s.reset.mode)) fail("reset");
  }
  if (s.schema !== 1) fail("schema");
  if (s.repo !== UPSTREAM) fail("foreign repo");
  for (const [ref, r] of Object.entries(s.refs)) {
    if (!REF.test(ref)) fail(`ref name ${JSON.stringify(ref)}`);
    exactKeys(r, ["processed", "first_seen"], `refs.${ref}`, fail);
    if (!SHA.test(r.processed)) fail(`refs.${ref}.processed`);
    for (const [k, v] of Object.entries(r.first_seen)) if (!FP.test(k) || !SHA.test(v)) fail(`refs.${ref}.first_seen`);
  }
  for (const k of ["tags_seen", "release_branches_seen"]) if (!Array.isArray(s[k]) || !s[k].every((t) => REF.test(t))) fail(k);
  return s;
}

/** The state a successful run would record. Failed targets keep their old cursor. */
export function nextState(prev, discovery, targets, findings, reset = null) {
  const refs = { ...(prev?.refs ?? {}) };
  for (const t of targets) {
    if (t.status === "failed" || t.status === "unchanged") continue;
    const first_seen = {};
    for (const f of findings) if (f.ref === t.ref && f.attribution.sha) first_seen[f.key] = f.attribution.sha;
    refs[t.ref] = { processed: t.head, first_seen: Object.fromEntries(Object.entries(first_seen).sort()) };
  }
  return { schema: 1, repo: UPSTREAM, refs: Object.fromEntries(Object.entries(refs).sort()),
    tags_seen: discovery.releaseTags, release_branches_seen: discovery.releaseBranches, reset };
}

// ---------- report

const SEVERITY = ["breaking", "review", "info"];
const order = (f) => [SEVERITY.indexOf(f.severity), f.scope, f.detector, f.subject, f.ref, f.fingerprint];
const cmp = (a, b) => { const x = order(a), y = order(b); for (let i = 0; i < x.length; i++) if (x[i] !== y[i]) return x[i] < y[i] ? -1 : 1; return 0; };

export function buildReport({ inventory, discovery, targets, findings, state = null }) {
  const list = [...findings].sort(cmp).map(({ key, ...f }) => f);
  return {
    schema: SCHEMA, upstream: UPSTREAM, mode: "dry-run", state_digest: stateDigest(state),
    baseline: { ref: inventory.revisions.baseline.ref, sha: inventory.revisions.baseline.sha },
    discovery: { default_branch: discovery.defaultBranch, release_line: discovery.releaseLine,
      release_branches: discovery.releaseBranches.slice(-LIMITS.list), latest_tag: discovery.releaseTags.at(-1) ?? null },
    targets: targets.map((t) => ({ ref: t.ref, role: t.role, base: t.base ?? null, head: t.head ?? null, status: t.status, error: t.error ?? null })),
    totals: Object.fromEntries(SEVERITY.map((s) => [s, list.filter((f) => f.severity === s).length])),
    findings: list,
  };
}

function exactKeys(o, keys, where, fail) {
  if (!o || typeof o !== "object" || Array.isArray(o)) fail(`${where}: not an object`);
  const got = Object.keys(o).sort().join(","), want = [...keys].sort().join(",");
  if (got !== want) fail(`${where}: keys ${got} != ${want}`);
}

const ENUMS = {
  role: ["trunk", "release-line"],
  status: ["changed", "cumulative", "unchanged", "history-rewrite", "failed"],
  detector: ["D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D9"],
  severity: SEVERITY,
  certainty: ["confirmed", "textual", "uncertain"],
};
export const SCOPE = /^((?:[a-z][a-z0-9-]*(?:\.[a-z0-9-]+)+)|multi|release:[A-Za-z0-9._-]{1,60}|contract:[\w-]{1,40}|unmapped:[A-Za-z0-9._/:+-]{1,200})$/;
const BASIS = ["first-commit-touching-file", "first-seen-at-head", "recorded-in-state", "release-ref", "unavailable"];
const KIND = /^[a-z][a-z-]{2,40}$/;

/** Strict validation: the only gate between inspect and any future reporter. */
export function validateReport(obj, { bytes, capabilityIds }) {
  const fail = (why) => { throw new Error(`report rejected: ${why}`); };
  if (bytes > LIMITS.bytes) fail(`larger than ${LIMITS.bytes} bytes`);
  const str = (v, where, re, max = LIMITS.text, nullable = false) => {
    if (v === null && nullable) return;
    if (typeof v !== "string" || !v.length || Array.from(v).length > max) fail(`${where}: string`);
    if (new RegExp(UNSAFE.source).test(v) || v.includes("<!--")) fail(`${where}: unsafe characters`);
    if (re && !re.test(v)) fail(`${where}: pattern`);
  };
  const oneOf = (v, where, list) => list.includes(v) || fail(`${where}: ${JSON.stringify(v)}`);
  exactKeys(obj, ["schema", "upstream", "mode", "state_digest", "baseline", "discovery", "targets", "totals", "findings"], "report", fail);
  if (obj.state_digest !== "absent" && !FP.test(obj.state_digest)) fail("state_digest");
  if (obj.schema !== SCHEMA || obj.upstream !== UPSTREAM || obj.mode !== "dry-run") fail("header");
  exactKeys(obj.baseline, ["ref", "sha"], "baseline", fail); str(obj.baseline.ref, "baseline.ref", REF); str(obj.baseline.sha, "baseline.sha", SHA);
  const d = obj.discovery;
  exactKeys(d, ["default_branch", "release_line", "release_branches", "latest_tag"], "discovery", fail);
  str(d.default_branch, "discovery.default_branch", REF); str(d.release_line, "discovery.release_line", REF);
  str(d.latest_tag, "discovery.latest_tag", REF, LIMITS.text, true);
  if (!Array.isArray(d.release_branches) || d.release_branches.length > LIMITS.list) fail("discovery.release_branches");
  d.release_branches.forEach((b, i) => str(b, `discovery.release_branches[${i}]`, REF));
  if (!Array.isArray(obj.targets) || obj.targets.length > 10) fail("targets");
  obj.targets.forEach((t, i) => {
    exactKeys(t, ["ref", "role", "base", "head", "status", "error"], `targets[${i}]`, fail);
    str(t.ref, `targets[${i}].ref`, REF); oneOf(t.role, `targets[${i}].role`, ENUMS.role); oneOf(t.status, `targets[${i}].status`, ENUMS.status);
    str(t.base, `targets[${i}].base`, SHA, 40, true); str(t.head, `targets[${i}].head`, SHA, 40, true); str(t.error, `targets[${i}].error`, null, LIMITS.text, true);
  });
  if (!Array.isArray(obj.findings) || obj.findings.length > LIMITS.findings) fail("findings: count");
  const fps = new Set();
  obj.findings.forEach((f, i) => {
    const w = `findings[${i}]`;
    exactKeys(f, ["fingerprint", "scope", "primary", "capabilities", "detector", "kind", "severity", "certainty", "ref", "subject", "path", "symbol", "attribution", "evidence"], w, fail);
    str(f.fingerprint, `${w}.fingerprint`, FP);
    if (fps.has(f.fingerprint)) fail(`${w}: duplicate fingerprint`);
    fps.add(f.fingerprint);
    str(f.scope, `${w}.scope`, SCOPE);
    if (/^[a-z][a-z0-9-]*\./.test(f.scope) && !capabilityIds.has(f.scope)) fail(`${w}.scope: not an inventory id`);
    if (f.primary !== null && (!capabilityIds.has(f.primary) || f.primary !== f.scope)) fail(`${w}.primary`);
    if (!Array.isArray(f.capabilities) || f.capabilities.length > LIMITS.list || !f.capabilities.every((c) => capabilityIds.has(c))) fail(`${w}.capabilities`);
    oneOf(f.detector, `${w}.detector`, ENUMS.detector); str(f.kind, `${w}.kind`, KIND);
    oneOf(f.severity, `${w}.severity`, ENUMS.severity); oneOf(f.certainty, `${w}.certainty`, ENUMS.certainty);
    str(f.ref, `${w}.ref`, REF); str(f.subject, `${w}.subject`);
    str(f.path, `${w}.path`, PATH, 300, true); str(f.symbol, `${w}.symbol`, null, LIMITS.text, true);
    exactKeys(f.attribution, ["sha", "basis"], `${w}.attribution`, fail);
    str(f.attribution.sha, `${w}.attribution.sha`, SHA, 40, true); oneOf(f.attribution.basis, `${w}.attribution.basis`, BASIS);
    if ((f.attribution.sha === null) !== (f.attribution.basis === "unavailable")) fail(`${w}.attribution: basis and sha disagree`);
    if (!Array.isArray(f.evidence) || f.evidence.length > LIMITS.evidence) fail(`${w}.evidence`);
    f.evidence.forEach((e, j) => {
      exactKeys(e, ["sha", "path", "line", "text"], `${w}.evidence[${j}]`, fail);
      str(e.sha, `${w}.evidence[${j}].sha`, SHA, 40); str(e.path, `${w}.evidence[${j}].path`, PATH, 300, true);
      if (e.line !== null && !(Number.isInteger(e.line) && e.line > 0 && e.line < 1e6)) fail(`${w}.evidence[${j}].line`);
      str(e.text, `${w}.evidence[${j}].text`, null, LIMITS.text, true);
    });
  });
  for (let i = 1; i < obj.findings.length; i++) if (cmp(obj.findings[i - 1], obj.findings[i]) > 0) fail("findings: not in canonical order");
  for (const s of SEVERITY) if (obj.totals?.[s] !== obj.findings.filter((f) => f.severity === s).length) fail(`totals.${s}`);
  exactKeys(obj.totals, SEVERITY, "totals", fail);
  return obj;
}

// ---------- human-readable dry-run summary

export const link = (e) => {
  // Built from validated parts only; upstream URLs are never copied.
  if (!SHA.test(e.sha)) return "";
  if (!e.path) return `[${e.sha.slice(0, 12)}](https://github.com/${UPSTREAM}/commit/${e.sha})`;
  if (!PATH.test(e.path)) return "";
  const anchor = e.line ? `#L${e.line}` : "";
  return `[\`${e.sha.slice(0, 8)}:${e.path}${e.line ? `:${e.line}` : ""}\`](https://github.com/${UPSTREAM}/blob/${e.sha}/${e.path}${anchor})`;
};
