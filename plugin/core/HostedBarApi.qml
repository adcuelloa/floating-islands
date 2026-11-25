import QtQuick
import qs.Ui

// The bar surface a hosted widget sees: Omarchy's own PluginBarApi facade,
// plus barSizeFor(). Widgets size their buttons to `barSize` (the island's
// inner height here), while KeyboardPanel and toasts clear the bar by
// barSizeFor() (gap + island), so the two must differ for floating islands.
PluginBarApi {
  property var _barSizeFor: null

  function barSizeFor(screenName) {
    return _barSizeFor ? _barSizeFor(String(screenName || "")) : barSize
  }
}
