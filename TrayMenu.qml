import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

PopupWindow {
    id: root

    // --- 样式配置 ---
    property color backgroundColor: "#2d2d2d"
    property color borderColor: "#444444"
    property color textColor: "#ffffff"
    property color highlightColor: "#3d3d3d"
    property int menuWidth: 220 // 增加一点宽度以容纳图标
    property int itemHeight: 28
    property int iconSize: 18    // 菜单项图标大小
    property int borderRadius: 6
    property int padding: 4

    // --- 数据与状态 ---
    property var menuHandle: null
    property bool isSubMenu: false
    property var screen: Screens.primary

    implicitWidth: menuWidth
    implicitHeight: columnLayout.implicitHeight + (padding * 2)
    
    color: "transparent"
    visible: false

    onVisibleChanged: {
        if (visible) root.forceActiveFocus();
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

                    // 1. 勾选状态指示器
                    Text {
                        text: (modelData.checkState === Qt.Checked || modelData.checked) ? "✓" : ""
                        color: root.textColor
                        font.pixelSize: 14
                        Layout.preferredWidth: 12
                    }

                    // 2. 菜单图标 (新增部分)
                    Image {
                        source: modelData.icon || "" // 自动处理图标路径
                        Layout.preferredWidth: root.iconSize
                        Layout.preferredHeight: root.iconSize
                        fillMode: Image.PreserveAspectFit
                        visible: source != "" // 如果没有图标则隐藏
                        
                        // 某些图标可能来自本地路径或系统主题，Qt 会尝试自动解析
                        asynchronous: true 
                    }

                    // 3. 菜单文字
                    Text {
                        Layout.fillWidth: true
                        text: modelData.text ? modelData.text.replace(/&/g, "") : ""
                        color: modelData.enabled ? root.textColor : "#888888"
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }

                    // 4. 子菜单箭头
                    Text {
                        text: "▶"
                        color: root.textColor
                        font.pixelSize: 10
                        visible: modelData.hasChildren
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
                                var sub = component.createObject(root, {
                                    "menuHandle": modelData,
                                    "isSubMenu": true,
                                    "screen": root.screen,
                                    "backgroundColor": root.backgroundColor,
                                    "borderColor": root.borderColor,
                                    "textColor": root.textColor,
                                    "highlightColor": root.highlightColor,
                                    "anchor.item": itemDelegate,
                                    "anchor.rect.x": itemDelegate.width,
                                    "anchor.rect.y": 0
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
