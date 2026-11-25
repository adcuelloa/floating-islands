pragma ComponentBehavior: Bound
import QtQuick
import "../components"
import "../theme/Icons.js" as Icons

// The left island: the launcher, a hairline, and this output's workspaces.
Island {
  id: root

  required property var workspaces
  required property var strings
  property var reach: ({ top: 0, bottom: 0 })
  // "omarchy": the logo from Omarchy's icon font, as the stock menu widget
  // draws it. "grid": a generic application grid (bar.islands.launcherIcon).
  property string iconStyle: "omarchy"

  signal launcherClicked(int button)

  IslandButton {
    objectName: "launcherButton"
    theme: root.theme
    reachTop: root.reach.top
    reachBottom: root.reach.bottom
    accessibleName: root.strings.t("launcher")
    onClicked: function(button) { root.launcherClicked(button) }

    Text {
      objectName: "launcherLogo"
      visible: root.iconStyle !== "grid"
      textFormat: Text.PlainText
      text: "\ue900"
      font.family: "omarchy"
      font.pixelSize: Math.round(18 * root.theme.m.scale)
      color: root.theme.accent
      // One em square, centred like the stroke icons beside it.
      width: font.pixelSize
      height: font.pixelSize
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }

    StrokeIcon {
      objectName: "launcherGrid"
      visible: root.iconStyle === "grid"
      icon: Icons.grid
      size: Math.round(18 * root.theme.m.scale)
      color: root.theme.accent
    }
  }

  Divider {
    theme: root.theme
    anchors.verticalCenter: parent.verticalCenter
  }

  Row {
    anchors.verticalCenter: parent.verticalCenter
    leftPadding: Math.round(2 * root.theme.m.scale)
    rightPadding: Math.round(2 * root.theme.m.scale)

    Accessible.role: Accessible.PageTabList
    Accessible.name: root.strings.t("workspaces")

    Repeater {
      model: root.workspaces.entries

      Row {
        id: slot

        required property var modelData

        // A gap sets workspaces visiting from another monitor apart.
        Item {
          visible: slot.modelData.firstGuest
          width: Math.round(6 * root.theme.m.scale)
          height: 1
        }

        IslandButton {
          objectName: "workspaceButton"
          theme: root.theme
          minimumWidth: root.theme.m.workspaceSlot
          horizontalPadding: Math.round(2 * root.theme.m.scale)
          reachTop: root.reach.top
          reachBottom: root.reach.bottom
          reachSide: Math.round(1 * root.theme.m.scale)
          accessibleName: (slot.modelData.occupied || slot.modelData.active
            ? root.strings.t("workspace") : root.strings.t("workspace.empty")).arg(slot.modelData.label)
          onClicked: function(button) { if (button === Qt.LeftButton) root.workspaces.focus(slot.modelData.id) }
          onWheelMoved: function(delta) { root.workspaces.scroll(delta) }

          WorkspaceDot {
            theme: root.theme
            active: slot.modelData.active
            occupied: slot.modelData.occupied
          }
        }
      }
    }
  }
}
