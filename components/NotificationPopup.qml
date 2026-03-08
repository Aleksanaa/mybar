import QtQuick
import Quickshell
import Quickshell.Wayland
import QtQuick.Layouts

PanelWindow {
    id: notificationPopup

    property var currentNotification: null

    visible: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors {
        bottom: true
        right: true
    }

    margins {
        bottom: 16
        right: 60 // 44 (bar width) + 16 padding
    }

    implicitWidth: 336
    implicitHeight: item.implicitHeight
    color: "transparent"

    NotificationItem {
        id: item
        notification: notificationPopup.currentNotification
        isPopup: true
        width: 336
        onClosed: {
            notificationPopup.visible = false;
        }
    }

    Timer {
        id: hideTimer
        interval: 5000
        onTriggered: notificationPopup.visible = false
    }

    function show(notification) {
        currentNotification = notification;
        notificationPopup.visible = true;
        hideTimer.restart();
    }

    function hideIfIdMatches(id) {
        if (currentNotification && currentNotification.id === id) {
            notificationPopup.visible = false;
        }
    }
}
