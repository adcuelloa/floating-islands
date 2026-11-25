.pragma library

// General-purpose 24x24 stroke icons for QtQuick.Shapes PathSvg.
//
// Upstream provenance:
//   Source:   https://github.com/lucide-icons/lucide
//   Version:  1.79.0
//   Commit:   c26ce5515667640ca2753e095ba319d225fc0d8d
//   License:  ISC License (Lucide Icons and Contributors) and MIT License
//             (Feather icons: terminal, monitor, moon, chevron-right).
//             Full license texts live in THIRD_PARTY_LICENSES.md.
//
// Modifications from upstream SVG files:
//   1. SVG <rect>, <circle>, and <line> primitives are converted to equivalent
//      SVG path data so QtQuick.Shapes PathSvg can render them without an SVG
//      or web runtime.
//   2. Leading relative `m` commands on multi-element icons are normalized to
//      absolute `M` (+ `l` when implicit lineto pairs follow) so multiple
//      subpaths concatenate safely inside a single PathSvg string.
//   3. `play` (stroke + fill) and `pause` (fill) use filled rendering to match
//      the media island's visual emphasis; StrokeIcon.qml renders strokes at
//      width 1.8 with round caps and joins.
//
// Native Omarchy icons (launcher logo glyph in LauncherIsland, hosted stock
// widgets) and real DesktopEntries application icons (TitleIsland) are NOT
// defined here and remain untouched.

var provenance = {
  family: "Lucide",
  version: "1.79.0",
  commit: "c26ce5515667640ca2753e095ba319d225fc0d8d",
  license: "ISC AND MIT"
}

// Launcher alternative to the Omarchy logo glyph: Lucide `layout-grid` (ISC).
var grid = {
  stroke: "M4 3h5a1 1 0 0 1 1 1v5a1 1 0 0 1 -1 1h-5a1 1 0 0 1 -1 -1v-5a1 1 0 0 1 1 -1z" +
          "M15 3h5a1 1 0 0 1 1 1v5a1 1 0 0 1 -1 1h-5a1 1 0 0 1 -1 -1v-5a1 1 0 0 1 1 -1z" +
          "M15 14h5a1 1 0 0 1 1 1v5a1 1 0 0 1 -1 1h-5a1 1 0 0 1 -1 -1v-5a1 1 0 0 1 1 -1z" +
          "M4 14h5a1 1 0 0 1 1 1v5a1 1 0 0 1 -1 1h-5a1 1 0 0 1 -1 -1v-5a1 1 0 0 1 1 -1z"
}

// Window-kind fallback symbols (used when titleIcon === "symbol" or no
// DesktopEntries app icon resolves).
// Lucide `terminal` (Feather MIT).
var terminal = { stroke: "M12 19h8M4 17l6 -6 -6 -6" }

// Lucide `globe` (ISC).
var browser = {
  stroke: "M2 12a10 10 0 1 0 20 0a10 10 0 1 0 -20 0M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20M2 12h20"
}

// Lucide `code-xml` (ISC).
var code = { stroke: "M18 16l4 -4 -4 -4M6 8l-4 4 4 4M14.5 4l-5 16" }

// Lucide `file-text` (ISC).
var note = {
  stroke: "M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z" +
          "M14 2v5a1 1 0 0 0 1 1h5M10 9H8M16 13H8M16 17H8"
}

// Desktop with no active window: Lucide `monitor` (Feather MIT).
var empty = {
  stroke: "M4 3h16a2 2 0 0 1 2 2v10a2 2 0 0 1 -2 2h-16a2 2 0 0 1 -2 -2v-10a2 2 0 0 1 2 -2zM8 21L16 21M12 17L12 21"
}

// Any other application: Lucide `app-window` (ISC).
var generic = {
  stroke: "M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-16a2 2 0 0 1 -2 -2v-12a2 2 0 0 1 2 -2zM10 4v4M2 8h20M6 4v4"
}

// Media controls: Lucide `skip-back`, `skip-forward`, `play`, `pause` (ISC).
// `play` and `pause` are filled for primary transport emphasis.
var previous = {
  stroke: "M17.971 4.285A2 2 0 0 1 21 6v12a2 2 0 0 1-3.029 1.715l-9.997-5.998a2 2 0 0 1-.003-3.432zM3 20V4"
}
var next = {
  stroke: "M21 4v16M6.029 4.285A2 2 0 0 0 3 6v12a2 2 0 0 0 3.029 1.715l9.997-5.998a2 2 0 0 0 .003-3.432z"
}
var play = {
  stroke: "M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z",
  fill:   "M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z"
}
var pause = {
  stroke: "",
  fill: "M15 3h3a1 1 0 0 1 1 1v16a1 1 0 0 1 -1 1h-3a1 1 0 0 1 -1 -1v-16a1 1 0 0 1 1 -1z" +
        "M6 3h3a1 1 0 0 1 1 1v16a1 1 0 0 1 -1 1h-3a1 1 0 0 1 -1 -1v-16a1 1 0 0 1 1 -1z"
}

function forKind(kind) {
  if (kind === "terminal") return terminal
  if (kind === "browser") return browser
  if (kind === "code") return code
  if (kind === "note") return note
  if (kind === "empty") return empty
  return generic
}

// Control Center icons (standardized on Lucide 1.79.0 for consistent geometry).
// Lucide `sliders-horizontal` (ISC).
var controlCenter = { stroke: "M10 5H3M12 19H3M14 3v4M16 17v4M21 12h-9M21 19h-5M21 5h-7M8 10v4M8 12H3" }
// Lucide `moon` (Feather MIT).
var nightlight = {
  stroke: "M20.985 12.486a9 9 0 1 1-9.473-9.472c.405-.022.617.46.402.803a6 6 0 0 0 8.268 8.268c.344-.215.825-.004.803.401"
}
// Lucide `coffee` (ISC).
var stayAwake = {
  stroke: "M10 2v2M14 2v2M16 8a1 1 0 0 1 1 1v8a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4V9a1 1 0 0 1 1-1h14a4 4 0 1 1 0 8h-1M6 2v2"
}
// Lucide `bell-off` (ISC).
var doNotDisturb = {
  stroke: "M10.268 21a2 2 0 0 0 3.464 0M17 17H4a1 1 0 0 1-.74-1.673C4.59 13.956 6 12.499 6 8a6 6 0 0 1 .258-1.742" +
          "M2 2l20 20M8.668 3.01A6 6 0 0 1 18 8c0 2.687.77 4.653 1.707 6.05"
}
// Lucide `volume-2` (ISC).
var speaker = {
  stroke: "M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1" +
          "h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z" +
          "M16 9a5 5 0 0 1 0 6M19.364 18.364a9 9 0 0 0 0-12.728"
}
// Lucide `volume-x` (ISC).
var speakerMuted = {
  stroke: "M11 4.702a.7.7 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1" +
          "h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.7.7 0 0 0 11 19.298z" +
          "M16.5 14.5l5 -5M16.5 9.5l5 5"
}
// Lucide `sun` (ISC).
var brightness = {
  stroke: "M8 12a4 4 0 1 0 8 0a4 4 0 1 0 -8 0M12 2v2M12 20v2M4.93 4.93l1.41 1.41" +
          "M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"
}
// Lucide `wifi` (ISC).
var wifi = {
  stroke: "M12 20h.01M2 8.82a15 15 0 0 1 20 0M5 12.859a10 10 0 0 1 14 0M8.5 16.429a5 5 0 0 1 7 0"
}
// Lucide `bluetooth` (ISC).
var bluetooth = { stroke: "M7 7l10 10 -5 5V2l5 5L7 17" }
// Lucide `chevron-right` (Feather MIT).
var chevron = { stroke: "M9 18l6 -6 -6 -6" }
