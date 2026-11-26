import QtQuick
import QtTest
import "../../plugin/theme"
import "../../plugin/widgets"
import qs.Commons

// The media island against a stand-in for Omarchy's media service proxy:
// states, the player lifecycle, controls routed back through the service,
// tiers, reduced motion, and two outputs keeping separate expansion.
Item {
  id: scene
  width: 1000
  height: 120

  Theme { id: theme }

  QtObject {
    id: strings
    function t(key) { return key === "media.show" || key === "media.hide" ? key + " %1" : key }
  }

  Component {
    id: playerComponent
    QtObject {
      property string trackTitle: "Slow Tide"
      property string trackArtist: "Hikari Ensemble"
      property bool isPlaying: true
      property bool canGoNext: true
      property bool canGoPrevious: true
      property bool canTogglePlaying: true
      property real position: 30
      property real length: 120
      property int positionRequests: 0
      // Quickshell's MprisPlayer refreshes `position` when positionChanged()
      // is called; here the signal itself is counted.
      onPositionChanged: positionRequests++
    }
  }

  QtObject {
    id: service
    property var activePlayer: null
    property var actions: []
    function runAction(action, feedback, key) { actions = actions.concat([action + ":" + key + ":" + feedback]) }
    function playerKey(player) { return player ? "mpris:test" : "" }
  }

  MediaIsland { id: media; theme: theme; strings: strings; service: service; tier: "full" }
  MediaIsland { id: mirror; y: 60; theme: theme; strings: strings; service: service; tier: "full" }
  MediaIsland { id: orphan; x: 600; theme: theme; strings: strings; service: null }

  TestCase {
    name: "Media"
    when: windowShown

    function init() {
      service.activePlayer = playerComponent.createObject(scene)
      service.actions = []
      media.pinned = false
      mirror.pinned = false
      media.tier = "full"
      media.maximumWidth = -1
      // A test that left the controls out sees them close here; hover tests
      // need the title back where it rests.
      tryCompare(findNamed(media, "mediaControls"), "width", 0)
    }

    function cleanup() {
      var p = service.activePlayer
      service.activePlayer = null
      if (p) p.destroy()
    }

    function test_unavailableAndEmptyStates() {
      compare(orphan.mediaState, "unavailable")
      verify(!orphan.visible)
      service.activePlayer.trackTitle = ""
      service.activePlayer.trackArtist = ""
      compare(media.mediaState, "empty")
      verify(!media.visible)
    }

    function test_playingAndPaused() {
      compare(media.mediaState, "playing")
      verify(media.visible)
      service.activePlayer.isPlaying = false
      compare(media.mediaState, "paused")
      verify(media.visible)
    }

    function test_expandsTowardTheLeftByWidening() {
      var collapsed = media.implicitWidth
      media.pinned = true
      tryVerify(function() { return media.implicitWidth > collapsed + 100 }, 1000)
      compare(media.demandFor("full") >= media.implicitWidth - 1, true, "the layout reserves at least the expanded width")
    }

    function test_controlsGoThroughTheService() {
      media.act("next")
      media.act("playPause")
      compare(service.actions, ["next:mpris:test:false", "playPause:mpris:test:false"])
    }

    function test_playerDisappearingCollapses() {
      media.pinned = true
      var p = service.activePlayer
      service.activePlayer = null
      p.destroy()
      compare(media.mediaState, "empty")
      verify(!media.expanded)
      verify(!media.visible)
    }

    function test_positionIsOnlyPolledWhileExpandedAndPlaying() {
      var p = service.activePlayer
      wait(1200)
      compare(p.positionRequests, 0, "collapsed: no polling")
      media.pinned = true
      tryVerify(function() { return p.positionRequests > 0 }, 2000)
      compare(media.progress, 0.25)
      media.pinned = false
      var count = p.positionRequests
      wait(1200)
      compare(p.positionRequests, count, "collapsed again: polling stopped")
    }

    function findNamed(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var found = findNamed(item.children[i], name)
        if (found) return found
      }
      return null
    }

    // Trial 4: the progress line sat 4 px above the island's bottom border.
    // It is a 3 px line under the title, aligned with it, and the two are
    // centred together with room above and below.
    function test_progressLineSitsUnderTheTitle() {
      var line = findNamed(media, "mediaProgress")
      var title = findNamed(media, "mediaTitle")
      var s = theme.m.scale
      media.pinned = true
      tryVerify(function() { return line.visible && media.progress === 0.25 }, 2000)
      tryCompare(line, "opacity", 1)
      var l = line.mapToItem(media, 0, 0)
      var t = title.mapToItem(media, 0, 0)
      compare(line.height, Math.round(3 * s), "3 px")
      compare(l.x, t.x, "starts with the title")
      verify(l.y >= t.y + title.height + Math.round(3 * s) - 0.5, "below the title")
      verify(l.y + line.height <= media.height - Math.round(7 * s), "clear of the bottom border")
      verify(t.y >= Math.round(7 * s), "clear of the top border")
      compare(findNamed(media, "mediaProgressFill").width, Math.round(line.width * 0.25))
      media.pinned = false
      tryCompare(line, "visible", false)
      var centred = title.mapToItem(media, 0, title.height / 2).y
      verify(Math.abs(centred - media.height / 2) <= 1, "without progress the title is centred again")
    }

    // Three states: closed; a preview while the pointer rests 250 ms; pinned
    // by a click, which leaving does not undo.
    function test_hoverPreviewsAndClickPins() {
      var main = findNamed(media, "mediaMain")
      mouseMove(scene, 890, 110)
      compare(media.expanded, false)
      mouseMove(main, main.width / 2, main.height / 2)
      wait(100)
      verify(!media.expanded, "a passing pointer does not open it")
      tryVerify(function() { return media.expanded && media.previewing && !media.pinned }, 1000, "previews after resting")
      mouseMove(scene, 890, 110)
      tryVerify(function() { return !media.expanded }, 1000, "leaving ends a preview")

      mouseMove(main, main.width / 2, main.height / 2)
      tryVerify(function() { return media.previewing }, 1000)
      mouseClick(main, main.width / 2, main.height / 2)
      verify(media.pinned, "a click during the preview keeps it open")
      mouseMove(scene, 890, 110)
      wait(400)
      verify(media.expanded, "pinned: leaving does not close it")

      mouseMove(main, main.width / 2, main.height / 2)
      mouseClick(main, main.width / 2, main.height / 2)
      verify(!media.expanded, "a second click closes it")
      wait(400)
      verify(!media.expanded, "and it does not preview again under the same pointer")
      mouseMove(scene, 890, 110)
      mouseMove(main, main.width / 2, main.height / 2)
      tryVerify(function() { return media.previewing }, 1000, "until the pointer comes back")
      mouseMove(scene, 890, 110)
    }

    // The width when collapsed; a collapse animates, and the title slides
    // back under a pointer only once it has finished.
    function settleCollapsed() {
      var controls = findNamed(media, "mediaControls")
      tryVerify(function() { return !media.expanded && controls.width === 0 }, 2000)
    }

    // Pinned controls close on a workspace switch (focusKey); leaving never
    // closes them, and a preview is the pointer's.
    function test_workspaceSwitchClosesPinnedControls() {
      var main = findNamed(media, "mediaMain")
      media.focusKey = "1"
      mouseMove(main, main.width / 2, main.height / 2)
      tryVerify(function() { return media.previewing }, 1000)
      mouseClick(main, main.width / 2, main.height / 2)
      verify(media.pinned)
      mouseMove(scene, 890, 110)
      wait(400)
      verify(media.pinned, "leaving does not unpin")

      media.focusKey = "2"
      verify(!media.expanded, "switching workspace closes them")
      settleCollapsed()

      mouseMove(main, main.width / 2, main.height / 2)
      tryVerify(function() { return media.previewing }, 1000, "the pointer was away, so it previews again")
      media.focusKey = "3"
      verify(media.previewing, "a preview stays while the pointer does")
      mouseMove(scene, 890, 110)
      settleCollapsed()
    }

    // No keyboard focus and no Escape: keys always belong to applications.
    function test_pinnedControlsTakeNoKeys() {
      var main = findNamed(media, "mediaMain")
      mouseMove(main, main.width / 2, main.height / 2)
      tryVerify(function() { return media.previewing }, 1000)
      mouseClick(main, main.width / 2, main.height / 2)
      verify(media.pinned)
      verify(!media.activeFocus, "pinning takes no keyboard focus")
      keyClick(Qt.Key_Escape)
      verify(media.pinned, "Escape is not handled")
      mouseClick(main, main.width / 2, main.height / 2)
      verify(!media.expanded, "a second click closes them")
      mouseMove(scene, 890, 110)
      settleCollapsed()
    }

    function test_tiers() {
      var full = media.implicitWidth
      media.tier = "compact"
      // A Row re-lays out on the next frame.
      tryVerify(function() { return media.implicitWidth < full }, 1000)
      verify(media.demandFor("compact") < media.demandFor("full"))
      compare(media.demandFor("minimal"), 0)
      media.tier = "minimal"
      verify(!media.visible)
    }

    function test_outputsExpandIndependently() {
      media.pinned = true
      verify(!mirror.expanded)
      compare(mirror.mediaState, media.mediaState, "both read the same service")
    }

    function test_reducedMotionStopsTheEqualizer() {
      Style.reduceMotion = true
      compare(theme.widget, 0)
      Style.reduceMotion = false
    }

    function test_maximumWidthYieldsMetadataSmoothlyAndRestores() {
      var main = findNamed(media, "mediaMain")
      verify(main !== null)
      media.tier = "full"
      media.maximumWidth = -1
      tryCompare(main, "width", media.fullMainWidth, 1000)
      verify(media.showsTitle)

      // Moderate tray expansion: metadata yields width smoothly without disappearing.
      media.maximumWidth = 325
      verify(media.showsTitle, "metadata stays visible when space allows readable title")
      verify(media.mainWidth < media.fullMainWidth && media.mainWidth >= media.titleMinMainWidth)
      tryCompare(main, "width", media.mainWidth, 1000)

      // Tight space: collapses cleanly to compact equalizer pill.
      media.maximumWidth = 235
      verify(!media.showsTitle, "metadata hides when below titleMinMainWidth")
      compare(media.mainWidth, media.compactMainWidth)
      tryCompare(main, "width", media.compactMainWidth, 1000)

      // Space returns: restores full metadata width smoothly.
      media.maximumWidth = 383
      verify(media.showsTitle)
      compare(media.mainWidth, media.fullMainWidth)
      tryCompare(main, "width", media.fullMainWidth, 1000)

      // Reduced motion snaps width immediately.
      Style.reduceMotion = true
      media.maximumWidth = 235
      compare(main.width, media.compactMainWidth)
      media.maximumWidth = -1
      compare(main.width, media.fullMainWidth)
      Style.reduceMotion = false
    }
  }
}
