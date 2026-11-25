import QtQuick

// Stands in for Quickshell's FileView: nothing is read from disk. Contents
// come from FileTrap, keyed by path. Loading is asynchronous as in
// Quickshell: setting a path (with preload) or calling reload() queues a
// read that completes on FileTrap.settle(), or by itself on the next event
// loop turn while FileTrap.autoSettle is true. A view with watchChanges and
// a path is a watcher: FileTrap.change() updates a file and signals every
// watcher of that path, as inotify would.
QtObject {
  id: view

  property string path: ""
  property bool watchChanges: false
  property bool preload: true
  property bool blockLoading: false
  property bool printErrors: true

  property string _text: ""

  signal loaded()
  signal loadFailed(int error)
  signal fileChanged()

  function text() { return view._text }
  // As in Quickshell 0.3.2 (fileview.cpp, operationFinished): the finishing
  // read is still the live operation while loaded/loadFailed run, so a
  // reload() from their handlers is a no-op.
  property bool _finishing: false
  function reload() { if (view.path !== "" && !view._finishing) FileTrap.queue(view) }
  function waitForJob() { return false }

  // Called by FileTrap when this view's queued read completes.
  function testComplete() {
    var content = FileTrap.contentOf(view.path)
    view._finishing = true
    if (content === null) { view._text = ""; view.loadFailed(1) }
    else { view._text = content; view.loaded() }
    view._finishing = false
  }

  onPathChanged: {
    FileTrap.unqueue(view)
    view._text = ""
    if (view.path !== "" && view.preload) FileTrap.queue(view)
  }
  Component.onCompleted: { FileTrap.register(view); if (view.path !== "" && view.preload) FileTrap.queue(view) }
  Component.onDestruction: { FileTrap.unqueue(view); FileTrap.unregister(view) }
}
