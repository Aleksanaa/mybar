import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Qt5Compat.GraphicalEffects

PopupWindow {
    id: root

    // --- Style Configuration ---
    property color backgroundColor: "#2d2d2d"
    property color borderColor: "#444444"
    property color textColor: "#ffffff"
    property color highlightColor: "#3d3d3d"
    property int menuWidth: 220 
    property int itemHeight: 32
    property int iconSize: 18
    property int borderRadius: 6
    property int padding: 4

    // --- Data and State ---
    property var menuHandle: null
    property bool isSubMenu: false
    property var screen: Screens.primary
    property var activeSubMenu: null

    implicitWidth: menuWidth
    implicitHeight: columnLayout.implicitHeight + (padding * 2)
    
    color: "transparent"
    visible: false

    // Anchor system configuration (core modification point)
    // For the first-level menu, we align its top-right corner to the trigger point
    anchor.rect.x: isSubMenu ? -width : -width // Sub-menu is offset to the left, first-level menu is aligned to the top-right
    anchor.rect.y: isSubMenu ? 0 : 4          // Leave a little space below the first-level menu

    onVisibleChanged: {
        // When the menu is hidden, ensure any active child submenus are also closed.
        if (!visible && root.activeSubMenu) {
            root.activeSubMenu.closeAll();
        }
    }

    Item {
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: root.closeAll()
    }

    QsMenuOpener {
        id: opener
        menu: root.menuHandle
    }

    Rectangle {
        anchors.fill: parent
        color: root.backgroundColor
        border.color: root.borderColor
        border.width: 1
        radius: root.borderRadius
    }

    MouseArea {
        anchors.fill: parent
        // This MouseArea should be on top of other items when a submenu is active
        z: 1 
        enabled: root.activeSubMenu !== null // Only active when a submenu is open
        onClicked: {
            // If there's an active submenu, close it
            if (root.activeSubMenu && root.activeSubMenu.visible) {
                root.activeSubMenu.closeAll();
            }
        }
    }

    ColumnLayout {
        id: columnLayout
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 0

        Repeater {
            model: opener.children ? [...opener.children.values] : []
            
            delegate: Rectangle {
                id: itemDelegate
                required property var modelData
                
                Layout.fillWidth: true
                Layout.preferredHeight: modelData.isSeparator ? 8 : root.itemHeight
                color: mouseArea.containsMouse ? root.highlightColor : "transparent"
                radius: 4

                Rectangle {
                    visible: modelData.isSeparator
                    anchors.centerIn: parent
                    width: parent.width - 10
                    height: 1
                    color: root.borderColor
                }

                RowLayout {
                    visible: !modelData.isSeparator
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    // 1. Sub-menu indicator arrow (now on the left, because the menu expands to the left)
                    Text {
                        text: "◀"
                        color: root.textColor
                        font.pixelSize: 10
                        visible: modelData.hasChildren
                        Layout.preferredWidth: 10
                    }

                    // 2. Menu icon
                    Image {
                        source: modelData.icon || ""
                        Layout.preferredWidth: root.iconSize
                        Layout.preferredHeight: root.iconSize
                        fillMode: Image.PreserveAspectFit
                        visible: source != ""
                        asynchronous: true
                    }

                    // 3. Menu text
                    Text {
                        Layout.fillWidth: true
                        text: modelData.text ? modelData.text.replace(/&/g, "") : ""
                        color: modelData.enabled ? root.textColor : "#888888"
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }

                    // 4. Check status (on the right)
                    Text {
                        text: (modelData.checkState === Qt.Checked || modelData.checked) ? "✓" : ""
                        color: root.textColor
                        font.pixelSize: 14
                        Layout.preferredWidth: 12
                    }
                }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: modelData.enabled && !modelData.isSeparator
                    
                    onClicked: {
                        if (modelData.hasChildren) {
                            var component = Qt.createComponent(Qt.resolvedUrl("TrayMenu.qml"));
                            if (component.status === Component.Ready) {
                                var parentMenu = root; // Capture root context
                                var sub = component.createObject(parentMenu, {
                                    "menuHandle": modelData,
                                    "isSubMenu": true,
                                    "screen": parentMenu.screen,
                                    "backgroundColor": parentMenu.backgroundColor,
                                    "borderColor": parentMenu.borderColor,
                                    "textColor": parentMenu.textColor,
                                    "highlightColor": parentMenu.highlightColor,
                                    "anchor.item": itemDelegate
                                });
                                parentMenu.activeSubMenu = sub; // Keep track of the active submenu
                                sub.onVisibleChanged.connect(function() {
                                    if (!sub.visible) {
                                        parentMenu.activeSubMenu = null; // Clear when submenu closes
                                    }
                                });
                                sub.visible = true; 
                            }
                        } else {
                            modelData.triggered();
                            root.closeAll(); 
                        }
                    }
                }
            }
        }
    }

    function closeAll() {
        root.visible = false;
        if (root.parent && typeof root.parent.closeAll === "function") {
            root.parent.closeAll();
        }
    }

    function showAt(anchorItem, screenObj) {
        if (!anchorItem) return;
        root.anchor.item = anchorItem;
        if (screenObj) root.screen = screenObj;
        root.visible = true;
    }
}
