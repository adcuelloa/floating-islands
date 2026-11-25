# Licensing and Attribution

Floating Islands is licensed under the **MIT License** ([LICENSE](../LICENSE)), with third-party icon path attribution in [THIRD_PARTY_LICENSES.md](../THIRD_PARTY_LICENSES.md).

> **Historical provenance note:** Replacing the nine prototype-derived SVG paths on the current tree resolves current-tree icon provenance only. It does **not** retroactively resolve or erase historical licensing concerns in prior Git commits that contained those earlier paths.

## Repository Asset Provenance Audit (Current Tree)

| Content | Origin | Provenance Status | License / Attribution |
|---|---|---|---|
| QML, JavaScript, shell scripts, tests, docs | Written for this project | **Original** | MIT (`LICENSE`) |
| Translations (`plugin/i18n/{en,es,ja}.json`) | Written for this project | **Original** | MIT (`LICENSE`) |
| Test fixture (`tests/qml/assets/app-icon.png`) | Synthetic 32×32 test PNG created for `tst_components` / title icon fallback tests | **Original** | MIT (`LICENSE`) |
| Interface stroke icons in `plugin/theme/Icons.js` (21 icons) | Derived from pinned [Lucide](https://lucide.dev/) `1.79.0` (`c26ce5515667640ca2753e095ba319d225fc0d8d`) | **Resolved on current tree** | ISC (Lucide) & MIT (Feather for `terminal`, `monitor`, `moon`, `chevron-right`) — see [THIRD_PARTY_LICENSES.md](../THIRD_PARTY_LICENSES.md) |
| Native Omarchy icons & application icons | Loaded at runtime from Omarchy's icon font (`\ue900`), hosted stock widgets, and `DesktopEntries` | **Runtime / not bundled** | Not stored in this repository |
| Design tokens (dimensions, alpha ratios, durations) | Functional layout, contrast, and timing parameters re-expressed natively against Omarchy's `Commons.Color` and `Commons.Style` | **Reviewed** | Ordinary functional layout, contrast, and timing parameters; no themes, wallpapers, or fonts are bundled (all remain owned by Omarchy) |

### Lucide Icon Mapping (`plugin/theme/Icons.js`)

Pinned upstream: `lucide-icons/lucide` tag `1.79.0`, commit `c26ce5515667640ca2753e095ba319d225fc0d8d`.

Modifications applied to upstream SVGs:
- `<rect>`, `<circle>`, and `<line>` elements converted to `PathSvg` path commands (no SVG/web runtime added).
- Leading relative `m` commands on multi-element icons normalized to absolute `M` (+ `l`) for safe concatenation into a single `PathSvg`.
- `play` (`stroke` + `fill`) and `pause` (`fill`) rendered filled to preserve media-island visual emphasis; strokes rendered at width `1.8` in `StrokeIcon.qml`.

| `Icons.js` Key | Upstream Lucide Icon | Upstream License | Notes |
|---|---|---|---|
| `grid` | `layout-grid` | ISC | Replaced earlier original icon for visual consistency |
| `terminal` | `terminal` | MIT (Feather) | Replaced prototype-derived path |
| `browser` | `globe` | ISC | Replaced prototype-derived path |
| `code` | `code-xml` | ISC | Replaced prototype-derived path |
| `note` | `file-text` | ISC | Replaced prototype-derived path |
| `empty` | `monitor` | MIT (Feather) | Replaced prototype-derived path |
| `generic` | `app-window` | ISC | Replaced earlier original icon for visual consistency |
| `previous` | `skip-back` | ISC | Replaced prototype-derived path |
| `next` | `skip-forward` | ISC | Replaced prototype-derived path |
| `play` | `play` | ISC | Replaced prototype-derived path; rendered filled (`stroke` + `fill`) |
| `pause` | `pause` | ISC | Replaced prototype-derived path; rendered filled (`fill`) |
| `controlCenter` | `sliders-horizontal` | ISC | Replaced earlier original icon for visual consistency |
| `nightlight` | `moon` | MIT (Feather) | Replaced earlier original icon for visual consistency |
| `stayAwake` | `coffee` | ISC | Replaced earlier original icon for visual consistency |
| `doNotDisturb` | `bell-off` | ISC | Replaced earlier original icon for visual consistency |
| `speaker` | `volume-2` | ISC | Replaced earlier original icon for visual consistency |
| `speakerMuted` | `volume-x` | ISC | Replaced earlier original icon for visual consistency |
| `brightness` | `sun` | ISC | Replaced earlier original icon for visual consistency |
| `wifi` | `wifi` | ISC | Replaced earlier original icon for visual consistency |
| `bluetooth` | `bluetooth` | ISC | Replaced earlier original icon for visual consistency |
| `chevron` | `chevron-right` | MIT (Feather) | Replaced earlier original icon for visual consistency |

The repository contains **no** wallpapers, themes, fonts, personal configuration, credentials, or desktop screenshots; Omarchy retains ownership of themes, wallpapers, fonts, and core services. Test fixtures use synthetic IDs (`user.audio`, `user.lock`) and generic connector names (`eDP-1`).

### Design-Token Provenance Review

The numeric layout dimensions, surface alpha/contrast ratios, and animation durations in `plugin/theme/Theme.qml`, `plugin/theme/Palette.js`, and `plugin/geometry/Layout.js` were reviewed and recorded as ordinary functional layout, contrast, and timing parameters bound natively to Omarchy's `Commons.Color` and `Commons.Style` tokens (with reduced-motion routing through `Style.duration`). This review applies to the current tree and does not claim to retroactively resolve historical asset provenance in prior Git commits.

## Runtime Dependencies (Used, Not Bundled)

| Dependency | License | How It Is Used |
|---|---|---|
| Omarchy (`omarchy`, `$OMARCHY_PATH/shell`) | MIT | Imported at runtime as `qs.Commons` and `qs.Ui`. `HostedBarApi` extends `PluginBarApi` by type name; no Omarchy source is copied. `logic/Workspaces.js` reimplements Omarchy's workspace numbering behavior with attribution. |
| Quickshell | LGPL-3.0-only | Runtime QML modules; not bundled or modified. |
| Qt 6 (`QtQuick`, `Shapes`, `Effects`, `QtTest`) | LGPL-3.0 / GPL-3.0 | Runtime QML modules; not bundled. |
| Hyprland | BSD-3-Clause | Invoked via `hyprctl` and Quickshell IPC. |
| `jq`, `bash`, `coreutils`, `bubblewrap`, `node` (tests only) | MIT / GPL / LGPL | Invoked as external programs. |

## Design Reference License Boundaries

- **Omarchy** (MIT): public bar and widget contracts.
- **Shibumi-Shell** (MIT): architectural reference only; nothing copied.
- **Caelestia** (`caelestia-dots/shell`, GPL-3.0): **concept-only reference** (e.g., Quickshell's public `DesktopEntries.heuristicLookup` API and dashboard grouping concepts). **No GPL-3.0 code has been read into or copied into this MIT repository.**
