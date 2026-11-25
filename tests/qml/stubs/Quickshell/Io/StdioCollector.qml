import QtQuick

// Stands in for Quickshell's StdioCollector: a test sets the text the
// command printed before ending it.
QtObject {
  property string text: ""
}
