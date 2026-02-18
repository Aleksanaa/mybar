import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

PopupWindow {
    id: root

    // --- 可配置样式 ---
    property color backgroundColor: "#2d2d2d"
    property color borderColor: "#444444"
    property color textColor: "#ffffff"
    property color highlightColor: "#3d3d3d"
    property int menuWidth: 200
    property int itemHeight: 30
    property int borderRadius: 8
    property int padding: 4

    // 核心数据
    property var menuHandle: null
    property bool isSubMenu: false
    // 重要：Quickshell 窗口通常需要 screen 属性来确定位置
    property var screen: null 

    implicitWidth: menuWidth
    implicitHeight: columnLayout.implicitHeight + (padding * 2)
    
    color: "transparent"
    visible: false

    // 菜单打开时请求焦点，以便支持键盘关闭
    onVisibleChanged: {
        if (visible) root.forceActiveFocus();
    }

    Item {
        anchors.fill: parent
        Keys.onEscapePressed: root.visible = false;
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

                    Text {
                        text: (modelData.checkState === Qt.Checked || modelData.checked) ? "✓" : ""
                        color: root.textColor
                        font.pixelSize: 14
                        width: 12
                    }

                    Text {
                        Layout.fillWidth: true
                        text: modelData.text ? modelData.text.replace(/&/g, "") : ""
                        color: modelData.enabled ? root.textColor : "#888888"
                        elide: Text.ElideRight
                    }

                    Text {
                        text: modelData.hasChildren ? "▶" : ""
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
                            // --- 修正：使用动态创建来避免递归实例化错误 ---
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
                            } else {
                                console.error("Error loading sub-menu:", component.errorString());
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

    // 递归关闭所有层级的菜单
    function closeAll() {
        root.visible = false;
        // 这里的 parent 在动态创建时是上一级菜单
        if (root.parent && typeof root.parent.closeAll === "function") {
            root.parent.closeAll();
        }
    }

    // 外部调用：传入锚点 item 和当前的屏幕对象
    function showAt(anchorItem, screenObj) {
        root.anchor.item = anchorItem;
        root.screen = screenObj;
        root.visible = true;
    }
}
