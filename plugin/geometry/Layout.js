.pragma library

// Pure geometry for the Floating Islands bar. Everything here is in logical
// pixels (what Quickshell reports as screen.width), so a 1920 px panel at 1.25
// scale is 1536 wide. No QML types are touched, so tests/unit runs it in node.

var TIERS = ["full", "compact", "minimal"]

// Design values from the approved V2 prototype, at a 12 px Omarchy base font.
var DESIGN = {
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
}

function scaled(value, scale) {
  return Math.max(1, Math.round(value * scale))
}

// Every length the bar draws with, for a spacing scale (Style.spacing.scale,
// which follows the Omarchy font size) and a density.
function metrics(scale, density) {
  var s = Number(scale) > 0 ? Number(scale) : 1
  var height = DESIGN.islandHeight[density] || DESIGN.islandHeight.compact
  return {
    scale: s,
    density: DESIGN.islandHeight[density] ? density : "compact",
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
  }
}

// Only horizontal edges are supported; a vertical position set for the stock
// bar falls back to the top.
function normalizeEdge(position) {
  return position === "bottom" ? "bottom" : "top"
}

// The space windows keep clear of: the gap plus the islands. Hyprland adds
// its own gaps_out beyond this.
function exclusiveZone(m) {
  return m.edgeGap + m.islandHeight
}

// Where the islands' outer edge sits inside a surface that spans the screen.
// The bar size reported to Omarchy (barSizeFor, screenBarSizes). Its panels
// and toasts place themselves at that size plus Style.gapsOut, half of
// Hyprland's gaps_out, which Super+Shift+Backspace turns to 0. Reporting the
// island edge plus the difference keeps every panel panelGap from the islands.
function panelBarSize(m, platformGap) {
  var gap = isFinite(platformGap) && platformGap > 0 ? platformGap : 0
  return Math.max(0, exclusiveZone(m) + m.panelGap - gap)
}

function islandY(edge, surfaceHeight, m) {
  return edge === "bottom" ? surfaceHeight - m.edgeGap - m.islandHeight : m.edgeGap
}

// Room on each side of the centred clock.
function sideBudget(screenWidth, centerWidth, m) {
  return screenWidth / 2 - centerWidth / 2 - m.centerClearance - m.sideMargin
}

// demand = { center, leftFixed, titleMin, rightFixed } for one tier.
function fit(screenWidth, demand, m) {
  var budget = sideBudget(screenWidth, demand.center, m)
  var leftNeed = demand.leftFixed + (demand.titleMin || 0)
  var slack = Math.min(budget - leftNeed, budget - demand.rightFixed)
  return { fits: slack >= 0, budget: budget, slack: slack }
}

// The richest tier whose fixed islands fit beside the clock. Growing back to
// a richer tier needs `hysteresis` px of slack, so a width that hovers at a
// boundary (a tray icon appearing) does not flip the layout back and forth.
function chooseTier(screenWidth, demands, m, previous) {
  var previousIndex = TIERS.indexOf(previous)
  for (var i = 0; i < TIERS.length; i++) {
    var demand = demands ? demands[TIERS[i]] : null
    if (!demand) continue
    var result = fit(screenWidth, demand, m)
    if (!result.fits) continue
    if (previousIndex > i && result.slack < m.hysteresis) continue
    return TIERS[i]
  }
  return "minimal"
}

// The window title is the only island that gives way: it takes what is left
// of its side, up to the tier's cap.
function titleWidth(tier, screenWidth, demand, m) {
  if (tier === "minimal" || !demand) return 0
  var budget = sideBudget(screenWidth, demand.center, m)
  var cap = m.titleMax[tier] || 0
  return Math.max(0, Math.floor(Math.min(cap, budget - demand.leftFixed)))
}

// Tallest a future panel may grow on this screen.
function panelMaxHeight(screenHeight, m) {
  return Math.max(0, screenHeight - exclusiveZone(m) - m.panelGap - m.panelMargin)
}

// The pointer target of an island: out to the screen edge it hangs from (so a
// flick to the edge still lands), a few px past its inner side, and a few px
// sideways. rect is the island in surface coordinates.
function hitRect(rect, edge, surfaceHeight, m) {
  var x = rect.x - m.hitSide
  var width = rect.width + 2 * m.hitSide
  if (rect.width <= 0 || rect.height <= 0) return { x: 0, y: 0, width: 0, height: 0 }
  if (edge === "bottom") {
    var top = rect.y - m.hitInner
    return { x: x, y: top, width: width, height: surfaceHeight - top }
  }
  return { x: x, y: 0, width: width, height: rect.y + rect.height + m.hitInner }
}

// How far a button's own pointer area reaches past its top and bottom, so its
// hit area meets the island's hitRect.
function buttonReach(edge, m) {
  var towardEdge = m.buttonInset + m.edgeGap
  return edge === "bottom"
    ? { top: m.hitInner, bottom: towardEdge }
    : { top: towardEdge, bottom: m.hitInner }
}
