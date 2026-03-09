import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "."

MyPopup {
    id: monitorPopupRoot
    preferredWidth: 250

    ColumnLayout {
        width: parent.width
        spacing: 12

        Text {
            text: "System Statistics"
            color: Theme.fg
            font.bold: true
            font.family: Theme.globalFont
            font.pixelSize: 14
            Layout.bottomMargin: 2
        }

        // --- CPU Core Section ---
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                IconImage {
                    source: Quickshell.iconPath("cpu-symbolic")
                    implicitSize: 16
                    layer.enabled: true
                    layer.effect: ColorOverlay {
                        color: "#f38ba8"
                    }
                }
                Text {
                    text: "CPU Cores"
                    color: Theme.fg
                    font.pixelSize: 12
                    font.bold: true
                    font.family: Theme.globalFont
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    text: Math.round(root.sysStats.cpu * 100) + "%"
                    color: Theme.fg
                    font.pixelSize: 11
                    font.family: Theme.globalFont
                }
            }

            // Per-core mini bars
            Flow {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: root.sysStats.cpus
                    MyPillBar {
                        width: (parent.width - (root.sysStats.cpus.length - 1) * parent.spacing) / root.sysStats.cpus.length
                        height: 12
                        progress: modelData
                        vertical: true
                        backgroundColor: "#313244"
                        barColor: modelData > 0.8 ? "#f38ba8" : (modelData > 0.5 ? "#fab387" : "#a6e3a1")
                    }
                }
            }
        }

        // --- Grid for other metrics ---
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 16
            rowSpacing: 10

            // Memory
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    IconImage {
                        source: Quickshell.iconPath("memory-symbolic")
                        implicitSize: 14
                        layer.enabled: true
                        layer.effect: ColorOverlay {
                            color: "#fab387"
                        }
                    }
                    Text {
                        text: "RAM"
                        color: Theme.fg
                        font.pixelSize: 10
                        font.family: Theme.globalFont
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Text {
                        text: Math.round(root.sysStats.mem * 100) + "%"
                        color: Theme.fg
                        font.pixelSize: 9
                        font.family: Theme.globalFont
                    }
                }
                MyPillBar {
                    height: 4
                    Layout.fillWidth: true
                    backgroundColor: "#313244"
                    barColor: "#fab387"
                    progress: root.sysStats.mem
                }
            }

            // Swap
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    IconImage {
                        source: Quickshell.iconPath("drive-harddisk-symbolic")
                        implicitSize: 14
                        layer.enabled: true
                        layer.effect: ColorOverlay {
                            color: "#f9e2af"
                        }
                    }
                    Text {
                        text: "SWAP"
                        color: Theme.fg
                        font.pixelSize: 10
                        font.family: Theme.globalFont
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Text {
                        text: Math.round(root.sysStats.swap * 100) + "%"
                        color: Theme.fg
                        font.pixelSize: 9
                        font.family: Theme.globalFont
                    }
                }
                MyPillBar {
                    height: 4
                    Layout.fillWidth: true
                    backgroundColor: "#313244"
                    barColor: "#f9e2af"
                    progress: root.sysStats.swap
                }
            }

            // Temperature
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    IconImage {
                        source: Quickshell.iconPath("sensors-temperature-symbolic")
                        implicitSize: 14
                        layer.enabled: true
                        layer.effect: ColorOverlay {
                            color: "#a6e3a1"
                        }
                    }
                    Text {
                        text: "TEMP"
                        color: Theme.fg
                        font.pixelSize: 10
                        font.family: Theme.globalFont
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Text {
                        text: root.sysStats.temp_c + "°C"
                        color: Theme.fg
                        font.pixelSize: 9
                        font.family: Theme.globalFont
                    }
                }
                MyPillBar {
                    height: 4
                    Layout.fillWidth: true
                    backgroundColor: "#313244"
                    barColor: "#a6e3a1"
                    progress: root.sysStats.temp
                }
            }

            // Frequency
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    IconImage {
                        source: Quickshell.iconPath("speedometer-symbolic")
                        implicitSize: 14
                        layer.enabled: true
                        layer.effect: ColorOverlay {
                            color: "#89b4fa"
                        }
                    }
                    Text {
                        text: "FREQ"
                        color: Theme.fg
                        font.pixelSize: 10
                        font.family: Theme.globalFont
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Text {
                        text: root.sysStats.cpu_freq.current.toFixed(1) + "G"
                        color: Theme.fg
                        font.pixelSize: 9
                        font.family: Theme.globalFont
                    }
                }
                MyPillBar {
                    height: 4
                    Layout.fillWidth: true
                    backgroundColor: "#313244"
                    barColor: "#89b4fa"
                    progress: root.sysStats.cpu_freq.max > 0 ? (root.sysStats.cpu_freq.current / root.sysStats.cpu_freq.max) : 0
                }
            }
        }

        // --- Combined Multi-line Graph ---
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            Layout.topMargin: 4

            MultiLineChart {
                Layout.fillWidth: true
                height: 60
                values: [root.sysStats.cpu, root.sysStats.cpu_freq.max > 0 ? (root.sysStats.cpu_freq.current / root.sysStats.cpu_freq.max) : 0, root.sysStats.mem, root.sysStats.temp]
                lineColors: ["#f38ba8", "#89b4fa", "#fab387", "#a6e3a1"]
            }

            // Legend for the graph
            Flow {
                Layout.fillWidth: true
                spacing: 8
                Layout.alignment: Qt.AlignHCenter

                Repeater {
                    model: [
                        {
                            name: "CPU",
                            color: "#f38ba8"
                        },
                        {
                            name: "FREQ",
                            color: "#89b4fa"
                        },
                        {
                            name: "RAM",
                            color: "#fab387"
                        },
                        {
                            name: "TEMP",
                            color: "#a6e3a1"
                        }
                    ]
                    RowLayout {
                        spacing: 4
                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: modelData.color
                        }
                        Text {
                            text: modelData.name
                            color: Theme.fg
                            font.pixelSize: 9
                            font.family: Theme.globalFont
                            opacity: 0.8
                        }
                    }
                }
            }
        }
    }
}
