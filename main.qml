//@ pragma IconTheme Papirus-Dark
//@ pragma UseQApplication

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick.Effects
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Qt5Compat.GraphicalEffects
import Niri 0.1


ShellRoot {
    id: root
    
    readonly property var colors: {
        "bg": "#1e1e2e",
        "fg": "#cdd6f4",
        "capsule": "#45475a",
        "accent": "#89b4fa",
        "border": "#313244",
        "clock": "#a6e3a1",
    }

    readonly property string globalFont: "JetBrainsMono Nerd Font Propo"

    component MyCapsule: Rectangle {
        width: 32
        height: childrenRect.height + 8
        radius: 6
        color: colors.bg
        border.color: "#45475a"
        border.width: 2
        opacity: 1
    }

    component MyThermo: Rectangle {
        id: thermoRoot
        width: 6
        height: 20
        color: "#585b70"
        // radius: 3

        property real progressValue: 0

        Rectangle {
            width: parent.width
            height: parent.height * thermoRoot.progressValue
            anchors.bottom: parent.bottom
            color: colors.accent
            Behavior on height {
                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
            }
        }
    }

    Item {
        Niri {
            id: niri
            Component.onCompleted: connect()
            onConnected: console.log("Connected to niri")
            onErrorOccurred: function(error) {
                console.error("Error:", error)
            }
        }
    }

    property var sysStats: ({
        "cpu": 0.01,
        "mem": 0.01,
        "temp": 0.01,
        "bat": { "value": "XX", "approx": "050", "charging": true },
        "net": { "up": "X.XX", "up_unit": "B/s", "down": "X.XX", "down_unit": "B/s" },
        "power_profile": "balanced",
        "brightness": { "value": 0.01, "approx": "low" },
        "volume": { "value": 0.01, "approx": "low" }
    })

    function recursiveUpdate(target, source) {
        for (let key in source) {
            // 关键修复：如果 target 缺失这个键，先创建一个空对象防止递归崩溃
            if (typeof source[key] === 'object' && source[key] !== null) {
                if (target[key] === undefined || typeof target[key] !== 'object') {
                    target[key] = {}; 
                }
                root.recursiveUpdate(target[key], source[key]);
            } else {
                target[key] = source[key];
            }
        }
        // 强制触发 UI 更新信号
        root.sysStatsChanged(); 
    }

    Process {
        id: pyMonitor
        command: ["python3", "main.py"]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                if (!data) return;

                try {
                    let cleanData = data.trim();
                    let jsonObject = JSON.parse(cleanData);

                    root.recursiveUpdate(root.sysStats, jsonObject);

                } catch (e) {
                    console.log("JSON: ", e, "content: ", data);
                }
            }
        }
    }

    function writeOutput(event) {
        root.pyMonitor.stdin.write(JSON.stringify(event) + "\n");
    }

    PanelWindow {
        id: panel
        
        anchors {
            right: true
            top: true
            bottom: true
        }

        color: "transparent"

        width: 48

        exclusionMode: ExclusionMode.Exclusive

        RectangularShadow {
            anchors.fill: contentRect
            radius: contentRect.radius
            blur: 5
            spread: 0.1
            color: "#B811111b"
            z: -1
        }
        
        Rectangle {
            id: contentRect
            anchors {
                fill: parent
                topMargin: 8
                bottomMargin: 8
                leftMargin: 4
                rightMargin: 4
            }
            radius: 8

            color: "#B81e1e2e"
            border.color: colors.border
            border.width: 1

            ColumnLayout {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 8
                IconImage {
                    source: Qt.resolvedUrl("nix-snowflake-colours.svg")
                    implicitSize: 28
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Column {
                    Repeater {
                        model: niri.workspaces
                        delegate: MyCapsule {
                            height: model.isFocused? 32 : 20
                            border.width: model.isFocused ? 2 : 0
                            Text {
                                text: model.index
                                anchors.centerIn: parent
                                font.family: globalFont
                                color: colors.fg
                                font.pixelSize: 16
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: niri.focusWorkspaceById(model.id)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 6
                    Layout.fillHeight: true
                    color: "#33FFFFFF" // 20% transparent white track
                    radius: 3

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: parent.height * Math.min(Math.max(0.5, 0), 1)
                        color: "white"
                        radius: parent.radius
            
                        Behavior on height { NumberAnimation { duration: 500 } }
                    }
                }

                MyCapsule {
                    Column {
                        anchors.centerIn: parent
                        spacing: 4

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 4

                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                source: Quickshell.iconPath("cpu-symbolic")
                                implicitSize: 14
                                layer.enabled: true
                                layer.effect: ColorOverlay {
                                    color: colors.accent
                                }
                            }

                            MyThermo {
                                anchors.verticalCenter: parent.verticalCenter
                                progressValue: root.sysStats.cpu
                            }
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 4

                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                source: Quickshell.iconPath("memory-symbolic")
                                implicitSize: 14
                                layer.enabled: true
                                layer.effect: ColorOverlay {
                                    color: colors.accent
                                }
                            }

                            MyThermo {
                                anchors.verticalCenter: parent.verticalCenter
                                progressValue: root.sysStats.mem
                            }
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 4

                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                source: Quickshell.iconPath("sensors-temperature-symbolic")
                                implicitSize: 14
                                layer.enabled: true
                                layer.effect: ColorOverlay {
                                    color: colors.accent
                                }
                            }

                            MyThermo {
                                anchors.verticalCenter: parent.verticalCenter
                                progressValue: root.sysStats.temp
                            }
                        }
                    }
                }

                MyCapsule {
                    id: netCapsule
                    height: 40

                    Column {
                        anchors.centerIn: parent

                        Row {
                            // anchors.verticalCenter: parent.verticalCenter
                            anchors.horizontalCenter: parent.horizontalCenter

                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                implicitSize: 8
                                source: Quickshell.iconPath("go-up-symbolic")
                                layer.enabled: true
                                layer.effect: ColorOverlay {
                                    color: colors.accent
                                }
                            }

                            Column {
                                spacing: -4
                                
                                Text {
                                    text: root.sysStats.net.up
                                    font.pixelSize: 8
                                    color: colors.fg
                                    font.bold: true
                                    font.family: globalFont
                                }
                                Text {
                                    text: root.sysStats.net.up_unit
                                    font.pixelSize: 8
                                    color:colors.fg
                                    font.bold: true
                                    font.family: globalFont
                                }
                            }
                        }

                        Row {
                            // anchors.verticalCenter: parent.verticalCenter
                            anchors.horizontalCenter: parent.horizontalCenter

                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                implicitSize: 8
                                source: Quickshell.iconPath("go-down-symbolic")
                                layer.enabled: true
                                layer.effect: ColorOverlay {
                                    color: colors.accent
                                }
                            }

                            Column {
                                spacing: -4
                                
                                Text {
                                    text: root.sysStats.net.down
                                    font.pixelSize: 8
                                    color: colors.fg
                                    font.bold: true
                                    font.family: globalFont
                                }
                                Text {
                                    text: root.sysStats.net.down_unit
                                    font.pixelSize: 8
                                    color:colors.fg
                                    font.bold: true
                                    font.family: globalFont
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                MyCapsule {
                    height: 42
                    IconImage {
                        anchors.centerIn: parent
                        source: Quickshell.iconPath("window-close") 
                        implicitSize: 32
                        layer.enabled: true
                        layer.effect: ColorOverlay {
                            color: "#f38ba8"
                        }
                    }
                }
                MyCapsule {
                    height: 42
                    IconImage {
                        anchors.centerIn: parent
                        source: Quickshell.iconPath("window-maximize")
                        implicitSize: 32
                        layer.enabled: true
                        layer.effect: ColorOverlay {
                            color: "#f9e2af"
                        }
                    }
                }
                MyCapsule {
                    height: 42
                    IconImage {
                        anchors.centerIn: parent
                        source: Quickshell.iconPath("view-fullscreen")
                        implicitSize: 28
                        layer.enabled: true
                        layer.effect: ColorOverlay {
                            color: "#a6e3a1"
                        }
                    }
                }
                MyCapsule {
                    height: 42
                    IconImage {
                        anchors.centerIn: parent
                        source: Quickshell.iconPath("hand-grab-symbolic")
                        implicitSize: 26
                        layer.enabled: true
                        layer.effect: ColorOverlay {
                            color: "#94e2d5"
                        }
                    }
                }

            }

            ColumnLayout {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8

                MyCapsule {
                    IconImage {
                        anchors.centerIn: parent
                        source: Quickshell.iconPath("notifications-symbolic")
                        implicitSize: 20
                        layer.enabled: true
                        layer.effect: ColorOverlay {
                            color: "#b4befe"
                        }
                    }
                }

                
                MyCapsule {
                    id: batCapsule

                    Column {
                        anchors.centerIn: parent
                        spacing: 4

                        Row {
                            IconImage {
                                source: Quickshell.iconPath(`battery-${root.sysStats.bat.approx}${root.sysStats.bat.charging ? "-charging" : ""}-symbolic`)
                                implicitSize: 17
                                layer.enabled: true
                                layer.effect: ColorOverlay {
                                    color: colors.accent
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                id: batPercentage
                                text: root.sysStats.bat.value
                                font.pixelSize: 10
                                color: colors.fg
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                                font.family: globalFont
                            }
                        }

                        IconImage {
                            anchors.horizontalCenter: parent.horizontalCenter
                            source: Quickshell.iconPath(`power-profile-${root.sysStats.power_profile}-symbolic`)
                            implicitSize: 17
                            layer.enabled: true
                            layer.effect: ColorOverlay {
                                color: colors.accent
                            }
                        }
                    }
                }

                
                MyCapsule {
                    Column {
                        anchors.centerIn: parent
                        spacing: 4

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 4

                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                source: Quickshell.iconPath(`brightness-${root.sysStats.brightness.approx}-symbolic`)
                                implicitSize: 14
                                layer.enabled: true
                                layer.effect: ColorOverlay {
                                    color: colors.accent
                                }
                            }

                            MyThermo {
                                anchors.verticalCenter: parent.verticalCenter
                                progressValue: root.sysStats.brightness.value
                            }
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 4

                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                source: Quickshell.iconPath(`audio-volume-${root.sysStats.volume.approx}-symbolic`)
                                implicitSize: 14
                                layer.enabled: true
                                layer.effect: ColorOverlay {
                                    color: colors.accent
                                }
                            }

                            MyThermo {
                                anchors.verticalCenter: parent.verticalCenter
                                progressValue: root.sysStats.volume.value
                            }
                        }
                    }
                }



                
                MyCapsule {
                    id: trayCapsule
                    Column {
                        anchors.centerIn: parent
                        Repeater {
                            model: SystemTray.items

                            
                            delegate: MouseArea {
                                width: 20
                                height: 20
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                visible: modelData.status !== 0

                                IconImage {
                                    width: modelData.id.includes("Telegram") ? 15 : 20
                                    height: 20
                                    anchors.centerIn: parent
                                    source: modelData.icon || Quickshell.iconPath("image-missing")
                                    layer.enabled: true
                                    layer.effect: ColorOverlay {
                                        color: "#bac2de"
                                    }
                                }

                                function showMenu(mouse) {
                                    const win = QsWindow.window;
                                    const pos = mapToItem(win.contentItem, mouse.x, mouse.y);
                                    modelData.display(win, pos.x, pos.y);
                                }

                                // 处理交互
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.LeftButton) {
                                        modelData.activate(); // 左键激活（通常是打开主界面）
                                    } else if (mouse.button === Qt.RightButton) {
                                        showMenu(mouse)
                                    }
                                }

                                onPressAndHold: (mouse) => showMenu(mouse)
                            }
                        }
                    }
                }


                MyCapsule {
                    id: clockCapsule
                    border.width: 0

                    Column {
                        anchors.centerIn: parent
                        spacing: -10

                        Text {
                            id: hours
                            text: "00"
                            font.pixelSize: 24
                            color: colors.accent
                            font.bold: true
                            Layout.alignment: Qt.AlignHCenter
                            font.family: globalFont
                        }

                        Text {
                            id: minutes
                            text: "00"
                            font.pixelSize: 24
                            color: colors.fg
                            font.bold: true
                            Layout.alignment: Qt.AlignHCenter
                            font.family: globalFont
                        }
                    }
                }

                Timer {
                    interval: 1000 // update every second
                    running: true
                    repeat: true
                    onTriggered: {
                        var date = new Date();
                        hours.text = Qt.formatDateTime(date, "hh");
                        minutes.text = Qt.formatDateTime(date, "mm");
                    }
                }
            }
        }
    }
}
