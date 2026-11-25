.pragma library

// Creates hosted-widget facades from this library's context (the engine's
// root context) rather than a bar's, so a facade stays callable while widgets
// torn down after their bar still hold it. Not cached: a hot reload must pick
// up a changed HostedBarApi.qml.
function create(url, props) {
  var component = Qt.createComponent(url)
  if (component.status !== 1) {
    console.warn("floating-islands: facade component failed: " + component.errorString())
    return null
  }
  return component.createObject(null, props)
}
