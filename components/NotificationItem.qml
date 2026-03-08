import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "."

Rectangle {
    id: rootItem
    property var notification: null
    property bool isPopup: false
    property bool showHeader: true

    signal closed

    width: parent ? parent.width : 350
    implicitHeight: layout.implicitHeight + 24

    color: isPopup ? Theme.bg : Theme.border
    border.color: isPopup ? Theme.border : Theme.capsule
    border.width: 1
    radius: 8
    opacity: isPopup ? 0.95 : 1.0

    ColumnLayout {
        id: layout
        anchors {
            fill: parent
            margins: 12
        }
        spacing: showHeader ? 10 : 4

        // Header: Icon, Name, Close Button
        RowLayout {
            spacing: 10
            Layout.fillWidth: true
            visible: rootItem.showHeader

            IconImage {
                id: notificationIcon
                implicitSize: 18
                source: {
                    if (!rootItem.notification)
                        return Quickshell.iconPath("preferences-desktop-notification-symbolic");
                    return Theme.resolveAppIcon(rootItem.notification.app_icon, rootItem.notification.app_name, "preferences-desktop-notification-symbolic");
                }
            }

            Text {
                text: rootItem.notification ? rootItem.notification.app_name : "Notification"
                color: Theme.fg
                font.family: Theme.globalFont
                font.pixelSize: 11
                font.bold: true
                opacity: 0.8
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            // Larger Close Button
            Item {
                width: 24
                height: 24

                IconImage {
                    anchors.centerIn: parent
                    source: Quickshell.iconPath("window-close-symbolic")
                    implicitSize: 18 // Enlarged icon
                    layer.enabled: true
                    layer.effect: ColorOverlay {
                        color: Theme.fg
                    }
                    opacity: closeHover.hovered ? 1.0 : 0.5
                }

                HoverHandler {
                    id: closeHover
                }
                TapHandler {
                    onTapped: {
                        if (rootItem.notification) {
                            root.writeOutput({
                                "action": "close-notification",
                                "id": rootItem.notification.id
                            });
                            rootItem.closed();
                        }
                    }
                }
            }
        }

        // Content Section
        ColumnLayout {
            spacing: 4
            Layout.fillWidth: true

            Text {
                text: rootItem.notification ? rootItem.notification.summary : ""
                color: Theme.fg
                font.family: Theme.globalFont
                font.pixelSize: 14
                font.bold: true
                elide: Text.ElideRight
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            Text {
                text: rootItem.notification ? rootItem.notification.body : ""
                color: Theme.fg
                font.family: Theme.globalFont
                font.pixelSize: 12
                wrapMode: Text.Wrap
                maximumLineCount: rootItem.isPopup ? 3 : 10
                elide: Text.ElideRight
                Layout.fillWidth: true
                opacity: 0.9
            }
        }

        // Actions Row
        Flow {
            spacing: 8
            Layout.fillWidth: true
            visible: rootItem.notification && rootItem.notification.actions && rootItem.notification.actions.length > 0

            Repeater {
                model: rootItem.notification ? rootItem.notification.actions.length / 2 : 0
                delegate: Rectangle {
                    width: actionText.implicitWidth + 20
                    height: 28
                    radius: 14
                    color: actionHover.hovered ? Theme.accent : Theme.border

                    Text {
                        id: actionText
                        anchors.centerIn: parent
                        text: rootItem.notification.actions[index * 2 + 1]
                        color: actionHover.hovered ? Theme.bg : Theme.fg
                        font.family: Theme.globalFont
                        font.pixelSize: 10
                        font.bold: true
                    }

                    HoverHandler {
                        id: actionHover
                    }
                    TapHandler {
                        onTapped: {
                            root.writeOutput({
                                "action": "invoke-notification-action",
                                "id": rootItem.notification.id,
                                "action_key": rootItem.notification.actions[index * 2]
                            });
                            rootItem.closed();
                        }
                    }
                }
            }
        }
    }
}
