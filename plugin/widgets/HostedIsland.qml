pragma ComponentBehavior: Bound
import QtQuick
import "../components"
import "../logic/Hosted.js" as Hosted

// Bar widgets this bar does not draw itself (network, power, a user's audio
// plugin, ...), each loaded from the shell's widget registry and given the
// public PluginBarApi facade, in one island on the right.
Island {
  id: root

  // [{ id, settings }] from logic/Settings.js hostedEntries().
  required property var entries
  required property var hosting
  required property var registry
  required property string screenName

  // Empty while no hosted widget takes up room. It stays `visible` either way:
  // widths here come from the widgets' effective visibility, so hiding the
  // island for being empty would keep it empty. It fades out instead, and the
  // surface leaves it out of the input mask and the layout.
  readonly property bool empty: implicitWidth <= paddingLeft + paddingRight + 2 * borderWidth + 0.5
  opacity: empty ? 0 : 1
  // As in the other islands: buttons sit buttonInset from the island's edge.
  paddingLeft: theme.m.buttonInset
  paddingRight: theme.m.buttonInset

  // One slot per configured widget, kept across configuration changes: each
  // shell.json change brings this model to the new order (logic/Hosted.js)
  // instead of rebuilding every widget.
  readonly property var settingsById: Hosted.settingsById(entries)
  onEntriesChanged: root.reconcile()
  Component.onCompleted: root.reconcile()

  function reconcile() {
    var current = []
    for (var i = 0; i < slotModel.count; i++) current.push(slotModel.get(i).wid)
    var ops = Hosted.reconcile(current, Hosted.uniqueIds(root.entries))
    for (var j = 0; j < ops.length; j++) {
      var op = ops[j]
      if (op.op === "remove") slotModel.remove(op.index)
      else if (op.op === "move") slotModel.move(op.from, op.to, 1)
      else slotModel.insert(op.index, { wid: op.id })
    }
  }

  // Each slot's state, for `floating-islands slots`.
  function describeSlots() {
    var out = []
    for (var i = 0; i < slots.count; i++) {
      var cell = slots.itemAt(i)
      out.push(cell ? cell.describe() : null)
    }
    return out
  }

  // A native control at the start of the island (the Control Center entry),
  // or nothing. It is not a hosted widget, so it takes no hotkey number.
  property Component leading: null
  readonly property Item leadingItem: leadingLoader.item

  Loader {
    id: leadingLoader

    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    active: root.leading !== null
    visible: active
    sourceComponent: root.leading
  }

  ListModel { id: slotModel }

  Repeater {
    id: slots

    model: slotModel

    // One hosted widget in a slot of the islands' button height, at least
    // statusSlot wide, with the islands' hover and pressed fills. The handlers
    // are passive: the widget's own MouseArea still takes every event.
    Item {
      id: cell

      required property string wid
      readonly property alias fill: fill
      readonly property bool shown: slot.visual !== null && slot.visual.visible

      objectName: "hostedSlot"

      function describe() {
        return {
          id: cell.wid,
          registered: slot.registered !== null,
          live: slot.registered !== null && !!slot.registered.component,
          loader: slot.status,
          visible: cell.shown,
          width: cell.width,
          loads: slot.loads
        }
      }

      anchors.verticalCenter: parent ? parent.verticalCenter : undefined
      // Never hidden: `shown` reads the widget's effective visibility, which a
      // hidden cell would force to false. An absent widget takes no width.
      width: shown ? Math.max(slot.width, root.theme.m.statusSlot) : 0
      height: root.theme.m.islandHeight - 2 * root.theme.m.buttonInset

      Rectangle {
        id: fill

        anchors.fill: parent
        radius: root.theme.m.buttonRadius
        color: press.active ? root.theme.pressed : (hover.hovered ? root.theme.hover : "transparent")

        Behavior on color { ColorAnimation { duration: root.theme.fast; easing.type: Easing.OutCubic } }
      }


      // A Loader, as the stock bar uses: the registry's widget components can be
      // handed to a Loader but not instantiated from JavaScript in a plugin
      // (createObject on them fails in the live shell). So bar, moduleName and
      // settings are injected right after construction, as the stock bar does.
      Loader {
        id: slot

        readonly property string moduleName: cell.wid
        readonly property var settings: root.settingsById[cell.wid] || ({})
        // Reading `widgets` (and the revision) keeps this following the registry
        // as plugins are enabled, disabled or reloaded.
        readonly property var registered: {
          var revision = root.registry ? root.registry.revision : 0
          var widgets = root.registry ? root.registry.widgets : null
          return widgets && widgets[moduleName] ? widgets[moduleName] : null
        }
        readonly property var widgetComponent: Hosted.componentFor(moduleName, registered, !!(root.registry && root.registry.widgets))

        // The item handed to the hosting registry, kept so it can be withdrawn
        // after the Loader has already let go of it.
        property var registeredItem: null
        property int loads: 0

        anchors.centerIn: parent
        active: widgetComponent !== null
        sourceComponent: widgetComponent
        // Bar widgets are Items; anything else is not drawn.
        readonly property Item visual: item as Item

        // Visibility must not depend on width: the width reads the widget's
        // effective visibility, which a hidden Loader would force to false.
        visible: status === Loader.Ready
        width: visual && visual.visible ? visual.implicitWidth : 0
        height: visual ? visual.implicitHeight : 0

        function withdraw() {
          if (!slot.registeredItem) return
          root.hosting.unregisterItem(slot.registeredItem)
          slot.registeredItem = null
        }

        function inject() {
          // Widgets declare these optionally, so they are set by name, as the
          // stock bar does, and only when the widget has them.
          var target = slot.item
          if (!target) return
          var values = {
            fixedEdge: "end",
            bar: root.hosting.facadeFor(slot.moduleName),
            moduleName: slot.moduleName,
            settings: slot.settings
          }
          for (var name in values) if (name in target) target[name] = values[name]
        }

        onLoaded: {
          slot.loads++
          slot.withdraw()
          slot.inject()
          injectAgain.restart()
          slot.registeredItem = slot.item
          root.hosting.registerItem({ item: slot.item, moduleName: slot.moduleName, screenName: root.screenName })
        }
        onSettingsChanged: slot.inject()
        onItemChanged: if (!slot.item) slot.withdraw()
        Component.onDestruction: slot.withdraw()

        // Once more after the widget's own Component.onCompleted, as the stock
        // bar does with Qt.callLater; a child timer cannot outlive the slot,
        // where a queued call would run in a destroyed context.
        Timer { id: injectAgain; interval: 0; onTriggered: slot.inject() }
      }

      // On the cell, below the widget: here it observes hover without taking it
      // from the widget, whose tooltips depend on its own hover.
      HoverHandler { id: hover }

      // Above the widget, so it sees a press before the widget's own MouseArea
      // accepts it. A passive grab: delivery continues to the widget.
      Item {
        anchors.fill: parent
        z: 1

        PointHandler { id: press; acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton }
      }
    }
  }
}
