import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "."

MyPopup {
    id: adjustPopupRoot
    preferredWidth: 220 // Default width from main.qml for this popup

    onActiveChanged: {
        root.writeOutput({
            "action": "toggle_visualizer",
            "enabled": active
        });
    }

    Item {
        width: parent.width
        height: brightnessLabelRow.implicitHeight
        Row {
            id: brightnessLabelRow
            spacing: 8
            IconImage {
                anchors.verticalCenter: parent.verticalCenter
                source: Quickshell.iconPath(`brightness-${root.sysStats.brightness.approx}-symbolic`)
                implicitSize: 16
                layer.enabled: true
                layer.effect: ColorOverlay {
                    color: Theme.accent
                }
            }
            Text {
                text: "Brightness:"
                color: Theme.fg
                font.family: Theme.globalFont
                font.pixelSize: 13
                font.bold: true
            }
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: `${Math.round(root.sysStats.brightness.value * 100)}%`
            color: Theme.fg
            font.family: Theme.globalFont
            font.pixelSize: 13
            font.bold: true
        }
    }

    MySlider {
        width: parent.width
        value: root.sysStats.brightness.value
        onMoved: root.writeOutput({
            "action": "set_brightness",
            "value": value
        })
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.border
        opacity: 0.5
    }

    Item {
        width: parent.width
        height: volumeLabelRow.implicitHeight
        Row {
            id: volumeLabelRow
            spacing: 8
            IconImage {
                anchors.verticalCenter: parent.verticalCenter
                source: Quickshell.iconPath(`audio-volume-${root.sysStats.volume.approx}-symbolic`)
                implicitSize: 16
                layer.enabled: true
                layer.effect: ColorOverlay {
                    color: Theme.accent
                }
                TapHandler {
                    onTapped: root.writeOutput({
                        "action": "toggle_mute"
                    })
                }
            }
            Text {
                text: "Volume:"
                color: Theme.fg
                font.family: Theme.globalFont
                font.pixelSize: 13
                font.bold: true
            }
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: `${Math.round(root.sysStats.volume.value * 100)}%`
            color: Theme.fg
            font.family: Theme.globalFont
            font.pixelSize: 13
            font.bold: true
        }
    }

    MySlider {
        width: parent.width
        value: root.sysStats.volume.value
        onMoved: root.writeOutput({
            "action": "set_volume",
            "value": value
        })
    }

    // Combined MPRIS and Visualizer
    Item {
        width: parent.width
        height: mprisColumn.implicitHeight
        visible: root.sysStats.mpris !== null

        // Visualizer Background
        Row {
            id: visualizerRow
            anchors.fill: parent
            spacing: 2
            opacity: 0.3 // Subtle transparency
            visible: {
                if (!root.sysStats.visualizer)
                    return false;
                for (var i = 0; i < root.sysStats.visualizer.length; i++) {
                    if (root.sysStats.visualizer[i] > 0.001)
                        return true;
                }
                return false;
            }
            Repeater {
                model: root.sysStats.visualizer ? root.sysStats.visualizer.length : 0
                Item {
                    width: (visualizerRow.width - (visualizerRow.spacing * (root.sysStats.visualizer.length - 1))) / root.sysStats.visualizer.length
                    height: visualizerRow.height
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.max(2, root.sysStats.visualizer[index] * parent.height)
                        color: Theme.accent
                        radius: 1
                    }
                }
            }
        }

        // Foreground Media Info
        Column {
            id: mprisColumn
            width: parent.width
            spacing: 8

            Row {
                width: parent.width
                spacing: 10
                Rectangle {
                    width: 48
                    height: 48
                    radius: 4
                    color: Theme.capsule
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: (root.sysStats.mpris && root.sysStats.mpris.art_url) ? root.sysStats.mpris.art_url : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                    }
                    IconImage {
                        anchors.centerIn: parent
                        source: Quickshell.iconPath("audio-x-generic-symbolic")
                        visible: parent.children[0].status !== Image.Ready
                        implicitSize: 24
                        layer.enabled: true
                        layer.effect: ColorOverlay {
                            color: Theme.fg
                        }
                    }
                }

                Column {
                    width: parent.width - 58
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        width: parent.width
                        text: (root.sysStats.mpris && root.sysStats.mpris.title) ? root.sysStats.mpris.title : "Not Playing"
                        color: Theme.fg
                        font.bold: true
                        elide: Text.ElideRight
                        style: Text.Outline
                        styleColor: Theme.bg // Added outline for readability over visualizer
                    }
                    Text {
                        width: parent.width
                        text: (root.sysStats.mpris && root.sysStats.mpris.artist) ? root.sysStats.mpris.artist : "Let's play some music"
                        color: Theme.fg
                        opacity: 0.9 // Slightly higher opacity for readability
                        elide: Text.ElideRight
                        font.pixelSize: 12
                        style: Text.Outline
                        styleColor: Theme.bg
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 20

                IconImage {
                    source: Quickshell.iconPath("media-skip-backward-symbolic")
                    implicitSize: 20
                    layer.enabled: true
                    layer.effect: ColorOverlay {
                        color: Theme.fg
                    }
                    TapHandler {
                        onTapped: if (root.sysStats.mpris) {
                            root.writeOutput({
                                "action": "mpris_action",
                                "bus_name": root.sysStats.mpris.bus_name,
                                "action_type": "previous"
                            });
                        }
                    }
                }

                IconImage {
                    source: Quickshell.iconPath(root.sysStats.mpris && root.sysStats.mpris.status === "Playing" ? "media-playback-pause-symbolic" : "media-playback-start-symbolic")
                    implicitSize: 24
                    layer.enabled: true
                    layer.effect: ColorOverlay {
                        color: Theme.accent
                    }
                    TapHandler {
                        onTapped: if (root.sysStats.mpris) {
                            root.writeOutput({
                                "action": "mpris_action",
                                "bus_name": root.sysStats.mpris.bus_name,
                                "action_type": "play_pause"
                            });
                        }
                    }
                }

                IconImage {
                    source: Quickshell.iconPath("media-skip-forward-symbolic")
                    implicitSize: 20
                    layer.enabled: true
                    layer.effect: ColorOverlay {
                        color: Theme.fg
                    }
                    TapHandler {
                        onTapped: if (root.sysStats.mpris) {
                            root.writeOutput({
                                "action": "mpris_action",
                                "bus_name": root.sysStats.mpris.bus_name,
                                "action_type": "next"
                            });
                        }
                    }
                }
            }
        }
    }

    MyCombo {
        implicitWidth: parent.width
        model: root.sysStats.volume.sinks
        currentIndex: root.sysStats.volume.current_sink
        onActivated: root.writeOutput({
            "action": "set_sink",
            "sink_id": model[currentIndex].id
        })
    }
}
