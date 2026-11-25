# Decisions and deviations from the approved design

The Claude Design V2 prototype (Floating Islands, HTML/React) is the visual and
behavioural specification. It was not translated into QML mechanically.
Geometry, colour roles, type hierarchy and interaction were re-expressed
natively. This file records each place where the native bar differs from the
prototype, and why.

## Kept from the prototype

- **Islands.** 40 px high (46 comfortable), radius 12, 1 px border at
  foreground 10 %, shadow `0 4 14 −6 rgba(0,0,0,.55)`, horizontal padding 4,
  2 px between items. 10 px from the edge, 12 px from the sides, 8 px between
  islands.
- **Buttons.** `H − 8` high, at least 40 wide, padding 10, radius 8. Hover
  fill 8 %, pressed fill 14 %, a 0.97 press scale. The hit area reaches the
  screen edge.
- **Launcher.** The design's ring-and-dot icon in the accent, a hairline
  divider, then the workspaces as dots: ring for empty, dot for occupied,
  24 px accent pill for the one shown.
- **Title island.** Padding 12/14, gap 10, an 18 px monochrome icon in the
  muted colour, the title in the foreground (muted for an empty workspace),
  elided. Capped at 480 px in full and 240 px in compact.
- **Clock island.** Time in the mono face at 16 px, weight 600, letter-spacing
  0.02 em. Then the date in the muted colour, with the weekday in the accent
  at weight 500; gap 12, padding 14.
- **Durations.** 120 ms (fast), 200 ms (widgets).

## Deviations

| # | Prototype | Native | Reason |
|---|---|---|---|
| D1 | Tier thresholds at 1700 and 1200 px | Measured, per output, with hysteresis | The thresholds assumed CSS pixels and mis-tier scaled outputs (COMPATIBILITY.md) |
| D2 | Spring easing with overshoot | `Style.easeOut` and `OutCubic` | Omarchy's plugin motion rules: no bounce |
| D3 | Theme cross-fade 360 ms | 250 ms, as the stock bar | Stays under the 300 ms ceiling |
| D4 | `prefers-reduced-motion` | `Style.duration` (`omarchy toggle animations`) | The native source of truth |
| D5 | IBM Plex Sans, JetBrains Mono, Zen Kaku Gothic New | fontconfig `sans-serif` for labels; Omarchy's configured family for figures | Bundling or requiring fonts is out of scope; the hierarchy is kept by size and weight. A kanji workspace style can use Noto Sans CJK later |
| D6 | Panels 58 px from the edge, 8 px below the islands | 8 px below the islands, with Hyprland's gaps on or off (polish branch). Omarchy places panels at `barSizeFor + Style.gapsOut` (half of `gaps_out`, 0 after Super+Shift+Backspace), so the bar reports `islandEdge + 8 − Style.gapsOut` (`Layout.panelBarSize`). Before: 5 px, or 0 px with gaps off | The exclusive zone is unchanged; only the size panels and toasts are told changes |
| D7 | Appearance option: fixed palette | Always follows the Omarchy theme | Avoids a second theme system |
| D8 | Notification-centre panel and bell | Not in the MVP | No history API for bar plugins |
| D9 | Panel height from a 1080 px assumption | `screen.height` in logical px (`Layout.panelMaxHeight`) | Same issue as D1 |
| D10 | Tab focus and arrow keys within the bar | The bar never takes keyboard focus; workspaces follow Hyprland's keybindings | A layer-shell bar must not take focus from applications. A focus hotkey needs a design of its own |
| D11 | Per-app icons for terminal, web, code and note | The application's own icon from its desktop entry (`DesktopEntries.heuristicLookup` + `Quickshell.iconPath`, as Omarchy's dock does), falling back to the design's symbols (the four, plus a generic window). `bar.islands.titleIcon: "symbol"` keeps the monochrome symbols | Real applications are not limited to four kinds, and a single globe for every browser was reported in trial 4 |
| D12 | Island surface `#22201d` on `#171614` | The theme's bar background lifted 4.5 % toward the foreground | The same relationship, expressed against any theme |
| D13 | Calendar panel | Implemented (Milestone 2) on Omarchy's KeyboardPanel. Padding 16, width 340, layout per V2. **Six weeks always**, where the prototype shows five or six: the panel keeps its height between months instead of resizing under the cursor | Stable geometry; KeyboardPanel would animate the height change each month |
| D14 | A media island and a status island on the right | The native media island (Milestone 2), and the status island as hosted Omarchy widgets | The status island's contents are Omarchy's own widgets, so every system control keeps working |
| D15 | Tooltips | Drawn on the bar surface for hosted widgets that request them, 8 px below the islands like the panels. Working live since trial 3 | The stock bar's tooltip window is not public; the surface already spans the screen |
| D16 | Equaliser bars animate continuously while playing | Same, but `bar.islands.mediaEqualizer: "static"` turns it off, and reduced motion stops it | A constantly animating bar redraws its surface while music plays; the option is there for battery-conscious use |
| D17 | Media progress line | A 3 px line under the title, aligned with it, shown while the controls are out; the position is read once a second, only while expanded and playing. No seeking: the media service exposes no seek action | MPRIS position is not pushed; polling all the time is avoided. The line used to run 4 px above the island's border |
| D18 | Calendar and clock language from the prototype's en/es/ja switch | `bar.islands.locale`: `auto` (the Omarchy language) or `en`, `es`, `ja`. Week starts come from Qt's locale data, so `auto` with US English starts on Sunday | Follows the desktop's language unless told otherwise |
| D19 | Launcher mark | Omarchy's logo (`\ue900` in the installed `omarchy` icon font, as the stock menu widget), in the theme accent; `bar.islands.launcherIcon: "grid"` for a generic application grid | The prototype's stroke mark read as "refresh" (trial 4) |
| D20 | Hover behaviour | Media island: closed, a preview after the pointer rests 250 ms (leaving ends it), pinned by a click (a second click ends it). Calendar: click or IPC only, persistent until Escape, an outside click or the clock again; no hover preview | Omarchy's KeyboardPanel takes keyboard focus when it opens, so a hover-opened calendar would take focus from the application under the pointer; a focusless preview would duplicate the panel |
| D22 | Pinned media dismissal | A second click or a workspace switch closes pinned controls. No Escape, no outside-click dismissal, no closing on window focus | Escape needs keyboard focus, which a mapped layer surface on Hyprland only gets through a focus grab (the click that clears it is swallowed, and keys typed into a hovered window go to the bar) or Exclusive focus (takes every pointer event). Both block application input (trial 5 recheck). With focus-follows-mouse, a window focus change is only the pointer passing over a window, so it cannot close pinned controls either |
| D21 | Workspace spacing | 28 px slots (the 24 px pill plus 2 px a side), contiguous pointer targets | The generic 40 px button minimum spaced the dots widely |

## Engineering decisions

- **One plugin, no new process.** Everything runs inside `omarchy-shell`.
- **Same layer namespace as the stock bar** (`omarchy-bar`), so Omarchy's
  layer rules (no open animation, glassy blur) apply unchanged.
- **Answers the `omarchy.bar syncHidden` IPC nudge.** `omarchy toggle bar`
  sends it to whichever bar is active, and the stock bar's handler is gone
  while this bar is loaded.
- **Activation is a trial by default.** It is bound to the Hyprland instance
  and ends at the next login on its own (ARCHITECTURE.md, Trial mode).
- **Rollback never depends on the shell.** It uses `omarchy bar reset` when
  available, and `jq` on `shell.json` otherwise.
