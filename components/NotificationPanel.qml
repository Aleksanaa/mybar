import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

MyPopup {
    id: notificationPanel
    preferredWidth: 350

    property int updateTrigger: 0

    function getDisplayList() {
        var _ = updateTrigger; // Access for dependency tracking
        var list = root.sysStats.notifications.list;
        if (!list)
            return [];

        var counts = {};
        for (var i = 0; i < list.length; i++) {
            var n = list[i];
            counts[n.app_name] = (counts[n.app_name] || 0) + 1;
        }

        var result = [];
        var processedApps = {};
        for (var i = 0; i < list.length; i++) {
            var n = list[i];
            if (counts[n.app_name] > 1) {
                if (!processedApps[n.app_name]) {
                    var appNotifications = [];
                    for (var j = 0; j < list.length; j++) {
                        if (list[j].app_name === n.app_name) {
                            appNotifications.push(list[j]);
                        }
                    }
                    result.push({
                        isGroup: true,
                        app_name: n.app_name,
                        app_icon: n.app_icon,
                        notifications: appNotifications
                    });
                    processedApps[n.app_name] = true;
                }
            } else {
                result.push({
                    isGroup: false,
                    notification: n
                });
            }
        }
        return result;
    }

    ColumnLayout {
        width: parent.width
        spacing: 12

        // Header Section
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Notifications"
                color: Theme.fg
                font.bold: true
                font.family: Theme.globalFont
                font.pixelSize: 14
                Layout.fillWidth: true
            }

            // DND Toggle
            Rectangle {
                width: 28
                height: 28
                radius: 14
                color: Theme.border

                IconImage {
                    anchors.centerIn: parent
                    source: Quickshell.iconPath(`notifications${root.sysStats.notifications.dnd ? "-disabled" : ""}-symbolic`)
                    implicitSize: 16
                    layer.enabled: true
                    layer.effect: ColorOverlay {
                        color: Theme.fg
                    }
                }

                TapHandler {
                    onTapped: root.writeOutput({
                        "action": "toggle-dnd"
                    })
                }

                HoverHandler {
                    id: dndHover
                }
            }

            // Clear All
            Rectangle {
                width: 28
                height: 28
                radius: 14
                color: Theme.border

                IconImage {
                    anchors.centerIn: parent
                    source: Quickshell.iconPath("edit-clear-all-symbolic")
                    implicitSize: 16
                    layer.enabled: true
                    layer.effect: ColorOverlay {
                        color: Theme.fg
                    }
                }

                TapHandler {
                    onTapped: root.writeOutput({
                        "action": "clear-notifications"
                    })
                }

                HoverHandler {
                    id: clearHover
                }
            }
        }

        // List Section with ScrollView
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 300
            clip: true

            ListView {
                id: notificationList
                model: notificationPanel.getDisplayList()
                width: parent.width
                spacing: 15

                topMargin: 10
                bottomMargin: 10

                delegate: Item {
                    width: notificationList.width
                    height: loader.item ? loader.item.implicitHeight : 0

                    Loader {
                        id: loader
                        width: parent.width
                        sourceComponent: modelData.isGroup ? groupComp : itemComp

                        Component {
                            id: groupComp
                            NotificationGroup {
                                width: loader.width
                                appName: modelData.app_name
                                appIcon: modelData.app_icon
                                notifications: modelData.notifications
                            }
                        }

                        Component {
                            id: itemComp
                            NotificationItem {
                                width: loader.width
                                notification: modelData.notification
                                isPopup: false
                                showHeader: true
                            }
                        }
                    }
                }

                // Placeholder when empty
                Text {
                    anchors.centerIn: parent
                    text: "No Notifications"
                    color: Theme.fg
                    opacity: 0.3
                    font.family: Theme.globalFont
                    font.pixelSize: 13
                    visible: notificationList.count === 0
                }
            }
        }
    }
}
