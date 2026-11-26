import QtQuick
import qs.Commons as Commons
import "../geometry/Layout.mjs" as Layout
import "Palette.js" as Palette

// The design's tokens, resolved against the live Omarchy theme. One instance
// is shared by every bar surface. Colors bind to Commons.Color, so a theme
// switch (pushed to the shell over IPC) repaints the islands without a reload;
// durations go through Style.duration, so `omarchy toggle animations` turning
// animations off makes every transition instant.
QtObject {
  id: theme

  // "compact" (40 px islands) or "comfortable" (46 px).
  property string density: "compact"
  // "top" or "bottom"; the edge the islands hang from.
  property string edge: "top"

  readonly property var m: Layout.metrics(Commons.Style.spacing.scale, density)

  // ------------------------------------------------------------- colors
  readonly property color background: Commons.Color.background
  readonly property color foreground: Commons.Color.bar.text
  readonly property color muted: Commons.Color.muted
  readonly property color accent: Commons.Color.accent
  readonly property color danger: Commons.Color.urgent
  // Islands sit a little above the theme's bar background, as the design's
  // surface sits above its background, so they hold an edge on any wallpaper.
  readonly property color surface: Palette.mix(Commons.Color.bar.background, foreground, 0.045)
  readonly property color raised: Palette.mix(surface, foreground, 0.06)
  readonly property color faint: Palette.mix(muted, background, 0.35)
  readonly property color hover: Palette.withAlpha(foreground, 0.08)
  readonly property color pressed: Palette.withAlpha(foreground, 0.14)
  readonly property color border: Palette.withAlpha(foreground, 0.10)
  readonly property color borderStrong: Palette.withAlpha(foreground, 0.22)
  readonly property color track: Palette.withAlpha(foreground, 0.16)
  readonly property color accentSoft: Palette.withAlpha(accent, 0.16)
  readonly property color shadow: Qt.rgba(0, 0, 0, 0.55)
  // The Control Center card (KeyboardPanel's popups.background), as drawn.
  readonly property color card: Palette.mix(background, Palette.withAlpha(Commons.Color.popups.background, 1), Commons.Color.popups.background.a)
  // What bar-island text is drawn on: the island surface (over the theme
  // background), and a button there hovered or pressed.
  readonly property var islandGrounds: {
    var island = Palette.mix(background, Palette.withAlpha(surface, 1), surface.a)
    return [island, Palette.mix(island, foreground, hover.a), Palette.mix(island, foreground, pressed.a)]
  }
  // Secondary text on an island (the clock's date, the empty-title
  // placeholder, the media artist): muted made readable there.
  readonly property color islandSecondaryText: Palette.readable(muted, foreground, islandGrounds)
  // Accent used as text on an island (the clock's weekday): kept where it
  // reads, moved toward the foreground just far enough otherwise.
  readonly property color islandAccentText: Palette.readable(accent, foreground, islandGrounds)
  // Text on a lit or selected control (the accent fill, composited on the
  // card): the theme's background or foreground when one reaches 4.5:1,
  // else the closer one moved toward black or white just far enough.
  readonly property color accentForeground: Palette.textOn(
    Palette.mix(card, Palette.withAlpha(accent, 1), accent.a), background, foreground)
  // What Control Center text is drawn on: the card, and a tile (plain or
  // hovered) on the card.
  readonly property var cardGrounds: [card, Palette.mix(card, Palette.withAlpha(surface, 1), surface.a), Palette.mix(card, foreground, hover.a)]
  // Failure text: the theme's urgent colour, moved toward the foreground
  // only as far as 4.5:1 needs on those. Many themes' urgent is under 4.5:1
  // on their own background.
  readonly property color dangerText: Palette.readable(danger, foreground, cardGrounds)
  // Secondary text that carries meaning (headings, a control's state,
  // notes): the theme's muted colour made readable the same way, still
  // weaker than foreground. Muted itself stays for disabled controls and
  // decoration; in most themes it is under 4.5:1.
  readonly property color secondaryText: Palette.readable(muted, foreground, cardGrounds)
  readonly property color tooltipBackground: Commons.Color.tooltip.background
  readonly property color tooltipText: Commons.Color.tooltip.text
  readonly property color tooltipBorder: Palette.withAlpha(Commons.Color.tooltip.border, 0.25)

  // --------------------------------------------------------- typography
  // The design pairs a sans for labels with a mono for figures. Omarchy's
  // configured family (`omarchy font set`) carries the figures; labels use
  // the fontconfig sans alias.
  readonly property string monoFamily: Commons.Style.font.family
  readonly property string textFamily: "sans-serif"
  readonly property real fontScale: Commons.Style.fontScale
  readonly property int textSize: Math.round(15 * fontScale)
  readonly property int timeSize: Math.round(16 * fontScale)

  // -------------------------------------------------------------- motion
  // The design's spring curve overshoots; Omarchy's motion rules ask for no
  // bounce, so its ease-out stands in for it.
  readonly property int fast: Commons.Style.duration(120)
  readonly property int widget: Commons.Style.duration(200)
  readonly property int colorChange: Commons.Style.duration(250)
  readonly property var easeOut: Commons.Style.easeOut
}
