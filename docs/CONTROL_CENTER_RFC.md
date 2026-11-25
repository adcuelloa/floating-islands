# RFC: Community-Driven Unified Control Center

**Status:** Draft for Community Feedback (no widget placement or navigation hierarchy is finalized)  
**Target:** Pre-v1.0 design alignment  
**References:** Shoji Bar 2/3/4, Caelestia *(concept-only, GPL-3.0 boundary)*, Shibumi-Shell, Stellarchy, and Omarchy 4.5.0

## 1. Goal

Floating Islands currently hosts Omarchy's right-section widgets (`tray`, `keyboard-layout`, `agents`, `bluetooth`, `network`, `audio`, `monitor`, `power`) as separate icons in the status island, alongside an experimental Control Center behind `bar.islands.controlCenter: false`.

Our firm product goal is **one unified system-control entry point** so the status island stays compact and avoids prematurely compressing the bar on 1536 px logical displays. However, **where every Omarchy widget, button, indicator, and menu should live is an open community design decision.**

## 2. Complete Inventory of Built-In Omarchy Widgets (Omarchy 4.5.0)

| Widget ID | Stock Section | Role / Capability | Current Floating Islands Handling |
|---|---|---|---|
| `omarchy.menu` | `left` | Omarchy system/app menu launcher | Native launcher button in left island |
| `omarchy.workspaces` | `left` | Hyprland workspace dots/pills | Native workspace dots in left island |
| `omarchy.active-window` | *(optional)* | Active window title & icon | Native title island |
| `omarchy.indicators` | `centerBegin` | Active state badges: `PasswordlessSudo`, `ScreenRecording`, `RemoteSession`, `Reminder`, `NightLight`, `Dnd`, `StayAwake` | Not hosted by default; 3 toggles (`NightLight`, `Dnd`, `StayAwake`) exist in experimental Control Center |
| `omarchy.clock` | `center` | Time, date, calendar (`SUPER+CTRL+ALT+D`) | Native clock island + native Calendar panel |
| `omarchy.media` | *(service/widget)* | MPRIS playback controls | Native media island (hover preview + click pin) |
| `omarchy.elsewhen` | `centerEnd` | World clock (`SUPER+CTRL+ALT+E`) | Opt-in via `extraHosted` |
| `omarchy.weather` | `centerEnd` | Weather forecast (`SUPER+CTRL+ALT+W`) | Opt-in via `extraHosted` |
| `omarchy.system-update` | `centerEnd` | Available OS/Omarchy update indicator | Opt-in via `extraHosted` |
| `omarchy.tray` | `right` | System tray drawer (StatusNotifier apps) | Hosted in status island |
| `omarchy.keyboard-layout` | `right` | Active keyboard layout / fcitx5 (tooltip) | Hosted in status island |
| `omarchy.agents` | `right` | AI/background agents panel | Hosted in status island |
| `omarchy.bluetooth` | `right` | Bluetooth toggle + device panel | Hosted in status island + experimental CC tile |
| `omarchy.network` | `right` | Wi-Fi / Ethernet + Network panel | Hosted in status island + experimental CC tile |
| `omarchy.audio` | `right` | Volume / mute / device + Audio panel | Hosted in status island + experimental CC slider |
| `omarchy.monitor` | `right` | Display brightness / layout panel | Hosted in status island + experimental CC brightness slider |
| `omarchy.power` | `right` | Battery, power profile, power actions | Hosted in status island + experimental CC profile selector |
| `omarchy.microphone` | *(optional)* | Microphone mute/level indicator | Hosted if placed in `bar.layout.right` |
| `omarchy.dropbox` | *(optional)* | Dropbox sync status | Hosted if placed in `bar.layout.right` |
| `omarchy.tailscale` | *(optional)* | Tailscale VPN status & panel | Hosted if placed in `bar.layout.right` |
| `omarchy.spacer` | *(optional)* | Flexible layout spacer | Not needed in island layout |

## 3. Non-Negotiable Constraints

1. **Progressive migration rule:** Never unhost a stock widget before its native replacement provides sufficient functional parity or an explicitly accepted fallback. Never delete user `bar.layout` entries, disable underlying services, or use invisible stacked anchor buttons.
2. **Third-party & configured widget compatibility:** User-installed and cloned widgets (e.g., cloned `omarchy.audio`, custom status widgets) must keep their live state, panel, and shortcuts.
3. **Native Omarchy panel fallback:** Complex workflows (Wi-Fi passwords, Bluetooth pairing, display arrangement, Wi-Fi QR/speed test) must remain reachable via clean handover to Omarchy's native panels (one panel at a time).
4. **Upstream anchor constraint:** Omarchy 4.5.0's `PluginBarApi` currently has no panel-anchor redirection hook ([docs/COMPATIBILITY.md](COMPATIBILITY.md#platform-and-control-center-constraints)). Stock panels anchor directly to their own button until upstream adds an anchor hook or native replacements cover their quick flows.
5. **Keyboard accessibility:** Full keyboard navigation (Tab between groups, arrows within grids, slider keys, Escape to step back/close), keyboard-only focus rings, accurate `Accessible` roles/names/descriptions, and zero focus grabs while closed.
6. **Themes, reduced motion & multi-monitor:** Live `Theme.qml` tokens only (dark & light contrast), zero transitions when animations are off, and clean per-output anchoring on mixed-scale monitors.

## 4. Open Design Questions for Community Feedback

1. **System tray (`omarchy.tray`):** Should the system tray stay as a separate micro-island, an expandable drawer next to the Control Center entry, or a section/page inside the Control Center?
2. **Agents & third-party widgets (`omarchy.agents`, custom/cloned plugins):** Should they get dedicated slots on the bar, or live in an Extensions/Panels page inside the Control Center?
3. **Keyboard layout (`omarchy.keyboard-layout`):** Should the active layout indicator stay directly on the bar for 1-click/glanceable switching, or move into the Control Center?
4. **Passive & critical indicators (`omarchy.indicators`, `omarchy.microphone`, `omarchy.system-update`, low battery):** Which active states (`ScreenRecording`, `PasswordlessSudo`, `RemoteSession`, `Reminder`, `Microphone`, `SystemUpdate`) must always appear directly on the bar, and where (inline near the clock, separate micro-island, or badged on the Control Center entry)?
5. **Weather & World Clock (`omarchy.weather`, `omarchy.elsewhen`):** Should they remain opt-in bar islands, integrate with the Clock/Calendar island, or appear in the Control Center?
6. **Single entry visual composition:** Should the Control Center button show a single icon (+ alert dot), or a compact multi-glyph capsule (e.g., Wi-Fi + Audio + Battery acting as one unified button, inspired by Shoji Bar / macOS / GNOME)?
7. **Dashboard & subpage organization:** How should the main view group quick settings vs. detail subpages (e.g., Audio device picker, Bluetooth quick-connect, Power actions) vs. native panel links?
8. **Numbered hotkeys (`SUPER+CTRL+1..9`):** As legacy buttons are progressively replaced, should numbered hotkeys retain stock order, map only to remaining bar buttons, or bind to Control Center sections?
9. **Visual transitions:** What level of panel/page transition motion (inspired by Shoji Bar and Caelestia, respecting `Style.duration` and reduced motion) feels fast without being distracting?
