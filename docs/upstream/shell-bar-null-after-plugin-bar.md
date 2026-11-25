# Draft upstream issue (not submitted)

> Draft for review. Target: omacom/omarchy. Before submitting, re-check the
> current `quattro` branch and search for a duplicate. As of 2026-10-28,
> `shell/shell.qml` on `quattro` still has the line below unguarded. Related
> but different issues: #10324, #10745 and #7418 (load-error fallback), and
> #13289 (service-less entry facade).

---

**Title:** Switching from a plugin bar back to the built-in bar leaves `shell.bar` null (panel hotkeys and `summon` stop working)

### Version

- omarchy 4.5.0rc2-1 (also present on `quattro` at 91acd2c)
- quickshell 0.3.2.r7.g2b4501a-1
- Hyprland 0.56.2

### What happens

After a `kind: "bar"` plugin has been the active bar, `omarchy bar reset`
correctly brings the built-in bar back on screen, and it takes clicks. But the
shell's `shell.bar` stays `null` until `omarchy-shell` is restarted. As a
result:

- `omarchy-shell shell summon <bar-widget id>` returns `unknown`, and the
  journal logs "summon: no live bar widget for: …";
- `omarchy-shell shell togglePanelAt right 1` returns `unknown`, so panel
  hotkeys do nothing;
- `omarchy-shell shell debugBarGeometry` returns `[]`;
- `PluginBarStateApi` reports no bar to plugins (`barSize` 0), so placement
  that clears the bar (e.g. notification toasts) loses its reference.

### Steps to reproduce

1. Install any third-party bar plugin, e.g. a clone of `omarchy.bar` that
   loads successfully.
2. `omarchy bar use <its id>`. The plugin bar appears;
   `omarchy-shell shell debugBarGeometry` returns data.
3. `omarchy bar reset`. The built-in bar appears.
4. `omarchy-shell shell debugBarGeometry` now returns `[]`, and
   `omarchy-shell shell summon omarchy.audio` returns `unknown`.
5. `omarchy restart shell` brings everything back.

### Cause

`shell/shell.qml`, the two bar loaders:

```qml
Loader {
  id: defaultBarLoader
  active: shell.activeBarId === shell.defaultBarId
  sourceComponent: defaultBarComponent
  onLoaded: shell.configureBar(item, shell.barManifestFor(shell.defaultBarId))
  onActiveChanged: if (!active && shell.activeBarId !== shell.defaultBarId) shell.bar = null
}

Loader {
  id: pluginBarLoader
  active: !shell.pluginReloading && shell.activeBarId !== shell.defaultBarId && shell.activeBarSourceUrl !== ""
  ...
  onLoaded: shell.configureBar(item, shell.activeBarManifest)
  onActiveChanged: if (!active) shell.bar = null        // <- unguarded
}
```

When `activeBarId` returns to `omarchy.bar`, both `active` bindings
re-evaluate. `defaultBarLoader` loads synchronously, and its `onLoaded` sets
`shell.bar` to the new built-in bar. Then `pluginBarLoader` becomes inactive,
and its unguarded `onActiveChanged` sets `shell.bar = null`. The default
loader's handler already carries the matching guard; the plugin loader's does
not.

### Suggested fix

Mirror the default loader's guard, so the plugin loader clears the reference
only when the built-in bar is not the one taking over:

```qml
onActiveChanged: if (!active && shell.activeBarId !== shell.defaultBarId) shell.bar = null
```

This keeps today's behaviour where the reference must be cleared:

- **Plugin-to-plugin switch.** The next `onLoaded` publishes the new bar.
- **Plugin hot reload.** `pluginReloading` makes the loader inactive briefly,
  and it publishes again on load.

The only change is that it no longer clears the reference the built-in bar
has just published. (Comparing against `item` is not reliable here: the
Loader is already tearing its item down when `active` turns false.)

### Workaround

`omarchy restart shell` after `omarchy bar reset`.
