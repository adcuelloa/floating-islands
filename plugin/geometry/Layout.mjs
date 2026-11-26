// Pure geometry for the Floating Islands bar. Everything here is in logical
// pixels (what Quickshell reports as screen.width), so a 1920 px panel at 1.25
// scale is 1536 wide. Native ECMAScript module executed directly by Qt/QML and
// Node.js with no build step.

/** @typedef {"full" | "compact" | "minimal"} Tier */
/** @typedef {"compact" | "comfortable"} Density */
/** @typedef {"top" | "bottom"} Edge */

/**
 * @typedef {{
 *   readonly full: number,
 *   readonly compact: number,
 *   readonly minimal: number
 * }} TitleMaxByTier
 */

/**
 * @typedef {{
 *   readonly scale: number,
 *   readonly density: Density,
 *   readonly islandHeight: number,
 *   readonly edgeGap: number,
 *   readonly sideMargin: number,
 *   readonly groupGap: number,
 *   readonly centerClearance: number,
 *   readonly islandRadius: number,
 *   readonly islandPaddingX: number,
 *   readonly itemGap: number,
 *   readonly buttonInset: number,
 *   readonly buttonMinWidth: number,
 *   readonly statusSlot: number,
 *   readonly workspaceSlot: number,
 *   readonly buttonPaddingX: number,
 *   readonly buttonRadius: number,
 *   readonly contentGap: number,
 *   readonly dividerHeight: number,
 *   readonly dividerMargin: number,
 *   readonly hitSide: number,
 *   readonly hitInner: number,
 *   readonly titleMin: number,
 *   readonly titleMax: TitleMaxByTier,
 *   readonly panelGap: number,
 *   readonly panelMargin: number,
 *   readonly hysteresis: number
 * }} Metrics
 */

/**
 * @typedef {{
 *   readonly center: number,
 *   readonly leftFixed: number,
 *   readonly titleMin?: number,
 *   readonly rightFixed: number
 * }} TierDemand
 */

/** @typedef {Partial<Record<Tier, TierDemand | null | undefined>>} TierDemands */

/**
 * @typedef {{
 *   readonly center: number,
 *   readonly leftFixed: number
 * }} TitleDemand
 */

/**
 * @typedef {{
 *   readonly fits: boolean,
 *   readonly budget: number,
 *   readonly slack: number
 * }} FitResult
 */

/**
 * @typedef {{
 *   readonly x: number,
 *   readonly y: number,
 *   readonly width: number,
 *   readonly height: number
 * }} Rect
 */

/**
 * @typedef {{
 *   readonly top: number,
 *   readonly bottom: number
 * }} ButtonReach
 */

/** @type {readonly Tier[]} */
export const TIERS = ["full", "compact", "minimal"];

// Design values from the approved V2 prototype, at a 12 px Omarchy base font.
export const DESIGN = {
  islandHeight: { compact: 40, comfortable: 46 },
  edgeGap: 10,          // screen edge to island
  sideMargin: 12,       // screen side to the outer groups
  groupGap: 8,          // between islands of one group
  centerClearance: 16,  // minimum gap between the clock and a side group
  islandRadius: 12,
  islandPaddingX: 4,
  itemGap: 2,
  buttonInset: 4,       // island edge to button edge
  buttonMinWidth: 40,
  statusSlot: 30,       // a hosted status widget's minimum slot (hover and press fill)
  workspaceSlot: 28,    // a workspace's pointer slot: the 24 px pill plus 2 px a side
  buttonPaddingX: 10,
  buttonRadius: 8,
  contentGap: 8,        // between a button's icon and label
  dividerHeight: 18,
  dividerMargin: 4,
  hitSide: 3,           // a button's pointer target reaches this far sideways
  hitInner: 5,          // and this far past the island's inner edge
  titleMin: 120,
  titleMax: { full: 480, compact: 240, minimal: 0 },
  panelGap: 8,
  panelMargin: 12,
  hysteresis: 24
};

/**
 * @param {number} value
 * @param {number} scale
 * @returns {number}
 */
function scaled(value, scale) {
  return Math.max(1, Math.round(value * scale));
}

/**
 * Every length the bar draws with, for a spacing scale (Style.spacing.scale,
 * which follows the Omarchy font size) and a density.
 *
 * @param {number} scale
 * @param {string} [density]
 * @returns {Metrics}
 */
export function metrics(scale, density) {
  const s = Number(scale) > 0 ? Number(scale) : 1;
  /** @type {Density} */
  const resolvedDensity = density === "comfortable" ? "comfortable" : "compact";
  const height = DESIGN.islandHeight[resolvedDensity];
  return {
    scale: s,
    density: resolvedDensity,
    islandHeight: scaled(height, s),
    edgeGap: scaled(DESIGN.edgeGap, s),
    sideMargin: scaled(DESIGN.sideMargin, s),
    groupGap: scaled(DESIGN.groupGap, s),
    centerClearance: scaled(DESIGN.centerClearance, s),
    islandRadius: scaled(DESIGN.islandRadius, s),
    islandPaddingX: scaled(DESIGN.islandPaddingX, s),
    itemGap: scaled(DESIGN.itemGap, s),
    buttonInset: scaled(DESIGN.buttonInset, s),
    buttonMinWidth: scaled(DESIGN.buttonMinWidth, s),
    statusSlot: scaled(DESIGN.statusSlot, s),
    workspaceSlot: scaled(DESIGN.workspaceSlot, s),
    buttonPaddingX: scaled(DESIGN.buttonPaddingX, s),
    buttonRadius: scaled(DESIGN.buttonRadius, s),
    contentGap: scaled(DESIGN.contentGap, s),
    dividerHeight: scaled(DESIGN.dividerHeight, s),
    dividerMargin: scaled(DESIGN.dividerMargin, s),
    hitSide: scaled(DESIGN.hitSide, s),
    hitInner: scaled(DESIGN.hitInner, s),
    titleMin: scaled(DESIGN.titleMin, s),
    titleMax: {
      full: scaled(DESIGN.titleMax.full, s),
      compact: scaled(DESIGN.titleMax.compact, s),
      minimal: 0
    },
    panelGap: scaled(DESIGN.panelGap, s),
    panelMargin: scaled(DESIGN.panelMargin, s),
    hysteresis: scaled(DESIGN.hysteresis, s)
  };
}

/**
 * Only horizontal edges are supported; a vertical position set for the stock
 * bar falls back to the top.
 *
 * @param {string | null | undefined} position
 * @returns {Edge}
 */
export function normalizeEdge(position) {
  return position === "bottom" ? "bottom" : "top";
}

/**
 * The space windows keep clear of: the gap plus the islands. Hyprland adds
 * its own gaps_out beyond this.
 *
 * @param {Metrics} m
 * @returns {number}
 */
export function exclusiveZone(m) {
  return m.edgeGap + m.islandHeight;
}

/**
 * Where the islands' outer edge sits inside a surface that spans the screen.
 * The bar size reported to Omarchy (barSizeFor, screenBarSizes). Its panels
 * and toasts place themselves at that size plus Style.gapsOut, half of
 * Hyprland's gaps_out, which Super+Shift+Backspace turns to 0. Reporting the
 * island edge plus the difference keeps every panel panelGap from the islands.
 *
 * @param {Metrics} m
 * @param {number} platformGap
 * @returns {number}
 */
export function panelBarSize(m, platformGap) {
  const gap = isFinite(platformGap) && platformGap > 0 ? platformGap : 0;
  return Math.max(0, exclusiveZone(m) + m.panelGap - gap);
}

/**
 * @param {Edge} edge
 * @param {number} surfaceHeight
 * @param {Metrics} m
 * @returns {number}
 */
export function islandY(edge, surfaceHeight, m) {
  return edge === "bottom" ? surfaceHeight - m.edgeGap - m.islandHeight : m.edgeGap;
}

/**
 * Room on each side of the centred clock.
 *
 * @param {number} screenWidth
 * @param {number} centerWidth
 * @param {Metrics} m
 * @returns {number}
 */
export function sideBudget(screenWidth, centerWidth, m) {
  return screenWidth / 2 - centerWidth / 2 - m.centerClearance - m.sideMargin;
}

/**
 * Maximum width the centred clock may occupy without overlapping either fixed
 * side group (respecting sideMargin and centerClearance). Returns 0 when the
 * fixed side groups alone already leave no room for a centred slot.
 *
 * @param {number} screenWidth
 * @param {number} leftFixed
 * @param {number} rightFixed
 * @param {Metrics} m
 * @returns {number}
 */
export function maxCenterWidth(screenWidth, leftFixed, rightFixed, m) {
  if (!isFinite(screenWidth) || screenWidth <= 0) return 0;
  const left = isFinite(leftFixed) && leftFixed > 0 ? leftFixed : 0;
  const right = isFinite(rightFixed) && rightFixed > 0 ? rightFixed : 0;
  const widestSide = Math.max(left, right);
  const available = Math.floor(screenWidth - 2 * (m.sideMargin + widestSide + m.centerClearance));
  return Math.max(0, available);
}

/**
 * @param {number} screenWidth
 * @param {TierDemand} demand
 * @param {Metrics} m
 * @returns {FitResult}
 */
export function fit(screenWidth, demand, m) {
  const budget = sideBudget(screenWidth, demand.center, m);
  const leftNeed = demand.leftFixed + (demand.titleMin || 0);
  const slack = Math.min(budget - leftNeed, budget - demand.rightFixed);
  return { fits: slack >= 0, budget: budget, slack: slack };
}

/**
 * Effective upward-recovery hysteresis for a tier: normally `hysteresis`,
 * capped at `observedSlack` when the bar was already stably in that tier with
 * positive slack below `hysteresis`, so returning to that steady state recovers
 * instead of deadlocking.
 *
 * @param {number} hysteresis
 * @param {number | null | undefined} observedSlack
 * @returns {number}
 */
export function recoveryHysteresis(hysteresis, observedSlack) {
  if (typeof observedSlack === "number" && isFinite(observedSlack) && observedSlack >= 0) {
    return Math.min(hysteresis, observedSlack);
  }
  return hysteresis;
}

/**
 * The richest tier whose fixed islands fit beside the clock. Growing back to
 * a richer tier needs `hysteresis` px of slack (capped at any previously
 * observed steady-state slack for that tier), so a width that hovers at a
 * boundary (a tray icon appearing) does not flip the layout back and forth
 * while returning to a prior collapsed state still recovers cleanly.
 *
 * @param {number} screenWidth
 * @param {TierDemands | null | undefined} demands
 * @param {Metrics} m
 * @param {Tier | null | undefined} [previous]
 * @param {Partial<Record<Tier, number>> | null | undefined} [observedSlack]
 * @returns {Tier}
 */
export function chooseTier(screenWidth, demands, m, previous, observedSlack) {
  const previousIndex = previous ? TIERS.indexOf(previous) : -1;
  for (let i = 0; i < TIERS.length; i++) {
    const tier = TIERS[i];
    if (!tier) continue;
    const demand = demands ? demands[tier] : null;
    if (!demand) continue;
    const result = fit(screenWidth, demand, m);
    if (!result.fits) continue;
    const threshold = recoveryHysteresis(m.hysteresis, observedSlack ? observedSlack[tier] : undefined);
    if (previousIndex > i && result.slack < threshold) continue;
    return tier;
  }
  return "minimal";
}

/**
 * The window title is the only island that gives way: it takes what is left
 * of its side, up to the tier's cap.
 *
 * @param {Tier} tier
 * @param {number} screenWidth
 * @param {TitleDemand | null | undefined} demand
 * @param {Metrics} m
 * @returns {number}
 */
export function titleWidth(tier, screenWidth, demand, m) {
  if (tier === "minimal" || !demand) return 0;
  const budget = sideBudget(screenWidth, demand.center, m);
  const cap = m.titleMax[tier] || 0;
  return Math.max(0, Math.floor(Math.min(cap, budget - demand.leftFixed)));
}

/**
 * Tallest a future panel may grow on this screen.
 *
 * @param {number} screenHeight
 * @param {Metrics} m
 * @returns {number}
 */
export function panelMaxHeight(screenHeight, m) {
  return Math.max(0, screenHeight - exclusiveZone(m) - m.panelGap - m.panelMargin);
}

/**
 * The pointer target of an island: out to the screen edge it hangs from (so a
 * flick to the edge still lands), a few px past its inner side, and a few px
 * sideways. rect is the island in surface coordinates.
 *
 * @param {Rect} rect
 * @param {Edge} edge
 * @param {number} surfaceHeight
 * @param {Metrics} m
 * @returns {Rect}
 */
export function hitRect(rect, edge, surfaceHeight, m) {
  const x = rect.x - m.hitSide;
  const width = rect.width + 2 * m.hitSide;
  if (rect.width <= 0 || rect.height <= 0) return { x: 0, y: 0, width: 0, height: 0 };
  if (edge === "bottom") {
    const top = rect.y - m.hitInner;
    return { x: x, y: top, width: width, height: surfaceHeight - top };
  }
  return { x: x, y: 0, width: width, height: rect.y + rect.height + m.hitInner };
}

/**
 * How far a button's own pointer area reaches past its top and bottom, so its
 * hit area meets the island's hitRect.
 *
 * @param {Edge} edge
 * @param {Metrics} m
 * @returns {ButtonReach}
 */
export function buttonReach(edge, m) {
  const towardEdge = m.buttonInset + m.edgeGap;
  return edge === "bottom"
    ? { top: m.hitInner, bottom: towardEdge }
    : { top: towardEdge, bottom: m.hitInner };
}
