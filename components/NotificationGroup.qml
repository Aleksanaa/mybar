import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "."

ColumnLayout {
    id: groupRoot
    property string appName: ""
    property string appIcon: ""
    property var notifications: []
    property bool expanded: false

    spacing: 4 // Tighter spacing between header and content
    Layout.fillWidth: true

    // Group Header (Always shown)
    RowLayout {
        id: groupHeader
        Layout.fillWidth: true
        spacing: 10
        Layout.leftMargin: 4
        Layout.rightMargin: 4

        IconImage {
            id: groupIcon
            implicitSize: 16
            source: Theme.resolveAppIcon(groupRoot.appIcon, groupRoot.appName, "preferences-desktop-notification-symbolic")
        }

        Text {
            text: groupRoot.appName
            color: Theme.fg
            font.family: Theme.globalFont
            font.pixelSize: 11
            font.bold: true
            opacity: 0.8
            Layout.fillWidth: true
        }

        // Expand/Fold Button
        Item {
            width: 24
            height: 24
            visible: groupRoot.notifications.length > 1

            IconImage {
                anchors.centerIn: parent
                source: Quickshell.iconPath(groupRoot.expanded ? "go-up-symbolic" : "go-down-symbolic")
                implicitSize: 16
                layer.enabled: true
                layer.effect: ColorOverlay {
                    color: Theme.fg
                }
                opacity: expandHover.hovered ? 1.0 : 0.6
            }

            HoverHandler {
                id: expandHover
            }
            TapHandler {
                onTapped: groupRoot.expanded = !groupRoot.expanded
            }
        }

        // Close Group Button
        Item {
            width: 24
            height: 24

            IconImage {
                anchors.centerIn: parent
                source: Quickshell.iconPath("edit-clear-all-symbolic")
                implicitSize: 16
                layer.enabled: true
                layer.effect: ColorOverlay {
                    color: Theme.fg
                }
                opacity: closeGroupHover.hovered ? 1.0 : 0.6
            }

            HoverHandler {
                id: closeGroupHover
            }
            TapHandler {
                onTapped: {
                    root.writeOutput({
                        "action": "clear-app-notifications",
                        "app_name": groupRoot.appName
                    });
                }
            }
        }
    }

    // Stacked/Expanded Notifications
    Item {
        Layout.fillWidth: true
        // Extra top margin for the stack offset effect
        Layout.topMargin: groupRoot.expanded ? 0 : 8
        implicitHeight: groupRoot.expanded ? expandedLayout.implicitHeight : collapsedStack.implicitHeight

        // Collapsed View (Stacked with upward offset)
        Item {
            id: collapsedStack
            width: parent.width
            implicitHeight: topItem.height
            visible: !groupRoot.expanded

            // Pseudo notification 2 (backmost)
            Rectangle {
                width: parent.width - 24
                height: 40
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: topItem.top
                anchors.bottomMargin: -32 // Visual offset behind
                y: -8 // Actual "Offset up"
                color: Theme.border
                border.color: Theme.capsule
                radius: 8
                opacity: 0.2
                visible: groupRoot.notifications.length > 2
                z: 1
            }

            // Pseudo notification 1 (middle)
            Rectangle {
                width: parent.width - 12
                height: 40
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: topItem.top
                anchors.bottomMargin: -36
                y: -4 // Actual "Offset up"
                color: Theme.border
                border.color: Theme.capsule
                radius: 8
                opacity: 0.4
                visible: groupRoot.notifications.length > 1
                z: 2
            }

            // Top Notification
            NotificationItem {
                id: topItem
                width: parent.width
                notification: groupRoot.notifications[0]
                isPopup: false
                showHeader: false
                z: 3
            }
        }

        // Expanded View
        ColumnLayout {
            id: expandedLayout
            width: parent.width
            spacing: 6
            visible: groupRoot.expanded

            Repeater {
                model: groupRoot.notifications
                delegate: NotificationItem {
                    Layout.fillWidth: true
                    notification: modelData
                    isPopup: false
                    showHeader: false
                }
            }
        }
    }
}
