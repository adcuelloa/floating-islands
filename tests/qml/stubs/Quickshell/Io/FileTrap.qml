pragma Singleton
import QtQuick

// Test-only: the files FileView stubs read, and their watchers.
//   setFile(path, text)  a file's content; null (or removeFile) = missing
//   change(path, text)   a new content, then fileChanged on its watchers
//   settle()             completes every queued read
//   reads(path)          how many reads of that path completed
//   watchers(path)       how many live views watch that path
QtObject {
  id: trap

  property var files: ({})
  property var views: []
  property var pending: []
  property var readCount: ({})
  property bool autoSettle: true

  function setFile(path, text) { var f = Object.assign({}, trap.files); f[path] = text; trap.files = f }
  function removeFile(path) { trap.setFile(path, null) }
  function contentOf(path) { return Object.prototype.hasOwnProperty.call(trap.files, path) ? trap.files[path] : null }

  function change(path, text) {
    trap.setFile(path, text)
    var list = trap.views.slice()
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].watchChanges && list[i].path === path) list[i].fileChanged()
  }

  function register(v) { trap.views = trap.views.concat([v]) }
  function unregister(v) { trap.views = trap.views.filter(function(x) { return x !== v }) }

  function queue(v) {
    if (trap.pending.indexOf(v) === -1) trap.pending = trap.pending.concat([v])
    if (trap.autoSettle) Qt.callLater(trap.settle)
  }
  function unqueue(v) { trap.pending = trap.pending.filter(function(x) { return x !== v }) }

  function settle() {
    var list = trap.pending
    trap.pending = []
    for (var i = 0; i < list.length; i++) {
      var v = list[i]
      var c = Object.assign({}, trap.readCount)
      c[v.path] = (c[v.path] || 0) + 1
      trap.readCount = c
      v.testComplete()
    }
  }

  function reads(path) { return trap.readCount[path] || 0 }
  function watchers(path) {
    var n = 0
    for (var i = 0; i < trap.views.length; i++) if (trap.views[i].watchChanges && trap.views[i].path === path) n++
    return n
  }

  function reset() { trap.files = {}; trap.pending = []; trap.readCount = {}; trap.autoSettle = true }
}
