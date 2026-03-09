import QtQuick
import Qt5Compat.GraphicalEffects

Item {
    id: pillBarRoot
    property real progress: 0.0
    property bool vertical: false
    property color barColor: Theme.accent
    property color backgroundColor: Theme.border
    property int animationDuration: 300

    implicitWidth: vertical ? 6 : 100
    implicitHeight: vertical ? 100 : 6

    // The visible background track
    Rectangle {
        id: backgroundTrack
        anchors.fill: parent
        color: pillBarRoot.backgroundColor
        radius: Math.min(width, height) / 2
    }

    // This container ensures the source and mask have the same dimensions
    // to prevent distorted rounding when the value is low.
    Item {
        id: maskContainer
        anchors.fill: parent
        visible: false

        // 1. The Mask Shape (same as background)
        Rectangle {
            id: maskShape
            anchors.fill: parent
            radius: backgroundTrack.radius
            color: "black"
        }

        // 2. The Source (a full-sized item containing the partial fill)
        Item {
            id: fillSource
            anchors.fill: parent
            Rectangle {
                id: fillRect
                width: vertical ? parent.width : parent.width * Math.max(0, Math.min(1, pillBarRoot.progress))
                height: vertical ? parent.height * Math.max(0, Math.min(1, pillBarRoot.progress)) : parent.height
                anchors.bottom: vertical ? parent.bottom : undefined
                anchors.left: vertical ? undefined : parent.left
                color: pillBarRoot.barColor

                Behavior on width {
                    enabled: !vertical
                    NumberAnimation {
                        duration: pillBarRoot.animationDuration
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on height {
                    enabled: vertical
                    NumberAnimation {
                        duration: pillBarRoot.animationDuration
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    // Apply the mask to the fillSource using the maskShape.
    // Since both are parent-sized, the rounding will always be 1:1.
    OpacityMask {
        anchors.fill: parent
        source: fillSource
        maskSource: maskShape
    }
}
