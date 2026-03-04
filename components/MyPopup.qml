import QtQuick
import Quickshell

PopupWindow {
    id: root
    property Item target: null
    property real preferredWidth: 220

    default property alias content: contentContainer.data
    property bool active: false

    visible: active
    implicitWidth: preferredWidth
    implicitHeight: contentContainer.implicitHeight + 20
    color: "transparent"

    anchor {
        item: target
        edges: Edges.Left | Edges.Top
        gravity: Edges.Left | Edges.Bottom
        adjustment: PopupAdjustment.Slide
    }

    Rectangle {
        width: parent.width
        height: contentContainer.implicitHeight + 20
        color: Theme.bg
        border.color: Theme.border
        border.width: 2
        radius: 8
        opacity: 0.95

        // This is the content slot
        Column {
            id: contentContainer
            width: parent.width - 20
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
                topMargin: 10
            }
            spacing: 8
            // Content defined externally will be displayed here
        }
    }
}
