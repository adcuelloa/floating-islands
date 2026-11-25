// Synthetic fixtures shared by the upstream watcher tests. Not a test file.
import { analyze, buildReport, contractRows, parseContract, parseLsRemote, validateReport } from "../../.github/upstream-watch/lib.mjs";
import { aggregate, renderSummary as renderItems } from "../../.github/upstream-watch/aggregate.mjs";

export const sha = (c) => c.repeat(40);
export const [A, B, C, D, X1, X2, X3] = ["a", "b", "c", "d", "1", "2", "3"].map(sha);
export const ch = (n) => String.fromCharCode(n);

export const cap = (id, { ids = [], paths = [], api = [], areas = [], blockers = [] } = {}) => ({
  id, title: id, kind: "api", origin: "baseline", upstream: { ids, paths, api }, depends_on: [],
  integration: { current: "native", intended: "native" }, placement: { current: null, proposed: null, approval: "not-applicable", rfc: null },
  compat: { baseline: "ok", trunk: "ok", evidence: [] }, contract_areas: areas, fi_files: [], blockers, issue: null, reviewed: A,
});
export const inventory = {
  schema: 1, product_rules: ["One unified system-control entry point."],
  revisions: { baseline: { ref: "v4.5.0", sha: A }, release_line: { ref: "v4-5-1", sha: B }, trunk: { ref: "quattro", sha: C } },
  capabilities: [
    cap("host.widget-facade", { paths: ["shell/Ui/PluginBarApi.qml", "shell/Ui/qmldir"], api: ["PluginBarApi._* callbacks"], areas: ["widgets"] }),
    cap("ui.screen-move-remap", { paths: ["shell/Ui/ScreenMoveRemap.qml", "shell/Ui/qmldir"], areas: ["commons"] }),
    cap("shortcuts.numbered-panels", { paths: ["default/hypr/bindings/utilities.lua"], areas: ["routes"] }),
    cap("hypr.monitor-workspaces", { paths: ["default/hypr/monitor-workspaces.lua"], areas: ["hyprland"] }),
    cap("omarchy.clock", { ids: ["omarchy.clock"], paths: ["shell/plugins/bar/widgets/clock.manifest.json"] }),
    cap("omarchy.old", { ids: ["omarchy.old"], paths: ["shell/plugins/old/manifest.json"] }),
    cap("omarchy.notifications", { ids: ["omarchy.notifications"], paths: ["shell/plugins/notifications/manifest.json"],
      blockers: [{ id: "no-history-api", summary: "no history", upstream_ref: null, watch: ["notificationHistory"] }] }),
  ],
};
export const capabilityIds = new Set(inventory.capabilities.map((c) => c.id));
export const rows = contractRows([
  "widgets\t$OMARCHY/shell/Ui/PluginBarApi.qml\tF\tproperty var _hide: null\tfacade callback _hide",
  "widgets\t$OMARCHY/shell/Ui/PluginBarApi.qml\tF?\tproperty var _optIn: null\topt-in callback",
  "hyprland\t$OMARCHY/default/hypr/monitor-workspaces.lua\tE\tworkspace[s]?\tper-monitor workspace blocks",
  "commons\t$OMARCHY/shell/Ui/qmldir\tE\t^ScreenMoveRemap [0-9.]+ ScreenMoveRemap.qml\toutput-move guard",
  "theme\t$QS/quickshell-core.qmltypes\tF\tname: \"x\"\tpinned runtime row is ignored",
].join("\n"));
export const contractPorcelain = (fails = [], warns = [], targetRows = rows) => {
  let pass = 0, fail = 0, warn = 0;
  const lines = [];
  for (const [k, r] of targetRows) {
    const status = fails.includes(k) ? (fail++, "FAIL") : warns.includes(k) ? (warn++, "WARN") : (pass++, "ok");
    lines.push(`row\t${r.lineno}\t${status}\t${r.conditional ? 1 : 0}\t${r.area}\t${r.reason}`);
  }
  lines.push(`contract: ${pass} passed, ${fail} failed, ${warn} conditional warnings`);
  return lines.join("\n");
};
export const contractOut = (fails = [], warns = [], targetRows = rows) =>
  parseContract(contractPorcelain(fails, warns, targetRows), targetRows);

export const api = (...lines) => ["Item {", ...lines.map((l) => `    ${l}`), "}"].join("\n");
export const baseFiles = () => new Map([
  ["shell/Ui/PluginBarApi.qml", api("property var _hide: null", "property var _optIn: null", "property var _gone: null", "function show(a, b) {}")],
  ["shell/Ui/qmldir", "module qs.Ui\nPluginBarApi 1.0 PluginBarApi.qml\nScreenMoveRemap 1.0 ScreenMoveRemap.qml"],
  ["shell/Ui/ScreenMoveRemap.qml", "Item { function remap(a) {} }"],
  ["default/hypr/monitor-workspaces.lua", "-- workspaces\n"],
  ["default/hypr/bindings/utilities.lua", 'o.bind("SUPER + CTRL + 1", "Panel 1", "x")\no.bind("SUPER + K", "Keys", "y")'],
  ["shell/plugins/bar/widgets/clock.manifest.json", JSON.stringify({ id: "omarchy.clock", kind: "widget", entryPoints: { bar: "Clock.qml" } })],
  ["shell/plugins/old/manifest.json", JSON.stringify({ id: "omarchy.old", kind: "service" })],
  ["shell/plugins/notifications/manifest.json", JSON.stringify({ id: "omarchy.notifications", kind: "panel" })],
  ["shell/plugins/notifications/Panel.qml", "Item {}"],
  ["config/omarchy/shell.json", JSON.stringify({ bar: { position: "top", layout: { right: ["a", "b"] } } })],
  ["bin/omarchy-bar", "#!/bin/bash\n# omarchy:summary=Configure the bar\n"],
]);
export const target = (over = {}) => ({ ref: "quattro", role: "trunk", base: A, head: C, status: "cumulative", rangeBase: A, ...over });
export const run = (head, { base = baseFiles(), t = target(), contract = { base: contractOut(), head: contractOut() }, intro = () => X1, firstSeen } = {}) =>
  analyze({ inventory, target: t, rows, files: { base, head }, contract, introducing: intro, firstSeen });
export const edit = (fn) => { const m = baseFiles(); fn(m); return m; };
export const only = (fs, detector) => fs.filter((f) => f.detector === detector);
export const report = (findings, targets = [target()]) => {
  const discovery = parseLsRemote(lsRemote());
  return buildReport({ inventory, discovery, targets, findings });
};
export const lsRemote = (extra = "") => [
  "ref: refs/heads/quattro\tHEAD", `${C}\tHEAD`, `${C}\trefs/heads/quattro`, `${B}\trefs/heads/v4-5-1`, `${A}\trefs/heads/v4-5-0`,
  `${D}\trefs/tags/v4.5.0`, `${A}\trefs/tags/v4.5.0^{}`, `${D}\trefs/heads/master`, extra,
].join("\n");
export const renderSummary = (r) => renderItems(r, aggregate(r, { inventory, rows }));
export const validate = (r, bytes) => validateReport(JSON.parse(JSON.stringify(r)), { bytes: bytes ?? JSON.stringify(r).length, capabilityIds });
