.pragma library

// The project's names, in one place. The plugin id that matters at runtime is
// the one in manifest.json, which the shell injects as `manifest.id`; the
// fallback below only covers the moment before that injection. Renaming the
// project means editing manifest.json and this file, nothing else.

var fallbackPluginId = "floating-islands"

// Key of this bar's own settings object inside shell.json's `bar` subtree:
// { "bar": { "islands": { ... } } }.
var settingsKey = "islands"

// IPC target for diagnostics (`omarchy-shell floating-islands geometry`).
var ipcTarget = "floating-islands"

// Layer-shell namespace. Kept equal to the stock bar's so Omarchy's own
// Hyprland layer rules (no open/close animation, glassy blur) apply unchanged.
var layerNamespace = "omarchy-bar"
