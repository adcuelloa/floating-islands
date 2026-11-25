.pragma library

// Colour arithmetic for the roles Omarchy themes do not name (raised, faint,
// the text drawn on the accent). Inputs are anything with r, g, b, a in 0..1,
// which QML colors are.

function clamp01(value) {
  return Math.max(0, Math.min(1, Number(value) || 0))
}

function rgba(r, g, b, a) {
  return Qt.rgba(clamp01(r), clamp01(g), clamp01(b), clamp01(a))
}

// `from` moved `t` of the way toward `to`, keeping from's alpha.
function mix(from, to, t) {
  var k = clamp01(t)
  return rgba(from.r + (to.r - from.r) * k, from.g + (to.g - from.g) * k, from.b + (to.b - from.b) * k,
    from.a === undefined ? 1 : from.a)
}

function withAlpha(color, alpha) {
  return rgba(color.r, color.g, color.b, alpha)
}

function channel(value) {
  var c = clamp01(value)
  return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
}

// WCAG relative luminance and contrast ratio.
function luminance(color) {
  return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b)
}

function contrast(left, right) {
  var a = luminance(left)
  var b = luminance(right)
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)
}

// The prototype draws dark text on its accent. A theme's background usually
// gives that; when it is too close to the accent, its foreground is used.
function readableOn(accent, background, foreground) {
  return contrast(accent, background) >= contrast(accent, foreground) ? background : foreground
}

// `color` moved toward `toward` (the theme's foreground) only as far as it
// takes to reach `ratio` (default 4.5:1, WCAG ordinary text) against every
// colour in `grounds`. A colour that already reaches it is returned as is;
// if even `toward` does not, `toward` is the best there is.
function readable(color, toward, grounds, ratio) {
  var want = ratio || 4.5
  function ok(c, target) {
    for (var i = 0; i < grounds.length; i++) if (contrast(c, grounds[i]) < target) return false
    return true
  }
  if (ok(color, want)) return color
  if (!ok(toward, want)) return toward
  // A mixed colour aims a little higher: QML keeps 8 bits per channel, and
  // rounding can take a value found exactly at `want` just under it.
  var low = 0, high = 1
  for (var step = 0; step < 16; step++) {
    var mid = (low + high) / 2
    if (ok(mix(color, toward, mid), want + 0.05)) high = mid
    else low = mid
  }
  return mix(color, toward, high)
}

// Text on a filled control (`fill`, opaque): the theme's background or
// foreground, whichever reads better (readableOn), when that reaches `ratio`
// (default 4.5:1). Otherwise the theme colour on the darker or lighter side
// (whichever the fill contrasts with more), moved toward black or white only
// as far as it takes. Any opaque fill reaches at least 4.58:1 against black
// or white, so this always succeeds; the fill itself is left alone.
function textOn(fill, background, foreground, ratio) {
  var want = ratio || 4.5
  var start = readableOn(fill, background, foreground)
  if (contrast(start, fill) >= want) return start
  var black = rgba(0, 0, 0, 1), white = rgba(1, 1, 1, 1)
  var dark = contrast(black, fill) >= contrast(white, fill)
  var base = (luminance(background) < luminance(foreground)) === dark ? background : foreground
  return readable(base, dark ? black : white, [fill], want)
}
