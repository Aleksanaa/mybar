import QtQuick
import Quickshell

PopupWindow {
    id: root
    property Item target: null

    default property alias content: contentContainer.data
    property bool active: false

    visible: active
    implicitWidth: 220
    implicitHeight: contentContainer.implicitHeight + 20
    color: "transparent"

    anchor {
        item: target
        edges: Edges.Left | Edges.Top
        gravity: Edges.Left | Edges.Bottom
        adjustment: PopupAdjustment.Slide
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        border.color: Theme.border
        border.width: 2
        radius: 8
        opacity: 0.95

        // This is the content slot
        Column {
            id: contentContainer
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 10
            }
            spacing: 8
            // Content defined externally will be displayed here
        }
    }
}
