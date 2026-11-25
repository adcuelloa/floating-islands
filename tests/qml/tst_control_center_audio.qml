import QtQuick
import QtTest
import Quickshell.Services.Pipewire
import "../../plugin/theme"
import "../../plugin/adapters"
import "../../plugin/widgets"

// The Control Center's output controls against fake Pipewire nodes shaped
// like Quickshell's PwNode (ready, description, audio.volume, audio.muted),
// and the adapter that follows Pipewire's default sink (stubbed).
Item {
  id: scene
  width: 800
  height: 600

  Theme { id: testTheme }

  QtObject {
    id: testStrings
    // controlCenter.openPanel is formatted with .arg(); keep its %1 as en.json does.
    function t(key) { return key === "controlCenter.openPanel" ? "Open %1" : key }
  }

  // A node that applies a change at once, as Pipewire reports it.
  component FakeSink: QtObject {
    property bool ready: true
    property string description: ""
    property QtObject audio: QtObject {
      property real volume: 0.5
      property bool muted: false
    }
  }

  FakeSink { id: speakers; description: "Speakers" }
  FakeSink { id: headset; description: "Headset" }

  ControlCenterAudio {
    id: audio
    width: 316
    theme: testTheme
    strings: testStrings
    confirmTimeout: 150
    sink: speakers
  }

  SignalSpy { id: panelSpy; target: view; signalName: "panelRequested" }

  ControlCenterView {
    id: view
    y: 120
    width: 316
    theme: testTheme
    strings: testStrings
    audioSink: speakers
    links: [{ id: "a", name: "A" }, { id: "b", name: "B" }, { id: "c", name: "C" }, { id: "d", name: "D" }, { id: "e", name: "E" }, { id: "f", name: "F" }]
  }

  AudioOutput { id: output }

  TestCase {
    name: "ControlCenterAudio"
    when: windowShown

    function find(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var found = find(item.children[i], name)
        if (found) return found
      }
      return null
    }
    function slider() {
      var list = audio.controls()
      for (var i = 0; i < list.length; i++) if (list[i].Accessible.role === Accessible.Slider) return list[i]
      return null
    }

    function init() {
      speakers.ready = true
      speakers.audio.volume = 0.5
      speakers.audio.muted = false
      headset.audio.volume = 0.2
      headset.audio.muted = false
      audio.sink = speakers
      audio.failed = false
      Pipewire.defaultAudioSink = null
      output.active = false
      view.audioPanelId = ""
      panelSpy.clear()
    }

    function test_showsTheNodesState() {
      compare(audio.statusText, "50 %")
      compare(find(audio, "audioDevice").text, "Speakers")
      speakers.audio.volume = 0.3
      compare(audio.statusText, "30 %", "a change made elsewhere shows at once")
      speakers.audio.muted = true
      compare(audio.statusText, "controlCenter.muted")
      compare(audio.controls()[0].Accessible.checked, true)
    }

    function test_volumeKeysAndBounds() {
      slider().forceActiveFocus()
      keyClick(Qt.Key_Right)
      compare(speakers.audio.volume, 0.55)
      keyClick(Qt.Key_Left)
      keyClick(Qt.Key_Left)
      compare(speakers.audio.volume, 0.45)
      keyClick(Qt.Key_End)
      compare(speakers.audio.volume, 1)
      keyClick(Qt.Key_Right)
      compare(speakers.audio.volume, 1, "never past 100 % from here")
      keyClick(Qt.Key_Home)
      compare(speakers.audio.volume, 0)
      keyClick(Qt.Key_Left)
      compare(speakers.audio.volume, 0)
      audio.setVolume(-3)
      compare(speakers.audio.volume, 0)
    }

    function test_pointerSetsVolume() {
      var s = slider()
      mouseClick(s, s.width * 0.25, s.height / 2)
      fuzzyCompare(speakers.audio.volume, 0.25, 0.02)
    }

    // A level above 100 % set elsewhere is shown as it is; the slider sits at its end.
    function test_louderThanTheSlider() {
      speakers.audio.volume = 1.2
      compare(audio.statusText, "120 %")
      compare(slider().shown, 1)
    }

    function test_muteToggles() {
      var mute = audio.controls()[0]
      mouseClick(mute)
      verify(speakers.audio.muted)
      compare(audio.statusText, "controlCenter.muted")
      mute.forceActiveFocus()
      keyClick(Qt.Key_Space)
      verify(!speakers.audio.muted)
    }

    // A node that takes the request but never reports it (a plain object, so
    // nothing notifies): the section reads pending, then failed, and the
    // state shown stays the node's.
    function test_unansweredChangeReadsFailed() {
      var stuck = { ready: true, description: "Stuck", audio: { volume: 0.5, muted: false } }
      audio.sink = stuck
      audio.setVolume(0.8)
      verify(audio.pending)
      compare(slider().value, 0.8, "the slider follows the hand while waiting")
      tryCompare(audio, "failed", true, 1000)
      verify(!audio.pending)
      compare(audio.statusText, "controlCenter.failed")
      compare(slider().value, 0.5, "back to the reported level")
      audio.toggleMute()
      verify(audio.pending)
      audio.toggleMute()
      tryCompare(audio, "failed", true, 1000)
    }

    // The default device changes: the controls move to the new node at once
    // and nothing asked of the old one is kept.
    function test_followsTheDefaultDevice() {
      var stuck = { ready: true, description: "Old", audio: { volume: 0.5, muted: false } }
      audio.sink = stuck
      audio.setVolume(0.9)
      verify(audio.pending)
      audio.sink = headset
      verify(!audio.pending, "the old request is dropped")
      verify(!audio.failed)
      compare(find(audio, "audioDevice").text, "Headset")
      compare(audio.statusText, "20 %")
      audio.setVolume(0.4)
      compare(headset.audio.volume, 0.4)
      compare(stuck.audio.volume, 0.9, "the old node got only its own request")
    }

    // Mute state and keyboard focus have their own marks: the fill is the
    // state, the ring the focus (live review: focus was invisible while
    // muted, because both used the fill).
    function test_muteFocusAndStateAreIndependent() {
      var mute = audio.controls()[0]
      var ring = find(mute, "focusRing")
      verify(ring !== null)
      audio.keyboardShown = true
      for (var muted of [false, true]) {
        speakers.audio.muted = muted
        mute.focus = false
        audio.forceActiveFocus()
        verify(!mute.activeFocus)
        compare(ring.visible, false, "unfocused, muted=" + muted)
        compare(mute.active, muted, "the fill follows the state, unfocused")
        mute.forceActiveFocus()
        compare(ring.visible, true, "focused, muted=" + muted)
        compare(mute.active, muted, "focus does not change the fill")
        compare(mute.Accessible.checked, muted)
        compare(mute.Accessible.name, "controlCenter.mute")
      }
      audio.keyboardShown = false
      compare(ring.visible, false, "no ring until the keyboard is used")
      speakers.audio.muted = false
    }

    function test_sliderFocusHalo() {
      var s = slider()
      var halo = find(s, "sliderFocusRing")
      var handle = find(s, "sliderHandle")
      audio.keyboardShown = true
      s.forceActiveFocus()
      verify(halo.visible)
      verify(halo.width > handle.width, "around the handle, not on it")
      verify(halo.height <= s.height, "inside the slider's own height")
      audio.forceActiveFocus()
      verify(!halo.visible)
      audio.keyboardShown = false
    }

    function test_noDevice() {
      audio.sink = null
      compare(audio.statusText, "controlCenter.noOutput")
      compare(audio.controls().length, 0, "nothing to reach by keyboard")
      audio.setVolume(0.7)
      audio.toggleMute()
      verify(!audio.pending)
      audio.sink = speakers
      speakers.ready = false
      compare(audio.statusText, "controlCenter.noOutput", "a node not yet bound is unavailable")
      speakers.ready = true
      compare(audio.statusText, "50 %")
    }

    function test_adapterFollowsPipewire() {
      compare(output.sink, null)
      Pipewire.defaultAudioSink = speakers
      compare(output.sink, null, "nothing tracked while inactive")
      output.active = true
      compare(output.sink, speakers)
      Pipewire.defaultAudioSink = headset
      compare(output.sink, headset, "a new default device is followed")
      Pipewire.defaultAudioSink = null
      compare(output.sink, null)
    }

    function test_viewLinksToTheAudioPanel() {
      var more = null
      function walk(item) {
        if (item.accessibleName === "controlCenter.moreAudio" && item.visible) more = more || item
        for (var i = 0; i < item.children.length; i++) walk(item.children[i])
      }
      walk(view)
      compare(more, null, "no audio panel hosted: no link")
      view.audioPanelId = "user.audio"
      walk(view)
      verify(more !== null)
      mouseClick(more)
      compare(panelSpy.count, 1)
      compare(panelSpy.signalArguments[0][0], "user.audio")
    }

    function test_viewKeepsItsHeight() {
      verify(view.contentHeight <= view.implicitHeight, view.contentHeight + " > " + view.implicitHeight)
      var height = view.implicitHeight
      view.audioSink = null
      compare(view.implicitHeight, height)
      view.audioSink = speakers
    }
  }
}
