import { test } from "node:test";
import assert from "node:assert/strict";
import * as Layout from "../../plugin/geometry/Layout.mjs";

const m = Layout.metrics(1, "compact");

// Widths estimated from the V2 prototype at a 12 px base font (see
// docs/COMPATIBILITY.md, "Responsive tiers"). At runtime they are measured.
const LEFT = 280;          // launcher + workspaces island, plus the group gap
const RIGHT_EXPANDED = 596; // planned media (expanded) + status + bell islands
const demands = {
  full: { center: 175, leftFixed: LEFT, titleMin: 120, rightFixed: RIGHT_EXPANDED },
  compact: { center: 135, leftFixed: LEFT, titleMin: 120, rightFixed: 420 },
  minimal: { center: 80, leftFixed: 272, titleMin: 0, rightFixed: 222 },
};

// [label, logical width, expected tier, expected title cap]
/** @type {readonly [string, number, Layout.Tier, number][]} */
const outputs = [
  ["1920x1080 @1.0", 1920, "full", 480],
  ["1920x1080 @1.25", 1536, "full", 372],
  ["1920x1080 @1.5", 1280, "compact", 240],
  ["1366x768 @1.0", 1366, "compact", 240],
  ["1366x768 @1.25", 1093, "compact", 171],
  ["2560x1440 @1.0", 2560, "full", 480],
  ["2560x1440 @1.25", 2048, "full", 480],
  ["2560x1440 @1.5", 1707, "full", 458],
  ["2560x1440 @2.0", 1280, "compact", 240],
  ["1024 logical", 1024, "minimal", 0],
];

for (const [label, width, tier, title] of outputs) {
  test(`tier for ${label} (${width} logical px) is ${tier}`, () => {
    const chosen = Layout.chooseTier(width, demands, m, "full");
    assert.equal(chosen, tier);
    assert.equal(Layout.titleWidth(chosen, width, demands[chosen], m), title);
  });
}

test("the 1700 px prototype threshold is not what decides: 1536 logical is full", () => {
  assert.equal(Layout.chooseTier(1536, demands, m, "compact"), "full");
});

test("growing back to a richer tier needs hysteresis slack", () => {
  // compact -> full needs slack >= 24 px; at 1536 slack is 56.5, at 1490 it is 33.5
  assert.equal(Layout.chooseTier(1490, demands, m, "compact"), "full");
  // full fits by 7.5 px at 1444 but compact was showing: stays compact.
  assert.equal(Layout.chooseTier(1444, demands, m, "full"), "full");
  assert.equal(Layout.chooseTier(1444, demands, m, "compact"), "compact");
});

test("exclusive zone is gap plus island height; windows start at 60 with gaps_out 10", () => {
  assert.equal(Layout.exclusiveZone(m), 50);
  assert.equal(Layout.exclusiveZone(m) + 10, 60);
  assert.equal(Layout.exclusiveZone(Layout.metrics(1, "comfortable")), 56);
});

test("metrics follow the Omarchy spacing scale", () => {
  const big = Layout.metrics(1.25, "compact");
  assert.equal(big.islandHeight, 50);
  assert.equal(big.edgeGap, 13);
  assert.equal(Layout.metrics(0, "nonsense").islandHeight, 40);
});

test("panel max height uses the logical screen height", () => {
  assert.equal(Layout.panelMaxHeight(864, m), 794);
  assert.equal(Layout.panelMaxHeight(768, m), 698);
});

test("only horizontal edges; vertical positions fall back to top", () => {
  assert.equal(Layout.normalizeEdge("bottom"), "bottom");
  for (const p of ["top", "left", "right", undefined, "x"]) assert.equal(Layout.normalizeEdge(p), "top");
});

test("islands hang from the anchored edge", () => {
  assert.equal(Layout.islandY("top", 864, m), 10);
  assert.equal(Layout.islandY("bottom", 864, m), 864 - 10 - 40);
});

test("hit rects reach the screen edge and a few px past the island", () => {
  const island = { x: 12, y: 10, width: 200, height: 40 };
  assert.deepEqual(JSON.parse(JSON.stringify(Layout.hitRect(island, "top", 864, m))), { x: 9, y: 0, width: 206, height: 55 });
  const low = { x: 12, y: 814, width: 200, height: 40 };
  assert.deepEqual(JSON.parse(JSON.stringify(Layout.hitRect(low, "bottom", 864, m))), { x: 9, y: 809, width: 206, height: 55 });
  assert.equal(Layout.hitRect({ x: 5, y: 5, width: 0, height: 40 }, "top", 864, m).width, 0);
});

test("button reach meets the hit rect", () => {
  assert.deepEqual(JSON.parse(JSON.stringify(Layout.buttonReach("top", m))), { top: 14, bottom: 5 });
  assert.deepEqual(JSON.parse(JSON.stringify(Layout.buttonReach("bottom", m))), { top: 5, bottom: 14 });
});

// Omarchy places hosted panels at barSizeFor() + Style.gapsOut (half of
// Hyprland's gaps_out), so the gap under the islands followed the user's
// gaps: 5 px by default, 0 with Super+Shift+Backspace (trial 4). The size the
// bar reports makes up the difference, so every panel sits panelGap below.
test("panels sit panelGap below the islands whatever Hyprland's gaps are", () => {
  const islandBottom = Layout.exclusiveZone(m);
  for (const gapsOut of [0, 3, 5, 8, 10]) {
    assert.equal(Layout.panelBarSize(m, gapsOut) + gapsOut, islandBottom + m.panelGap, `gapsOut ${gapsOut}`);
  }
  assert.equal(Layout.panelBarSize(m, 400), 0, "never negative");
  assert.equal(Layout.panelBarSize(m, NaN), islandBottom + m.panelGap - 0, "an unknown gap counts as none");
});

test("dynamic clock width keeps tier stable via max demand while title reclaims idle space", () => {
  // Reserve expanded clock width (175) for tier selection, while idle clock is 145.
  const idleClock = 145;
  const expandedClock = 175;
  const screenWidth = 1536;
  const tier = Layout.chooseTier(screenWidth, demands, m, "full");
  assert.equal(tier, "full");
  const idleTitle = Layout.titleWidth(tier, screenWidth, { center: idleClock, leftFixed: demands.full.leftFixed }, m);
  const expandedTitle = Layout.titleWidth(tier, screenWidth, { center: expandedClock, leftFixed: demands.full.leftFixed }, m);
  assert.ok(idleTitle > expandedTitle, `idle title (${idleTitle}) should exceed expanded title (${expandedTitle})`);
  assert.ok(expandedTitle >= m.titleMin, "expanded title still respects titleMin");
  // Verify no overlap with centered clock in both idle and expanded states.
  const idleClockLeft = Math.round((screenWidth - idleClock) / 2);
  const expandedClockLeft = Math.round((screenWidth - expandedClock) / 2);
  const leftEdge = m.sideMargin + demands.full.leftFixed;
  assert.ok(leftEdge + idleTitle + m.centerClearance <= idleClockLeft, "idle clearance preserved");
  assert.ok(leftEdge + expandedTitle + m.centerClearance <= expandedClockLeft, "expanded clearance preserved");
});

test("maxCenterWidth bounds centered clock and distinguishes clock overlap from fixed side-group overflow", () => {
  const m = Layout.metrics(1, "compact");
  // At 1024 px with left=240, right=260, sideMargin=12, centerClearance=16:
  // available = 1024 - 2 * (12 + 260 + 16) = 448 px.
  assert.equal(Layout.maxCenterWidth(1024, 240, 260, m), 448);
  // Symmetric centered clock of width 448 clears both sides by >= centerClearance.
  const budget = Layout.sideBudget(1024, 448, m);
  assert.ok(budget >= 260, `sideBudget ${budget} >= 260`);

  // When fixed side groups alone exceed the screen width, maxCenterWidth is 0.
  assert.equal(Layout.maxCenterWidth(560, 280, 280, m), 0);
  assert.equal(Layout.maxCenterWidth(0, 200, 200, m), 0);
});

test("actual visible right-group width avoids premature clock constraint when media is hidden or collapsed", () => {
  const m = Layout.metrics(1, "compact");
  const screenWidth = 1536;
  const leftWidth = 272;
  const hostedCollapsed = 232;
  const hostedExpanded = 290;
  const mediaCollapsed = 234;
  const mediaExpanded = 366;

  // Reserving expanded media (606 px) leaves only 268 px when idle/collapsed,
  // and drops to 152 px during tray expansion before tier switches.
  const reservedRightExpanded = hostedExpanded + m.groupGap + mediaExpanded;
  assert.equal(Layout.maxCenterWidth(screenWidth, leftWidth, reservedRightExpanded, m), 152);

  // Using actual visible right-group width keeps ample centered room when
  // media is hidden (936 px, bounded by leftWidth) or collapsed during tray
  // expansion (416 px).
  const actualWhenHidden = hostedCollapsed;
  assert.equal(Layout.maxCenterWidth(screenWidth, leftWidth, actualWhenHidden, m), 936);
  const actualWhenCollapsedMediaAndTrayExpanded = hostedExpanded + m.groupGap + mediaCollapsed;
  assert.equal(Layout.maxCenterWidth(screenWidth, leftWidth, actualWhenCollapsedMediaAndTrayExpanded, m), 416);
});

test("tier recovery breaks hysteresis deadlock when returning to collapsed tray baseline without losing hysteresis", () => {
  const m = Layout.metrics(1, "compact");
  const W = 1536;
  const leftFixed = 280;
  const mediaFull = 366;
  const mediaCompact = 190;
  const makeDemands = (/** @type {number} */ hosted) => ({
    full: { center: 234, leftFixed, titleMin: m.titleMin, rightFixed: hosted + m.groupGap + mediaFull },
    compact: { center: 185, leftFixed, titleMin: m.titleMin, rightFixed: hosted + m.groupGap + mediaCompact },
    minimal: { center: 110, leftFixed: 272, titleMin: 0, rightFixed: hosted },
  });

  // Collapsed tray (232 px) starts in full with +17 px slack (< 24 px hysteresis).
  const collapsed = makeDemands(232);
  const baseSlack = Layout.fit(W, collapsed.full, m).slack;
  assert.equal(baseSlack, 17);
  assert.equal(Layout.chooseTier(W, collapsed, m, "full"), "full");

  // Tray expands to 290 px -> drops to compact.
  const expanded = makeDemands(290);
  assert.equal(Layout.chooseTier(W, expanded, m, "full", { full: baseSlack }), "compact");

  // Mid-collapse (245 px, slack = +4 < 17): hysteresis still holds compact.
  const midCollapse = makeDemands(245);
  assert.equal(Layout.fit(W, midCollapse.full, m).slack, 4);
  assert.equal(Layout.chooseTier(W, midCollapse, m, "compact", { full: baseSlack }), "compact");

  // Returning to collapsed baseline (232 px, slack = +17 >= 17): recovers to full.
  assert.equal(Layout.chooseTier(W, collapsed, m, "compact", { full: baseSlack }), "full");

  // Without prior observed slack, full 24 px hysteresis remains intact (1444 px stays compact).
  assert.equal(Layout.chooseTier(1444, demands, m, "compact"), "compact");
  assert.equal(Layout.recoveryHysteresis(24, 56), 24);
  assert.equal(Layout.recoveryHysteresis(24, 17), 17);
  assert.equal(Layout.recoveryHysteresis(24, undefined), 24);
});
