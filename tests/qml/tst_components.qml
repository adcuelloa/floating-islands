import QtQuick
import QtTest
import "../../plugin/theme"
import "../../plugin/components"
import "../../plugin/widgets"
import "../../plugin/theme/Icons.js" as Icons

Item {
  id: scene
  width: 800
  height: 120

  Theme { id: theme }

  QtObject {
    id: strings
    // Keys LauncherIsland formats with .arg() keep their %1, as en.json does.
    property var formats: ({ "window.none": "Empty workspace", "workspace": "Workspace %1", "workspace.empty": "Workspace %1, empty" })
    function t(key) { return formats[key] !== undefined ? formats[key] : key }
  }

  // What LauncherIsland reads from WorkspacesAdapter.
  QtObject {
    id: fakeWorkspaces
    property var entries: [
      { id: 1, label: "1", active: true, occupied: true, firstGuest: false },
      { id: 2, label: "2", active: false, occupied: true, firstGuest: false },
      { id: 3, label: "3", active: false, occupied: false, firstGuest: false }
    ]
    property var focused: []
    function focus(id) { focused = focused.concat([id]) }
    function scroll(delta) { }
  }

  LauncherIsland {
    id: launcherIsland
    y: 60
    theme: theme
    workspaces: fakeWorkspaces
    strings: strings
  }

  SignalSpy { id: launcherSpy; target: launcherIsland; signalName: "launcherClicked" }

  Island {
    id: island
    theme: theme
    Rectangle { width: 50; height: 20 }
    Rectangle { width: 30; height: 20 }
  }

  IslandButton {
    id: button
    x: 400
    y: 60
    theme: theme
    reachTop: 14
    reachBottom: 5
    StrokeIcon { icon: Icons.grid; size: 20 }
  }

  WorkspaceDot { id: dot; theme: theme }

  QtObject {
    id: windowState
    property bool empty: false
    property string title: "nvim — a very long file name that will not fit in the space given to it by the layout"
    property string kind: "code"
    property string iconSource: ""
  }

  TitleIsland {
    id: titleIsland
    theme: theme
    window: windowState
    strings: strings
    maximumWidth: 240
  }

  TestCase {
    name: "Components"
    when: windowShown

    function findNamed(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var found = findNamed(item.children[i], name)
        if (found) return found
      }
      return null
    }

    // Trial 4: the launcher's glyph read as "refresh". It is Omarchy's own logo
    // now (the stock menu widget's \ue900 in the omarchy font), in the accent.
    function test_launcherShowsTheOmarchyLogo() {
      launcherIsland.iconStyle = "omarchy"
      var logo = findNamed(launcherIsland, "launcherLogo")
      verify(logo && logo.visible, "logo shown")
      compare(logo.text, "\ue900")
      compare(logo.font.family, "omarchy")
      compare(String(logo.color), String(theme.accent))
      verify(!findNamed(launcherIsland, "launcherGrid").visible)
    }

    function test_launcherGridAlternative() {
      launcherIsland.iconStyle = "grid"
      verify(findNamed(launcherIsland, "launcherGrid").visible)
      verify(!findNamed(launcherIsland, "launcherLogo").visible)
      compare(findNamed(launcherIsland, "launcherGrid").icon, Icons.grid)
      launcherIsland.iconStyle = "omarchy"
    }

    // Compact workspaces: a slot is the 24 px pill plus 2 px each side (was
    // 40 px), slots touch so there is no dead pointer zone, and a click still
    // focuses the workspace.
    function test_workspaceSlotsAreCompactAndContiguous() {
      var buttons = []
      function collect(item) {
        if (item.objectName === "workspaceButton") buttons.push(item)
        for (var i = 0; i < item.children.length; i++) collect(item.children[i])
      }
      collect(launcherIsland)
      compare(buttons.length, 3)
      compare(buttons[0].accessibleName, "Workspace 1")
      compare(buttons[1].accessibleName, "Workspace 2")
      compare(buttons[2].accessibleName, "Workspace 3, empty")
      for (var i = 0; i < buttons.length; i++) {
        compare(buttons[i].width, theme.m.workspaceSlot, "slot " + i)
        compare(buttons[i].height, theme.m.islandHeight - 2 * theme.m.buttonInset)
        if (i > 0) {
          var prev = buttons[i - 1].mapToItem(launcherIsland, 0, 0).x + buttons[i - 1].width
          compare(buttons[i].mapToItem(launcherIsland, 0, 0).x, prev, "no gap before slot " + i)
        }
      }
      fakeWorkspaces.focused = []
      mouseClick(buttons[1], 1, buttons[1].height / 2, Qt.LeftButton)
      compare(fakeWorkspaces.focused, [2], "the slot's edge still focuses it")
    }

    // Trial 4: a generic globe for every browser. The app's own icon when its
    // desktop entry resolves one; the design's symbol otherwise.
    function test_titleShowsTheAppIconOrFallsBack() {
      var image = findNamed(titleIsland, "titleAppIcon")
      var symbol = findNamed(titleIsland, "titleSymbol")
      titleIsland.iconStyle = "app"
      windowState.iconSource = ""
      verify(symbol.visible && !image.visible, "nothing resolved: symbol")
      windowState.iconSource = Qt.resolvedUrl("assets/app-icon.png")
      tryVerify(function() { return image.visible && !symbol.visible }, 2000, "resolved: app icon")
      compare(image.width, titleIsland.iconSize)
      windowState.iconSource = Qt.resolvedUrl("assets/missing.png")
      tryVerify(function() { return symbol.visible && !image.visible }, 2000, "broken file: symbol")
      windowState.iconSource = Qt.resolvedUrl("assets/app-icon.png")
      titleIsland.iconStyle = "symbol"
      verify(symbol.visible && !image.visible, "symbol style ignores app icons")
      titleIsland.iconStyle = "app"
      windowState.empty = true
      verify(symbol.visible && !image.visible, "an empty workspace keeps its desktop symbol")
      windowState.empty = false
      windowState.iconSource = ""
    }

    function test_launcherClicksUnchanged() {
      launcherSpy.clear()
      var button = findNamed(launcherIsland, "launcherButton")
      mouseClick(button, button.width / 2, button.height / 2, Qt.LeftButton)
      mouseClick(button, button.width / 2, button.height / 2, Qt.RightButton)
      compare(launcherSpy.count, 2)
      compare(launcherSpy.signalArguments[0][0], Qt.LeftButton)
      compare(launcherSpy.signalArguments[1][0], Qt.RightButton)
    }

    function test_islandGeometryMatchesDesign() {
      compare(island.implicitHeight, 40)
      // 50 + 2 (gap) + 30 content, 4 + 4 padding, 1 + 1 border
      compare(island.implicitWidth, 92)
    }

    function test_buttonSizeAndReach() {
      compare(button.implicitHeight, 32)
      compare(button.implicitWidth, 40)
      // The pointer area reaches toward the screen edge.
      var area = findChild(button, "")
      var pointer = null
      for (var i = 0; i < button.children.length; i++)
        if (button.children[i].hoverEnabled !== undefined) pointer = button.children[i]
      verify(pointer !== null)
      compare(pointer.y, -14)
      compare(pointer.height, 32 + 14 + 5)
    }

    function test_buttonClickAtScreenEdge() {
      var clicks = 0
      var handler = function() { clicks++ }
      button.clicked.connect(handler)
      // 10 px above the button: inside the reach, outside the drawn button.
      mouseClick(button, button.width / 2, -10)
      compare(clicks, 1)
      button.clicked.disconnect(handler)
    }

    function test_workspaceDotStates() {
      dot.active = false
      dot.occupied = false
      var mark = dot.children[0]
      compare(mark.width, 8)
      compare(mark.border.width, 1.5)
      dot.occupied = true
      compare(mark.border.width, 0)
      tryCompare(mark, "color", theme.muted)
      dot.active = true
      tryCompare(mark, "width", 24)
      tryCompare(mark, "color", theme.accent)
    }

    function test_titleElidesWithinItsCap() {
      compare(titleIsland.width, 240)
      verify(titleIsland.visible)
      titleIsland.maximumWidth = 100
      verify(!titleIsland.visible, "below the minimum the title island hides")
      titleIsland.maximumWidth = 2000
      verify(titleIsland.width < 2000)
      compare(titleIsland.width, titleIsland.naturalWidth)
    }

    function test_titleEmptyWorkspace() {
      windowState.empty = true
      compare(titleIsland.text, "Empty workspace")
      windowState.empty = false
    }

    function test_titleIsPlainText() {
      windowState.title = '<b>bold</b><img src="https://example.invalid/t">'
      var label = null
      for (var i = 0; i < titleIsland.children.length; i++) {
        var row = titleIsland.children[i]
        for (var j = 0; row.children && j < row.children.length; j++)
          if (row.children[j].textFormat !== undefined) label = row.children[j]
      }
      verify(label !== null)
      compare(label.textFormat, Text.PlainText)
      compare(label.text, '<b>bold</b><img src="https://example.invalid/t">')
    }
  }
}
