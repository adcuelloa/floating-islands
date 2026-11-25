pragma ComponentBehavior: Bound
import QtQuick
import "../logic/ControlCenter.js" as Model

// The power profile: one segment per profile the daemon offers, the active
// one lit. It shows only the observed profile. A press asks Omarchy for the
// other profile on the current power source and reads "pending" until both
// the command has exited and the profile is observed
// (logic/ControlCenter.js profileOutcome). Then:
//   - *unsaved* when the profile is active but the helper failed, so
//     Omarchy may not remember it for this power source;
//   - *failed* when the profile never became active;
//   - *superseded* when the power source changed meanwhile (Omarchy then
//     applies that source's profile, which is what is shown).
// Further presses are ignored while a request is pending. Arrow keys only
// move focus (the view's navigation); Space/Enter select.
Column {
  id: root

  required property var theme
  required property var strings
  // adapters/PowerProfileAdapter.qml, or an object shaped like it; null reads as
  // unavailable.
  property var provider: null
  property int confirmTimeout: 25000
  property int settleGrace: 3000
  property bool keyboardShown: false

  readonly property real s: theme.m.scale
  readonly property bool available: !!provider && provider.available === true && provider.profiles.length > 0
  readonly property string current: available ? String(provider.current || "") : ""
  readonly property string source: provider && provider.onBattery ? "battery" : "ac"

  // { target, source, exited, code } while a request is pending, else null.
  property var request: null
  // "", "failed", "unsaved" or "superseded": how the last request ended.
  property string outcome: ""
  property bool graceOver: false

  readonly property string statusKey: !available ? "unavailable"
    : (request !== null ? "switching"
    : (outcome === "failed" ? "failed"
    : (outcome === "unsaved" ? "profileUnsaved"
    : (outcome === "superseded" ? "profileSuperseded"
    : (provider.degraded ? "profileDegraded" : "")))))
  readonly property string statusText: statusKey ? strings.t("controlCenter." + statusKey) : ""

  // The focusable segments, in order, for the view's arrow keys.
  function controls() {
    var out = []
    for (var i = 0; i < segments.count; i++) {
      var item = segments.itemAt(i)
      if (item && item.enabled) out.push(item)
    }
    return out
  }

  // The focusable segment of the active profile, or null.
  function selectedControl() {
    var list = root.controls()
    for (var i = 0; i < list.length; i++) if (list[i].lit) return list[i]
    return null
  }

  function select(profile) {
    if (!root.available || root.request !== null || profile === root.current) return
    var life = root.life
    var asked = root.provider.request(profile, function(code) {
      if (!life.alive || root.request === null) return
      root.request = { target: root.request.target, source: root.request.source, exited: true, code: code }
      root.graceOver = false
      grace.restart()
      root.evaluate(false)
    })
    root.outcome = ""
    if (!asked) { root.outcome = "failed"; return }
    root.request = { target: profile, source: asked, exited: false, code: null }
    root.graceOver = false
    confirm.restart()
  }

  function evaluate(timedOut) {
    if (root.request === null) return
    var result = Model.profileOutcome(root.request, root.current, root.source, root.graceOver, timedOut)
    if (result === "pending") return
    root.request = null
    confirm.stop()
    grace.stop()
    root.outcome = result === "done" ? "" : result
  }

  readonly property var life: ({ alive: true })
  Component.onDestruction: root.life.alive = false

  onCurrentChanged: {
    if (root.request !== null) root.evaluate(false)
    else if (root.outcome === "failed" || root.outcome === "superseded") root.outcome = ""
  }
  onSourceChanged: root.evaluate(false)
  // The daemon went away: nothing asked of it applies any more.
  onAvailableChanged: if (!root.available) { root.request = null; root.outcome = ""; confirm.stop(); grace.stop() }

  Timer {
    id: confirm
    interval: root.confirmTimeout
    onTriggered: root.evaluate(true)
  }
  Timer {
    id: grace
    interval: root.settleGrace
    onTriggered: { root.graceOver = true; root.evaluate(false) }
  }

  spacing: Math.round(6 * s)

  Item {
    width: parent.width
    height: Math.max(label.implicitHeight, status.height)

    Text {
      id: label
      anchors.left: parent.left
      anchors.right: status.left
      anchors.rightMargin: Math.round(8 * root.s)
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: root.strings.t("controlCenter.powerProfile")
      color: root.theme.foreground
      font.family: root.theme.textFamily
      font.pixelSize: Math.round(12 * root.theme.fontScale)
    }

    // As wide as the widest note (up to 60 % of the row, wrapping past it),
    // so neither its width nor its height follows the note shown.
    ControlCenterStatus {
      id: status
      objectName: "profileStatus"
      anchors.right: parent.right
      width: Math.min(widest, parent.width * 0.6)
      horizontalAlignment: Text.AlignRight
      statuses: ["unavailable", "switching", "failed", "profileUnsaved", "profileSuperseded", "profileDegraded"]
        .map(function(k) { return root.strings.t("controlCenter." + k) })
      text: root.statusText
      color: root.outcome === "failed" ? root.theme.dangerText : root.theme.secondaryText
      font.family: root.theme.textFamily
      font.pixelSize: Math.round(11 * root.theme.fontScale)
    }
  }

  Row {
    id: row

    width: parent.width
    spacing: Math.round(6 * root.s)
    visible: root.available

    Repeater {
      id: segments

      model: root.available ? root.provider.profiles : []

      Rectangle {
        id: segment

        required property string modelData
        readonly property bool lit: modelData === root.current
        readonly property bool asked: root.request !== null && root.request.target === modelData
        readonly property color ink: lit ? root.theme.accentForeground : root.theme.foreground

        objectName: "profile:" + modelData
        width: (row.width - (segments.count - 1) * row.spacing) / Math.max(1, segments.count)
        height: Math.max(Math.round(34 * root.s), name.implicitHeight + 2 * Math.round(7 * root.s))
        radius: Math.round(8 * root.s)
        color: lit ? root.theme.accent
          : (pointer.pressed ? root.theme.pressed : (pointer.containsMouse ? root.theme.hover : root.theme.surface))
        border.width: activeFocus && root.keyboardShown && !lit ? Math.max(1, Math.round(1.5 * root.s)) : 1
        border.color: activeFocus && root.keyboardShown && !lit ? root.theme.accent : root.theme.border
        activeFocusOnTab: true
        enabled: root.available

        Accessible.role: Accessible.RadioButton
        Accessible.checkable: true
        Accessible.checked: segment.lit
        Accessible.name: name.text
        Accessible.description: segment.asked ? root.strings.t("controlCenter.switching") : root.statusText
        Accessible.onPressAction: root.select(segment.modelData)

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.select(segment.modelData)
            event.accepted = true
          }
        }

        Text {
          id: name
          objectName: "profileLabel"
          anchors.centerIn: parent
          width: parent.width - 2 * Math.round(6 * root.s)
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
          text: root.strings.t("controlCenter.profile." + segment.modelData)
          // Switching shows as secondary text, except while pressed: the
          // pressed fill (foreground at 0.14) is not among the grounds
          // secondaryText is made readable on (3.7-4.2:1 there); ink is
          // at least 5.3:1 on it.
          color: segment.asked && !pointer.pressed ? root.theme.secondaryText : segment.ink
          font.family: root.theme.textFamily
          font.pixelSize: Math.round(12 * root.theme.fontScale)
          font.weight: segment.lit ? Font.DemiBold : Font.Normal
        }

        // The focus ring on the lit segment, drawn inside the fill (as on
        // the tiles), so it shows against the accent.
        Rectangle {
          objectName: "litFocusRing"
          anchors.fill: parent
          anchors.margins: Math.round(3 * root.s)
          radius: Math.max(0, parent.radius - Math.round(3 * root.s))
          color: "transparent"
          border.width: Math.max(1, Math.round(1.5 * root.s))
          border.color: root.theme.accentForeground
          visible: segment.activeFocus && root.keyboardShown && segment.lit
        }

        MouseArea {
          id: pointer
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.select(segment.modelData)
        }
      }
    }
  }
}
