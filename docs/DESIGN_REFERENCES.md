# Design Principles & References

## Core Principles

1. **Native Omarchy citizen:** Floating Islands runs inside `omarchy-shell` as a standard `kind: "bar"` plugin, follows Omarchy's live theme tokens (`Commons.Color`, `Commons.Style`), respects `omarchy toggle animations`, and preserves Omarchy's layer rules (`omarchy-bar`).
2. **Focusless bar, scoped panels:** The bar surface never takes keyboard focus or intercepts clicks in transparent gaps. Interactive popouts use Omarchy's `KeyboardPanel` with clean Escape and outside-click dismissal.
3. **Predictable geometry:** Responsive tiers (`full`, `compact`, `minimal`) are computed per output from measured widths with hysteresis rather than fixed pixel breakpoints. Panels keep fixed footprints and scroll internally on short screens or large font scales.
4. **Honest state:** Controls display observed system state rather than optimistic assumptions, showing pending, unavailable, and failure states clearly.
5. **Accessibility by default:** Full keyboard navigation, focus rings visible only after keyboard use, accessible roles/names/descriptions, and readable contrast across dark and light themes.

## Architecture & Visual References

These projects inform interaction patterns and visual ergonomics. License boundaries are strictly respected — **no code is copied from GPL-3.0 references into this MIT repository**.

| Project | License | Reference Role |
|---|---|---|
| **Omarchy** (`omacom/omarchy`) | MIT | Host shell, `PluginBarApi`, `KeyboardPanel`, widget registry, theme tokens, and stock panel fallback contracts. |
| **Shoji Bar 2 / 3 / 4** | Reference | Floating-island geometry, compact single-entry status cluster, quick-settings density, and fluid visual transitions. |
| **Caelestia** (`caelestia-dots/shell`) | GPL-3.0 | **Concept-only:** unified dashboard grouping, separation of quick toggles vs. sliders vs. detail pages, and Quickshell public API patterns (`DesktopEntries.heuristicLookup`). No code read into or copied into this repository. |
| **Shibumi-Shell** (`HANCORE-linux/Shibumi-Shell`) | MIT | Native Omarchy/Quickshell plugin integration patterns, theme-aware widgets, and hosted-panel ergonomics. Nothing copied. |
| **Stellarchy** | Reference | Modular Quickshell panel organization, dynamic color theming, and sidebar/dashboard ergonomics. |

For current open design questions on the Unified Control Center, see [docs/CONTROL_CENTER_RFC.md](CONTROL_CENTER_RFC.md). For detailed deviations from the original prototype, see [docs/DECISIONS.md](DECISIONS.md).
