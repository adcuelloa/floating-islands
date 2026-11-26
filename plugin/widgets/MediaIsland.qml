pragma ComponentBehavior: Bound
import QtQuick
import "../components"
import "../logic/Media.js" as Media
import "../theme/Icons.js" as Icons

// The V2 media island: a small equaliser and "Track · Artist". Clicking it
// slides out previous / play-pause / next toward the clock, with a 3 px
// progress line under the title. No seeking: Omarchy's media service exposes
// no seek action, and controls go only through it. The player comes from Omarchy's media service (its
// choice of the active MPRIS player); controls go back through that
// service, so this island owns no player and selects none.
//
// The island sits in the right-hand group, which is anchored to the screen
// edge, so expanding grows it leftward and nothing else moves. The layout
// reserves its expanded width (demandFor), so expanding never pushes into
// the clock.
Island {
  id: root

  // Omarchy's media service proxy (firstPartyServiceFor("omarchy.media")), or null.
  property var service: null
  required property var strings
  property string tier: "full"
  property string equalizer: "animated"
  // Maximum width available beside the hosted island (< 0 = unconstrained).
  property real maximumWidth: -1
  property var reach: ({ top: 0, bottom: 0 })

  readonly property var player: service ? service.activePlayer : null
  readonly property string mediaState: Media.state(service, player)
  readonly property var track: Media.describe(player)
  readonly property bool hasMedia: mediaState === "playing" || mediaState === "paused"
  readonly property bool playing: mediaState === "playing"
  readonly property real s: theme.m.scale
  readonly property real chromeWidth: paddingLeft + paddingRight + spacing + 2 * borderWidth
  readonly property real fullMainWidth: Math.round(224 * s)
  readonly property real compactMainWidth: Math.round(48 * s)
  readonly property real titleMinMainWidth: Math.round(112 * s)
  readonly property real controlsWidth: Math.round(132 * s)
  readonly property real mainWidth: {
    if (tier !== "full") return compactMainWidth
    if (maximumWidth < 0) return fullMainWidth
    var budget = Math.floor(maximumWidth - controlsWidth - chromeWidth)
    return budget >= titleMinMainWidth ? Math.min(fullMainWidth, budget) : compactMainWidth
  }
  readonly property bool showsTitle: tier === "full" && mainWidth >= titleMinMainWidth

  // Three states: closed; previewing while the pointer rests on the island
  // (after previewDelay), which leaving ends; pinned by a click, which a second
  // click, a workspace switch (focusKey), or the player going away ends.
  // Leaving never ends a pin, nor does focusing another window: with
  // focus-follows-mouse that is only the pointer passing over it.
  //
  // The island never takes keyboard focus and sets no focus grab, so it never
  // swallows a click or a keystroke meant for an application. Hence no Escape,
  // and a click outside that focuses nothing new (the wallpaper, another
  // bar island) leaves it pinned.
  property bool pinned: false
  property bool previewing: false
  readonly property bool expanded: pinned || previewing
  readonly property int previewDelay: 250
  // Set when a click closes the island under the pointer, so it does not
  // preview again until the pointer has left.
  property bool previewSuppressed: false

  // A click pins a preview (the pointer is already there to use it) and
  // closes a pinned island.
  function togglePinned() {
    if (root.pinned) root.dismiss()
    else root.pinned = true
  }

  // Closes the controls. Under the pointer they do not preview again until the
  // pointer has left.
  function dismiss() {
    if (!root.expanded) return
    root.pinned = false
    root.previewing = false
    root.previewSuppressed = hover.hovered
  }

  // Identifies the focused workspace; the surface sets it from Hyprland. Any
  // change closes pinned controls.
  property string focusKey: ""
  onFocusKeyChanged: if (root.pinned) root.dismiss()

  property real progress: -1

  // The island's width when expanded in a tier, for the layout to reserve.
  function demandFor(forTier) {
    if (forTier === "minimal") return 0
    var main = Math.round((forTier === "full" ? 224 : 48) * s)
    return main + controlsWidth + paddingLeft + paddingRight + spacing + 2 * borderWidth
  }

  function act(action) {
    if (root.service && typeof root.service.runAction === "function")
      root.service.runAction(action, false, root.service.playerKey(root.player))
  }

  visible: hasMedia && tier !== "minimal"
  onHasMediaChanged: if (!hasMedia) { root.pinned = false; root.previewing = false }

  HoverHandler {
    id: hover

    onHoveredChanged: {
      if (hovered) {
        if (!root.previewSuppressed) previewTimer.restart()
      } else {
        previewTimer.stop()
        root.previewing = false
        root.previewSuppressed = false
      }
    }
  }

  Timer {
    id: previewTimer
    interval: root.previewDelay
    onTriggered: if (hover.hovered && root.hasMedia && !root.pinned) root.previewing = true
  }
  onPlayerChanged: root.progress = Media.progress(root.player)

  spacing: 0
  Accessible.role: Accessible.Grouping
  Accessible.name: root.strings.t("media")

  // Position is reported only on request, so it is read once a second, and
  // only while the controls are out and something is playing.
  Timer {
    interval: 1000
    repeat: true
    triggeredOnStart: true
    running: root.expanded && root.playing && root.visible
    onTriggered: {
      if (root.player && typeof root.player.positionChanged === "function") root.player.positionChanged()
      root.progress = Media.progress(root.player)
    }
  }

  // The controls, revealed by widening this clip toward the clock.
  Item {
    id: controlsClip
    objectName: "mediaControls"

    width: root.expanded ? root.controlsWidth : 0
    height: controls.implicitHeight
    anchors.verticalCenter: parent.verticalCenter
    clip: true

    Behavior on width {
      NumberAnimation { duration: root.theme.widget; easing.type: Easing.Bezier; easing.bezierCurve: root.theme.easeOut }
    }

    Row {
      id: controls

      anchors.right: parent.right
      rightPadding: Math.round(4 * root.s)
      spacing: root.theme.m.itemGap
      opacity: root.expanded ? 1 : 0

      Behavior on opacity { NumberAnimation { duration: root.expanded ? root.theme.widget : root.theme.fast } }

      component Control: IslandButton {
        id: control

        required property var glyph
        property bool emphasised: false

        theme: root.theme
        minimumWidth: Math.round(40 * root.s)
        horizontalPadding: Math.round(8 * root.s)
        reachTop: root.reach.top
        reachBottom: root.reach.bottom
        restColor: emphasised ? root.theme.accentSoft : "transparent"

        StrokeIcon {
          icon: control.glyph
          size: Math.round(16 * root.s)
          color: control.emphasised ? root.theme.accent : root.theme.foreground
        }
      }

      Control {
        glyph: Icons.previous
        enabled: root.track.canPrevious
        opacity: enabled ? 1 : 0.4
        accessibleName: root.strings.t("media.previous")
        onClicked: root.act("previous")
      }

      Control {
        glyph: root.playing ? Icons.pause : Icons.play
        emphasised: true
        enabled: root.track.canPlayPause
        accessibleName: root.strings.t(root.playing ? "media.pause" : "media.play")
        onClicked: root.act("playPause")
      }

      Control {
        glyph: Icons.next
        enabled: root.track.canNext
        opacity: enabled ? 1 : 0.4
        accessibleName: root.strings.t("media.next")
        onClicked: root.act("next")
      }
    }
  }

  IslandButton {
    id: mainButton

    objectName: "mediaMain"
    theme: root.theme
    minimumWidth: root.compactMainWidth
    width: root.mainWidth
    horizontalPadding: Math.round(10 * root.s)

    Behavior on width {
      enabled: root.theme.widget > 0
      NumberAnimation { duration: root.theme.widget; easing.type: Easing.Bezier; easing.bezierCurve: root.theme.easeOut }
    }
    contentSpacing: Math.round(10 * root.s)
    reachTop: root.reach.top
    reachBottom: root.reach.bottom
    accessibleName: root.strings.t(root.expanded ? "media.hide" : "media.show").arg(root.track.title)
    onClicked: function(button) {
      if (button === Qt.LeftButton) root.togglePinned()
      else if (button === Qt.MiddleButton) root.act("playPause")
    }
    onWheelMoved: function(delta) { if (delta !== 0) root.act(delta > 0 ? "previous" : "next") }

    // Four bars, 3 px wide, rising and falling while something plays.
    Row {
      id: equalizerBars

      readonly property bool moving: root.playing && root.equalizer === "animated" && root.theme.widget > 0

      anchors.verticalCenter: parent.verticalCenter
      height: Math.round(14 * root.s)
      spacing: Math.round(2 * root.s)

      Repeater {
        model: [0, 300, 600, 150]

        Item {
          id: barSlot

          required property int modelData

          width: Math.max(2, Math.round(3 * root.s))
          height: equalizerBars.height

          // 0..1, animated; the height follows it, so stopping the
          // animation never leaves a stale height behind.
          property real level: 0

          SequentialAnimation on level {
            running: equalizerBars.moving
            loops: Animation.Infinite
            PauseAnimation { duration: barSlot.modelData }
            SequentialAnimation {
              loops: Animation.Infinite
              NumberAnimation { from: 0; to: 1; duration: 450; easing.type: Easing.InOutSine }
              NumberAnimation { from: 1; to: 0; duration: 450; easing.type: Easing.InOutSine }
            }
          }

          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            radius: 1
            color: root.theme.accent
            height: equalizerBars.moving
              ? Math.round((4 + 10 * barSlot.level) * root.s)
              : Math.round((root.playing ? 6 : 4) * root.s)
          }
        }
      }
    }

    // The title, and while the controls are out a 3 px progress line under it,
    // centred together so the line keeps clear of the island's border.
    Item {
      id: metadata

      readonly property bool progressShown: root.expanded && root.progress >= 0
      readonly property real lineGap: Math.round(4 * root.s)

      anchors.verticalCenter: parent.verticalCenter
      opacity: root.showsTitle ? 1 : 0
      visible: opacity > 0 && width > 0
      width: Math.max(0, mainButton.width - 2 * mainButton.horizontalPadding - equalizerBars.width - mainButton.contentSpacing)
      height: titleRow.height + (progressShown ? lineGap + progressLine.height : 0)

      Behavior on opacity { enabled: root.theme.fast > 0; NumberAnimation { duration: root.theme.fast } }
      Behavior on height { NumberAnimation { duration: root.theme.widget; easing.type: Easing.OutCubic } }

      Row {
        id: titleRow

        objectName: "mediaTitle"
        width: parent.width
        clip: true

        Text {
          id: titleText

          width: Math.min(implicitWidth, parent.width)
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: root.track.title
          color: root.theme.foreground
          font.family: root.theme.textFamily
          font.pixelSize: root.theme.textSize
        }

        Text {
          objectName: "mediaArtist"
          width: Math.max(0, parent.width - titleText.width)
          visible: root.track.artist !== "" && width > 0
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: " · " + root.track.artist
          color: root.theme.islandSecondaryText
          font.family: root.theme.textFamily
          font.pixelSize: root.theme.textSize
        }
      }

      Rectangle {
        id: progressLine

        objectName: "mediaProgress"
        anchors.bottom: parent.bottom
        width: parent.width
        height: Math.round(3 * root.s)
        radius: height / 2
        color: root.theme.track
        opacity: metadata.progressShown ? 1 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: root.theme.widget } }

        Rectangle {
          objectName: "mediaProgressFill"
          width: Math.round(parent.width * Math.max(0, root.progress))
          height: parent.height
          radius: parent.radius
          color: root.theme.accent
        }
      }
    }
  }
}
