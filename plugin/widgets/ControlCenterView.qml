pragma ComponentBehavior: Bound
import QtQuick
import "../components"
import "../theme/Icons.js" as Icons
import "../logic/ControlCenter.js" as Model

// The Control Center: a dashboard of groups (Connectivity, System, Sound &
// Display, More) and a page listing every hosted panel. Both pages share
// one footprint, set by the dashboard's measured height; when the panel
// gives less (a short output, a large font), the page scrolls inside it
// and focus always brings its control into view.
//
// Keyboard (logic/ControlCenter.js navigate): Left/Right inside a group,
// Up/Down by row and on into the next group, Tab/Shift+Tab between groups
// (back where each was left), Space/Enter activate, Escape goes back from
// the panels page and then asks to close. The focus ring appears only once
// the keyboard is used.
FocusScope {
  id: root

  required property var theme
  required property var strings
  // { nightlight, stayAwake, doNotDisturb }: first-party proxies, or null.
  property var services: ({})
  // [{ id, name }] from logic/ControlCenter.js links().
  property var links: []
  // The default output's Pipewire node (adapters/AudioOutput.qml), or null.
  property var audioSink: null
  // The hosted widget whose full panel is audio, or "".
  property string audioPanelId: ""
  // Wi-Fi and Bluetooth providers (adapters/Connectivity.qml), or null.
  property var wifi: null
  property var bluetooth: null
  // Omarchy's Network and Bluetooth panels when hosted, or "".
  property string wifiPanelId: ""
  property string bluetoothPanelId: ""
  // The power profile (adapters/PowerProfileAdapter.qml), or null.
  property var powerProfile: null
  // adapters/BrightnessAdapter.qml for this panel's output, or null.
  property var brightness: null
  property int confirmTimeout: 3000

  signal closeRequested()
  signal panelRequested(string id)

  readonly property real s: theme.m.scale
  readonly property real gap: Math.round(8 * s)
  property bool keyboardShown: false
  // "main" (the dashboard) or "panels".
  property string page: "main"

  // Columns from the width: two wide tiles from 2 x 136 px, three compact
  // tiles from 3 x 88 px, scaled by the theme and by a larger font, so a
  // bigger font drops a column instead of cutting a label.
  readonly property real textGrowth: Math.max(1, theme.fontScale)
  readonly property int connectivityColumns: Model.columns(width, Math.round(136 * s * textGrowth), gap, 2)
  readonly property int systemColumns: Model.columns(width, Math.round(88 * s * textGrowth), gap, 3)
  // Every compact tile as tall as the tallest, so rows line up.
  readonly property real tileHeight: {
    var h = 0
    for (var i = 0; i < tiles.count; i++) {
      var t = tiles.itemAt(i)
      if (t) h = Math.max(h, t.implicitHeight)
    }
    return h
  }

  function focusable(item) {
    return !!item && item.visible !== false && item.enabled !== false && item.activeFocusOnTab !== false
  }

  // The current page as groups of rows of focusable controls, in reading order.
  function pageGroups() {
    if (root.page === "panels") {
      var list = [[backButton]]
      var linkRows = []
      for (var j = 0; j < linkButtons.count; j++) if (root.focusable(linkButtons.itemAt(j))) linkRows.push([linkButtons.itemAt(j)])
      return [list, linkRows]
    }
    var radios = root.connectivityColumns > 1
      ? [wifiTile.controls().concat(bluetoothTile.controls())]
      : [wifiTile.controls(), bluetoothTile.controls()]
    var tileItems = []
    for (var i = 0; i < tiles.count; i++) tileItems.push(tiles.itemAt(i))
    var audioControls = audio.controls()
    var audioRows = [audioControls.filter(function(c) { return c.objectName !== "moreAudio" }),
                     audioControls.filter(function(c) { return c.objectName === "moreAudio" }),
                     brightnessControl.controls()]
    var system = Model.rows(tileItems, root.systemColumns, root.focusable)
    // The profile selector is a group of its own for navigation (one Tab
    // stop; Left/Right stay among its profiles), though it sits under the
    // System heading. Always listed, empty when unavailable, so the group
    // indices the Tab memory uses do not shift.
    var profileRow = profiles.controls()
    return [
      radios.filter(function(r) { return r.length > 0 }),
      system,
      profileRow.length ? [profileRow] : [],
      audioRows.filter(function(r) { return r.length > 0 }),
      root.focusable(moreButton) ? [[moreButton]] : []
    ]
  }

  // Every focusable control of the page, in reading order.
  function controls() {
    var out = []
    var groups = root.pageGroups()
    for (var g = 0; g < groups.length; g++)
      for (var r = 0; r < groups[g].length; r++) out = out.concat(groups[g][r])
    return out
  }

  function shapeOf(groups) {
    return groups.map(function(g) { return g.map(function(r) { return r.length }) })
  }

  function positionOf(groups, item) {
    for (var g = 0; g < groups.length; g++)
      for (var r = 0; r < groups[g].length; r++) {
        var c = groups[g][r].indexOf(item)
        if (c !== -1) return { group: g, row: r, col: c }
      }
    return null
  }

  function focusedControl() {
    var list = root.controls()
    for (var i = 0; i < list.length; i++) if (list[i].activeFocus) return list[i]
    return null
  }

  // Where each group was last left, for Tab; per page.
  property var memory: ({})

  function move(direction) {
    var groups = root.pageGroups()
    var at = root.positionOf(groups, root.focusedControl())
    if (at) root.memory[root.page + at.group] = at
    var mem = {}
    for (var g = 0; g < groups.length; g++) mem[g] = root.memory[root.page + g]
    // The first Tab into the profile selector lands on the selected
    // profile; later ones return where focus was left, as in every group.
    var lit = root.page === "main" ? root.positionOf(groups, profiles.selectedControl()) : null
    if (lit && !mem[lit.group]) mem[lit.group] = lit
    var next = Model.navigate(root.shapeOf(groups), at, direction, mem)
    if (!next) { root.forceActiveFocus(); return }
    root.focusControl(groups[next.group][next.row][next.col])
  }

  function focusControl(item) {
    if (!item) return
    item.forceActiveFocus()
    root.reveal(item)
  }

  // The dashboard group holding `item`, or null.
  function groupOf(item) {
    for (var p = item; p; p = p.parent) if (String(p.objectName).indexOf("group") === 0) return p
    return null
  }

  // Scrolls the page so `item` is fully visible, with its group's heading
  // too when the whole group fits.
  function reveal(item) {
    if (!item || flick.height <= 0) return
    var group = root.groupOf(item)
    var target = group && group.height <= flick.height ? group : item
    var p = target.mapToItem(flick.contentItem, 0, 0)
    var margin = target === group ? 0 : Math.round(4 * root.s)
    var y = flick.contentY
    if (p.y - margin < y) y = p.y - margin
    else if (p.y + target.height + margin > y + flick.height) y = p.y + target.height + margin - flick.height
    flick.contentY = Math.max(0, Math.min(y, Math.max(0, flick.contentHeight - flick.height)))
  }

  function first() {
    var list = root.controls()
    if (list.length > 0) root.focusControl(list[0])
    else root.forceActiveFocus()
  }

  function showPanels() {
    root.page = "panels"
    flick.contentY = 0
    root.first()
  }

  function showMain() {
    root.page = "main"
    flick.contentY = 0
    root.focusControl(moreButton)
  }

  // Back to the dashboard and its first control, mouse mode, each time the
  // panel opens (the content is kept between opens).
  function reset() {
    root.keyboardShown = false
    root.page = "main"
    root.memory = {}
    flick.contentY = 0
    // Re-read what the services cannot say (rfkill) or a notification
    // might have missed (brightness), once per open.
    for (var provider of [root.wifi, root.bluetooth, root.powerProfile, root.brightness])
      if (provider && typeof provider.refresh === "function") provider.refresh()
    root.first()
  }

  implicitWidth: Math.round(316 * s)
  // One footprint for both pages: the header and the dashboard as measured.
  // It depends on the width, the font and the strings, not on any state
  // shown or on the number of hosted panels.
  implicitHeight: Math.ceil(header.height + root.gap + dashboard.implicitHeight)
  // The page's content height, for the tests.
  readonly property real contentHeight: header.height + root.gap + flick.contentHeight
  focus: true

  Keys.onPressed: function(event) {
    var mirrored = LayoutMirroring.enabled
    if (event.key === Qt.Key_Escape) {
      if (root.page !== "main") root.showMain()
      else root.closeRequested()
      event.accepted = true
      return
    }
    var direction = ""
    if (event.key === Qt.Key_Left) direction = mirrored ? "right" : "left"
    else if (event.key === Qt.Key_Right) direction = mirrored ? "left" : "right"
    else if (event.key === Qt.Key_Up) direction = "up"
    else if (event.key === Qt.Key_Down) direction = "down"
    if (direction === "") return
    root.keyboardShown = true
    root.move(direction)
    event.accepted = true
  }

  // Tab and Shift+Tab move between groups. A focused control with
  // activeFocusOnTab takes Tab for Qt's own focus chain before any key
  // handler here sees it, so groups are reached through shortcuts, enabled
  // only while focus is inside this view.
  Shortcut {
    sequences: ["Tab"]
    enabled: root.activeFocus
    onActivated: { root.keyboardShown = true; root.move("tab") }
  }
  // A physical Shift+Tab can match both sequences at once (the keymap
  // gives Backtab and Shift+Tab), and Qt then reports the shortcut as
  // ambiguous instead of activated. Both are this shortcut, so both act.
  Shortcut {
    objectName: "backtabShortcut"
    sequences: ["Backtab", "Shift+Tab"]
    enabled: root.activeFocus
    onActivated: { root.keyboardShown = true; root.move("backtab") }
    onActivatedAmbiguously: { root.keyboardShown = true; root.move("backtab") }
  }

  // ------------------------------------------------------------- header

  Item {
    id: header

    width: root.width
    // The same on every page, so the footprint does not change with Back.
    height: Math.max(title.implicitHeight, backButton.implicitHeight)

    IslandButton {
      id: backButton

      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      visible: root.page !== "main"
      theme: root.theme
      minimumWidth: Math.round(28 * root.s)
      horizontalPadding: 0
      implicitHeight: Math.round(28 * root.s)
      active: activeFocus && root.keyboardShown
      activeFocusOnTab: true
      accessibleName: root.strings.t("controlCenter.back")
      onClicked: function(button) { if (button === Qt.LeftButton) root.showMain() }
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.showMain()
          event.accepted = true
        }
      }

      StrokeIcon {
        icon: Icons.chevron
        size: Math.round(16 * root.s)
        color: root.theme.foreground
        rotation: LayoutMirroring.enabled ? 0 : 180
      }
    }

    Text {
      id: title

      anchors.left: backButton.visible ? backButton.right : parent.left
      anchors.leftMargin: backButton.visible ? Math.round(6 * root.s) : 0
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: root.strings.t(root.page === "main" ? "controlCenter" : "controlCenter.panels")
      color: root.theme.foreground
      font.family: root.theme.textFamily
      font.pixelSize: Math.round(15 * root.theme.fontScale)
      font.weight: Font.DemiBold
      Accessible.role: Accessible.Heading
    }
  }

  // -------------------------------------------------------------- pages

  Flickable {
    id: flick

    objectName: "pageScroll"
    anchors.top: header.bottom
    anchors.topMargin: root.gap
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: root.page === "main" ? dashboard.implicitHeight : panelsPage.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: dashboard

      objectName: "dashboard"
      visible: root.page === "main"
      width: flick.width
      spacing: Math.round(14 * root.s)

      ControlCenterGroup {
        objectName: "groupConnectivity"
        width: parent.width
        theme: root.theme
        title: root.strings.t("controlCenter.group.connectivity")

        Grid {
          columns: root.connectivityColumns
          spacing: root.gap

          ControlCenterRadio {
            id: wifiTile

            width: (root.width - (root.connectivityColumns - 1) * root.gap) / root.connectivityColumns
            theme: root.theme
            strings: root.strings
            kind: "wifi"
            provider: root.wifi
            panelId: root.wifiPanelId
            keyboardShown: root.keyboardShown
            onPanelRequested: function(id) { root.panelRequested(id) }
          }

          ControlCenterRadio {
            id: bluetoothTile

            width: (root.width - (root.connectivityColumns - 1) * root.gap) / root.connectivityColumns
            theme: root.theme
            strings: root.strings
            kind: "bluetooth"
            provider: root.bluetooth
            panelId: root.bluetoothPanelId
            keyboardShown: root.keyboardShown
            onPanelRequested: function(id) { root.panelRequested(id) }
          }
        }
      }

      ControlCenterGroup {
        objectName: "groupSystem"
        width: parent.width
        theme: root.theme
        title: root.strings.t("controlCenter.group.system")

        Grid {
          columns: root.systemColumns
          spacing: root.gap

          Repeater {
            id: tiles

            model: Model.TILES

            ControlCenterTile {
              required property var modelData

              theme: root.theme
              strings: root.strings
              key: modelData.key
              proxy: root.services[modelData.key] || null
              confirmTimeout: root.confirmTimeout
              keyboardShown: root.keyboardShown
              width: (root.width - (root.systemColumns - 1) * root.gap) / root.systemColumns
              height: Math.max(implicitHeight, root.tileHeight)
            }
          }
        }

        ControlCenterProfiles {
          id: profiles

          objectName: "profilesControl"

          width: parent.width
          theme: root.theme
          strings: root.strings
          provider: root.powerProfile
          keyboardShown: root.keyboardShown
        }
      }

      ControlCenterGroup {
        objectName: "groupSound"
        width: parent.width
        theme: root.theme
        title: root.strings.t("controlCenter.group.sound")

        ControlCenterAudio {
          id: audio

          width: parent.width
          theme: root.theme
          strings: root.strings
          sink: root.audioSink
          hasPanel: root.audioPanelId !== ""
          confirmTimeout: root.confirmTimeout
          keyboardShown: root.keyboardShown
          onPanelRequested: root.panelRequested(root.audioPanelId)
        }

        // Below the audio rows (docs/CONTROL_CENTER_LAYOUT.md): the same
        // group, so Up/Down move between them and Tab treats them as one.
        ControlCenterBrightness {
          id: brightnessControl

          objectName: "brightnessControl"
          width: parent.width
          theme: root.theme
          strings: root.strings
          provider: root.brightness
          keyboardShown: root.keyboardShown
        }
      }

      ControlCenterGroup {
        objectName: "groupMore"
        width: parent.width
        theme: root.theme
        title: root.strings.t("controlCenter.group.more")

        IslandButton {
          id: moreButton

          objectName: "morePanels"
          width: parent.width
          theme: root.theme
          implicitHeight: Math.round(32 * root.s)
          active: activeFocus && root.keyboardShown
          activeFocusOnTab: true
          accessibleName: root.strings.t("controlCenter.allPanels")
          onClicked: function(button) { if (button === Qt.LeftButton) root.showPanels() }
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.showPanels()
              event.accepted = true
            }
          }

          Text {
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            width: moreButton.width - 2 * moreButton.horizontalPadding - Math.round(16 * root.s) - moreButton.contentSpacing
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: root.strings.t("controlCenter.allPanels")
            color: root.theme.foreground
            font.family: root.theme.textFamily
            font.pixelSize: Math.round(12 * root.theme.fontScale)
          }

          StrokeIcon {
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            icon: Icons.chevron
            size: Math.round(16 * root.s)
            color: root.theme.foreground
          }
        }
      }
    }

    Column {
      id: panelsPage

      objectName: "panelsPage"
      visible: root.page === "panels"
      width: flick.width
      spacing: Math.round(4 * root.s)

      Text {
        objectName: "noPanels"
        visible: root.links.length === 0
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: root.strings.t("controlCenter.noPanels")
        color: root.theme.secondaryText
        font.family: root.theme.textFamily
        font.pixelSize: Math.round(12 * root.theme.fontScale)
      }

      Repeater {
        id: linkButtons

        model: root.links

        IslandButton {
          id: link

          required property var modelData

          width: panelsPage.width
          theme: root.theme
          implicitHeight: Math.round(32 * root.s)
          active: activeFocus && root.keyboardShown
          activeFocusOnTab: true
          accessibleName: root.strings.t("controlCenter.openPanel").arg(modelData.name)
          onClicked: function(button) { if (button === Qt.LeftButton) root.panelRequested(link.modelData.id) }
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.panelRequested(link.modelData.id)
              event.accepted = true
            }
          }

          Text {
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            width: link.width - 2 * link.horizontalPadding
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: link.modelData.name
            color: root.theme.foreground
            font.family: root.theme.textFamily
            font.pixelSize: Math.round(12 * root.theme.fontScale)
          }
        }
      }
    }
  }

  // The scroll position, shown only while the page is taller than the view.
  Rectangle {
    objectName: "scrollIndicator"
    visible: flick.contentHeight > flick.height + 0.5
    anchors.right: parent.right
    y: flick.y + (flick.height - height) * (flick.contentHeight > flick.height ? flick.contentY / (flick.contentHeight - flick.height) : 0)
    width: Math.max(2, Math.round(3 * root.s))
    height: Math.max(Math.round(24 * root.s), flick.height * flick.height / Math.max(1, flick.contentHeight))
    radius: width / 2
    color: root.theme.muted
    opacity: 0.6
  }
}
