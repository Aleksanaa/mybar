import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "."

MyPopup {
    id: networkPopupRoot
    preferredWidth: 250

    ColumnLayout {
        width: parent.width
        spacing: 12

        Text {
            text: "Network Usage"
            color: Theme.fg
            font.bold: true
            font.family: Theme.globalFont
            font.pixelSize: 14
            Layout.bottomMargin: 2
        }

        // --- Upload Info ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            IconImage {
                source: Quickshell.iconPath("network-transmit-receive-symbolic")
                implicitSize: 16
                layer.enabled: true
                layer.effect: ColorOverlay {
                    color: Theme.accent
                }
            }
            ColumnLayout {
                spacing: 0
                Text {
                    text: "Upload"
                    color: Theme.fg
                    font.pixelSize: 11
                    font.family: Theme.globalFont
                    opacity: 0.8
                }
                Text {
                    text: root.sysStats.net.up + " " + root.sysStats.net.up_unit
                    color: "#a6e3a1"
                    font.pixelSize: 13
                    font.bold: true
                    font.family: Theme.globalFont
                }
            }
            Item {
                Layout.fillWidth: true
            }
            ColumnLayout {
                spacing: 0
                Layout.alignment: Qt.AlignRight
                Text {
                    text: "Download"
                    color: Theme.fg
                    font.pixelSize: 11
                    font.family: Theme.globalFont
                    opacity: 0.8
                    Layout.alignment: Qt.AlignRight
                }
                Text {
                    text: root.sysStats.net.down + " " + root.sysStats.net.down_unit
                    color: "#89b4fa"
                    font.pixelSize: 13
                    font.bold: true
                    font.family: Theme.globalFont
                    Layout.alignment: Qt.AlignRight
                }
            }
        }

        // --- Graph Section ---
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            Layout.topMargin: 4

            MultiLineChart {
                id: netChart
                Layout.fillWidth: true
                height: 80
                autoScale: true
                values: [root.sysStats.net.up_raw, root.sysStats.net.down_raw]
                lineColors: ["#a6e3a1", "#89b4fa"]
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Layout.alignment: Qt.AlignHCenter

                RowLayout {
                    spacing: 4
                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: "#a6e3a1"
                    }
                    Text {
                        text: "Up"
                        color: Theme.fg
                        font.pixelSize: 10
                        font.family: Theme.globalFont
                        opacity: 0.8
                    }
                }
                RowLayout {
                    spacing: 4
                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: "#89b4fa"
                    }
                    Text {
                        text: "Down"
                        color: Theme.fg
                        font.pixelSize: 10
                        font.family: Theme.globalFont
                        opacity: 0.8
                    }
                }
            }
        }
    }
}
