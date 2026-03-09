import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "."

MyPopup {
    id: batteryPopupRoot
    preferredWidth: 270

    ColumnLayout {
        width: parent.width
        spacing: 15

        Text {
            text: "Battery & Power"
            color: Theme.fg
            font.bold: true
            font.family: Theme.globalFont
            font.pixelSize: 14
            Layout.bottomMargin: 2
        }

        // --- Detailed Status ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            IconImage {
                source: Quickshell.iconPath(`battery-${root.sysStats.bat.approx}${root.sysStats.bat.charging ? "-charging" : ""}-symbolic`)
                implicitSize: 24
                layer.enabled: true
                layer.effect: ColorOverlay {
                    color: Theme.accent
                }
            }
            ColumnLayout {
                spacing: 0
                Text {
                    text: root.sysStats.bat.value + "%"
                    color: Theme.fg
                    font.pixelSize: 18
                    font.bold: true
                    font.family: Theme.globalFont
                }
                Text {
                    text: {
                        if (root.sysStats.bat.state === 1)
                            return "Charging";
                        if (root.sysStats.bat.state === 2)
                            return "Discharging";
                        if (root.sysStats.bat.state === 4)
                            return "Fully Charged";
                        return "Unknown State";
                    }
                    color: Theme.fg
                    font.pixelSize: 11
                    font.family: Theme.globalFont
                    opacity: 0.8
                }
            }
            Item {
                Layout.fillWidth: true
            }
            Text {
                text: {
                    let time = 0;
                    if (root.sysStats.bat.state === 1)
                        time = root.sysStats.bat.time_to_full;
                    else if (root.sysStats.bat.state === 2)
                        time = root.sysStats.bat.time_to_empty;
                    if (time <= 0)
                        return "";
                    let h = Math.floor(time / 3600);
                    let m = Math.floor((time % 3600) / 60);
                    return `${h}h ${m}m`;
                }
                color: Theme.fg
                font.pixelSize: 13
                font.bold: true
                font.family: Theme.globalFont
            }
        }

        // --- Battery History (24 Vertical Bars) ---
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            Layout.topMargin: 4
            Text {
                text: "Last 24 Hours"
                color: Theme.fg
                font.pixelSize: 10
                font.family: Theme.globalFont
                opacity: 0.6
                Layout.bottomMargin: 4
            }
            RowLayout {
                Layout.fillWidth: true
                height: 48
                spacing: 2
                Repeater {
                    model: root.sysStats.bat_history
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Theme.border
                        radius: 1

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: Math.max(2, parent.height * (modelData / 100.0))
                            color: Theme.accent
                            radius: 1
                            // Recent values are fully opaque, older ones slightly fade
                            opacity: 0.4 + (index / 23.0) * 0.4
                        }
                    }
                }
            }
        }

        // --- Detailed Stats ---
        GridLayout {
            columns: 2
            Layout.fillWidth: true
            rowSpacing: 8
            columnSpacing: 16
            Layout.topMargin: -4

            // Row 1: Energy Rate & Energy
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                IconImage {
                    source: Quickshell.iconPath("speedometer-symbolic")
                    implicitSize: 14
                    layer.enabled: true
                    layer.effect: ColorOverlay {
                        color: Theme.accent
                    }
                }
                Text {
                    text: "Rate"
                    color: Theme.fg
                    font.pixelSize: 10
                    font.family: Theme.globalFont
                    opacity: 0.7
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    text: root.sysStats.bat.energy_rate + " W"
                    color: Theme.fg
                    font.pixelSize: 10
                    font.bold: true
                    font.family: Theme.globalFont
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                IconImage {
                    source: Quickshell.iconPath("battery-symbolic")
                    implicitSize: 14
                    layer.enabled: true
                    layer.effect: ColorOverlay {
                        color: Theme.accent
                    }
                }
                Text {
                    text: "Energy"
                    color: Theme.fg
                    font.pixelSize: 10
                    font.family: Theme.globalFont
                    opacity: 0.7
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    text: root.sysStats.bat.energy + " Wh"
                    color: Theme.fg
                    font.pixelSize: 10
                    font.bold: true
                    font.family: Theme.globalFont
                }
            }

            // Row 2: Voltage & Health
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                IconImage {
                    source: Quickshell.iconPath("bolt-symbolic")
                    implicitSize: 14
                    layer.enabled: true
                    layer.effect: ColorOverlay {
                        color: Theme.accent
                    }
                }
                Text {
                    text: "Voltage"
                    color: Theme.fg
                    font.pixelSize: 10
                    font.family: Theme.globalFont
                    opacity: 0.7
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    text: root.sysStats.bat.voltage + " V"
                    color: Theme.fg
                    font.pixelSize: 10
                    font.bold: true
                    font.family: Theme.globalFont
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                IconImage {
                    source: Quickshell.iconPath("view-refresh-symbolic")
                    implicitSize: 14
                    layer.enabled: true
                    layer.effect: ColorOverlay {
                        color: Theme.accent
                    }
                }
                Text {
                    text: "Health"
                    color: Theme.fg
                    font.pixelSize: 10
                    font.family: Theme.globalFont
                    opacity: 0.7
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    text: root.sysStats.bat.capacity + " %"
                    color: Theme.fg
                    font.pixelSize: 10
                    font.bold: true
                    font.family: Theme.globalFont
                }
            }
        }

        // --- Power Mode Selector ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Layout.topMargin: 4
            IconImage {
                source: Quickshell.iconPath(`power-profile-${root.sysStats.power_profile}-symbolic`)
                implicitSize: 16
                layer.enabled: true
                layer.effect: ColorOverlay {
                    color: Theme.accent
                }
            }
            MyCombo {
                Layout.fillWidth: true
                model: [
                    {
                        name: "Power Saver",
                        id: "power-saver"
                    },
                    {
                        name: "Balanced",
                        id: "balanced"
                    },
                    {
                        name: "Performance",
                        id: "performance"
                    }
                ]
                currentIndex: {
                    let prof = root.sysStats.power_profile;
                    if (prof === "power-saver")
                        return 0;
                    if (prof === "balanced")
                        return 1;
                    if (prof === "performance")
                        return 2;
                    return 1;
                }
                onActivated: root.writeOutput({
                    "action": "set_power_profile",
                    "profile": model[currentIndex].id
                })
            }
        }

        // --- Idle Inhibit Toggle ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            IconImage {
                source: Quickshell.iconPath(`my-caffeine-${root.sysStats.swayidle.active ? "off" : "on"}-symbolic`)
                implicitSize: 16
                layer.enabled: true
                layer.effect: ColorOverlay {
                    color: Theme.accent
                }
            }
            Text {
                text: "Idle Inhibit"
                color: Theme.fg
                font.pixelSize: 11
                font.family: Theme.globalFont
                Layout.fillWidth: true
            }
            Rectangle {
                width: 36
                height: 18
                radius: 9
                color: root.sysStats.swayidle.active ? "#313244" : Theme.accent
                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }
                Rectangle {
                    width: 14
                    height: 14
                    radius: 7
                    color: Theme.fg
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.sysStats.swayidle.active ? 2 : 20
                    Behavior on x {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }
                    }
                }
                TapHandler {
                    onTapped: root.writeOutput({
                        "action": "toggle_swayidle"
                    })
                }
            }
        }
    }
}
