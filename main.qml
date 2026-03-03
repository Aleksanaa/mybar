//@ pragma IconTheme Papirus-Dark
//@ pragma UseQApplication

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick.Effects
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Qt5Compat.GraphicalEffects
import Niri 0.1
import "components"

ShellRoot {
    id: root

    property real lastBrightness: 0.5
    property real lastVolume: 0.5
    property string lastVolumeApprox: ""

    Item {
        Niri {
            id: niri
            Component.onCompleted: connect()
            onConnected: console.log("Connected to niri")
            onErrorOccurred: function (error) {
                console.error("Error:", error);
            }
        }
    }

    property var sysStats: ({
            "cpu": 0.01,
            "mem": 0.01,
            "temp": 0.01,
            "bat": {
                "value": "XX",
                "approx": "050",
                "charging": true,
                "time_to_empty": 0,
                "time_to_full": 0,
                "state": 0
            },
            "net": {
                "up": "X.XX",
                "up_unit": "B/s",
                "up_raw": 0.0,
                "down": "X.XX",
                "down_unit": "B/s",
                "down_raw": 0.0
            },
            "power_profile": "balanced",
            "brightness": {
                "value": 0.01,
                "approx": "low"
            },
            "volume": {
                "value": 0.01,
                "approx": "low",
                "sinks": [],
                "current_sink": 0
            },
            "swayidle": {
                "active": true
            }
        })

    function recursiveUpdate(target, source) {
        for (let key in source) {
            // if target is missing this key, create an empty object first to prevent recursive crashes
            if (typeof source[key] === 'object' && source[key] !== null) {
                if (target[key] === undefined || typeof target[key] !== 'object') {
                    target[key] = {};
                }
                root.recursiveUpdate(target[key], source[key]);
            } else {
                target[key] = source[key];
            }
        }
        // Force trigger UI update signal
        root.sysStatsChanged();
    }

    Process {
        id: pyMonitor
        command: ["python3", "main.py"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                if (!data)
                    return;

                try {
                    let cleanData = data.trim();
                    let jsonObject = JSON.parse(cleanData);

                    root.recursiveUpdate(root.sysStats, jsonObject);

                    // Check for OSD updates after full packet update
                    if (jsonObject.brightness !== undefined) {
                        if (Math.abs(root.sysStats.brightness.value - lastBrightness) > 0.005) {
                            if (panel.currentPopup !== adjustDetailPopup) {
                                osd.show("brightness", root.sysStats.brightness.value, root.sysStats.brightness.approx);
                            }
                            lastBrightness = root.sysStats.brightness.value;
                        }
                    }

                    if (jsonObject.volume !== undefined) {
                        let volumeChanged = Math.abs(root.sysStats.volume.value - lastVolume) > 0.005;
                        let muteChanged = root.sysStats.volume.approx !== lastVolumeApprox;

                        if (volumeChanged || muteChanged) {
                            if (panel.currentPopup !== adjustDetailPopup) {
                                osd.show("volume", root.sysStats.volume.value, root.sysStats.volume.approx);
                            }
                            lastVolume = root.sysStats.volume.value;
                            lastVolumeApprox = root.sysStats.volume.approx;
                        }
                    }
                } catch (e) {
                    console.log("JSON: ", e, "content: ", data);
                }
            }
        }
    }

    Process {
        id: vicinae
        command: ["vicinae", "toggle"]
        function closeAll() {
            running = true;
        }
    }

    Process {
        id: swaync
        command: ["swaync-client", "-t"]
        function closeAll() {
            running = true;
        }
    }

    function writeOutput(event) {
        pyMonitor.write(JSON.stringify(event) + "\n");
    }

    PanelWindow {
        id: panel

        anchors {
            right: true
            top: true
            bottom: true
        }

        color: "transparent"

        implicitWidth: 44

        exclusionMode: ExclusionMode.Exclusive

        // Holds the currently visible popup object. null means none are open.
        property QtObject currentPopup: null

        MouseArea {
            anchors.fill: parent
            enabled: panel.currentPopup !== null
            z: 998
            onPressed: {
                if (panel.currentPopup) {
                    if (typeof panel.currentPopup.closeAll === "function") {
                        panel.currentPopup.closeAll();
                    }
                    panel.currentPopup = null;
                }
            } // Clearing this closes the popup
        }

        // RectangularShadow {
        //     anchors.fill: contentRect
        //     radius: contentRect.radius
        //     blur: 5
        //     spread: 0.1
        //     color: "#B811111b"
        //     z: -1
        // }

        TrayMenu {
            id: globalTrayMenu
            backgroundColor: Theme.bg
            borderColor: Theme.border
            textColor: Theme.fg
            highlightColor: Theme.border
            borderRadius: 8
            visible: panel.currentPopup === globalTrayMenu
        }

        Rectangle {
            id: contentRect
            anchors {
                fill: parent
                // topMargin: 8
                // bottomMargin: 8
                // leftMargin: 4
                // rightMargin: 8
            }
            radius: 0

            color: "#ef1e1e2e"
            border.color: Theme.border
            border.width: 1

            ColumnLayout {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 8
                IconImage {
                    id: nixLogo
                    source: Qt.resolvedUrl("nix-snowflake-colours.svg")
                    implicitSize: 28
                    Layout.alignment: Qt.AlignHCenter

                    TapHandler {
                        onTapped: {
                            vicinae.running = true;
                            panel.currentPopup = vicinae;
                        }
                        onLongPressed: panel.currentPopup = appMenuPopup
                    }

                    MyPopup {
                        id: appMenuPopup
                        target: nixLogo
                        active: panel.currentPopup === appMenuPopup

                        Column {
                            spacing: 4
                            Repeater {
                                model: [
                                    {
                                        text: "Applications",
                                        icon: "applications-all-symbolic",
                                        cmd: ["vicinae", "vicinae://extensions/vicinae/system/browse-apps"]
                                    },
                                    {
                                        text: "Clipboard",
                                        icon: "edit-paste-symbolic",
                                        cmd: ["vicinae", "vicinae://extensions/vicinae/clipboard/history"]
                                    },
                                    {
                                        text: "Switch Windows",
                                        icon: "focus-windows-symbolic",
                                        cmd: ["vicinae", "vicinae://extensions/vicinae/wm/switch-windows"]
                                    },
                                    {
                                        text: "Select Emojis",
                                        icon: "emoji-people-symbolic",
                                        cmd: ["vicinae", "vicinae://extensions/vicinae/core/search-emojis"]
                                    },
                                    {
                                        text: "Terminal",
                                        icon: "utilities-terminal-symbolic",
                                        cmd: ["alacritty", "msg", "create-window"]
                                    },
                                    {
                                        text: "File Manager",
                                        icon: "system-file-manager-symbolic",
                                        cmd: ["nautilus", "--new-window"]
                                    }
                                ]
                                Rectangle {
                                    width: 200
                                    height: 32
                                    color: itemHover.hovered ? Theme.border : "transparent"
                                    radius: 4
                                    Process {
                                        id: itemRunner
                                        command: modelData.cmd
                                    }
                                    Row {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 8
                                        IconImage {
                                            source: Quickshell.iconPath(modelData.icon)
                                            implicitSize: 20
                                            anchors.verticalCenter: parent.verticalCenter
                                            layer.enabled: true
                                            layer.effect: ColorOverlay {
                                                color: Theme.accent
                                            }
                                        }
                                        Text {
                                            text: modelData.text
                                            color: Theme.fg
                                            anchors.verticalCenter: parent.verticalCenter
                                            font.pixelSize: 14
                                        }
                                    }

                                    HoverHandler {
                                        id: itemHover
                                    }

                                    TapHandler {
                                        onTapped: {
                                            itemRunner.running = true;
                                            panel.currentPopup = null;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Column {
                    Repeater {
                        model: niri.workspaces
                        delegate: MyCapsule {
                            height: model.isFocused ? 32 : 20
                            border.width: model.isFocused ? 2 : 0
                            Text {
                                text: model.index
                                anchors.centerIn: parent
                                font.family: Theme.globalFont
                                color: Theme.fg
                                font.pixelSize: 16
                            }
                            TapHandler {
                                onTapped: niri.focusWorkspaceById(model.id)
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
                        implicitHeight: parent.height * Math.min(Math.max(0.5, 0), 1)
                        color: "white"
                        radius: parent.radius

                        Behavior on height {
                            NumberAnimation {
                                duration: 500
                            }
                        }
                    }
                }

                MyCapsule {
                    id: monitorCapsule
                    implicitHeight: monitorColumn.implicitHeight + 8

                    Column {
                        id: monitorColumn
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
                                    color: Theme.accent
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
                                    color: Theme.accent
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
                                    color: Theme.accent
                                }
                            }

                            MyThermo {
                                anchors.verticalCenter: parent.verticalCenter
                                progressValue: root.sysStats.temp
                            }
                        }
                    }

                    TapHandler {
                        onTapped: panel.currentPopup = monitorPopup
                    }

                    MyPopup {
                        id: monitorPopup
                        target: monitorCapsule
                        active: panel.currentPopup === monitorPopup

                        Column {
                            width: parent.width
                            spacing: 12

                            Text {
                                text: "System Statistics"
                                color: Theme.fg
                                font.bold: true
                                font.family: Theme.globalFont
                                font.pixelSize: 14
                            }

                            Column {
                                width: parent.width
                                spacing: 4
                                Text {
                                    text: "CPU: " + Math.round(root.sysStats.cpu * 100) + "%"
                                    color: Theme.fg
                                    font.pixelSize: 12
                                    font.family: Theme.globalFont
                                }
                                LineChart {
                                    width: parent.width
                                    height: 40
                                    value: root.sysStats.cpu
                                    lineColor: "#f38ba8"
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 4
                                Text {
                                    text: "Memory: " + Math.round(root.sysStats.mem * 100) + "%"
                                    color: Theme.fg
                                    font.pixelSize: 12
                                    font.family: Theme.globalFont
                                }
                                LineChart {
                                    width: parent.width
                                    height: 40
                                    value: root.sysStats.mem
                                    lineColor: "#fab387"
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 4
                                Text {
                                    text: "Temperature: " + Math.round(root.sysStats.temp * 100) + "°C"
                                    color: Theme.fg
                                    font.pixelSize: 12
                                    font.family: Theme.globalFont
                                }
                                LineChart {
                                    width: parent.width
                                    height: 40
                                    value: root.sysStats.temp
                                    lineColor: "#f9e2af"
                                }
                            }
                        }
                    }
                }

                MyCapsule {
                    id: netCapsule
                    implicitHeight: 40

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
                                    color: Theme.accent
                                }
                            }

                            Column {
                                spacing: -4

                                Text {
                                    text: root.sysStats.net.up
                                    font.pixelSize: 8
                                    color: Theme.fg
                                    font.bold: true
                                    font.family: Theme.globalFont
                                }
                                Text {
                                    text: root.sysStats.net.up_unit
                                    font.pixelSize: 8
                                    color: Theme.fg
                                    font.bold: true
                                    font.family: Theme.globalFont
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
                                    color: Theme.accent
                                }
                            }

                            Column {
                                spacing: -4

                                Text {
                                    text: root.sysStats.net.down
                                    font.pixelSize: 8
                                    color: Theme.fg
                                    font.bold: true
                                    font.family: Theme.globalFont
                                }
                                Text {
                                    text: root.sysStats.net.down_unit
                                    font.pixelSize: 8
                                    color: Theme.fg
                                    font.bold: true
                                    font.family: Theme.globalFont
                                }
                            }
                        }
                    }

                    TapHandler {
                        onTapped: panel.currentPopup = netPopup
                    }

                    MyPopup {
                        id: netPopup
                        target: netCapsule
                        active: panel.currentPopup === netPopup

                        Column {
                            width: parent.width
                            spacing: 12

                            Text {
                                text: "Network Usage"
                                color: Theme.fg
                                font.bold: true
                                font.family: Theme.globalFont
                                font.pixelSize: 14
                            }

                            Column {
                                width: parent.width
                                spacing: 4
                                Text {
                                    text: "Upload: " + root.sysStats.net.up + " " + root.sysStats.net.up_unit
                                    color: Theme.fg
                                    font.pixelSize: 12
                                    font.family: Theme.globalFont
                                }
                                LineChart {
                                    width: parent.width
                                    height: 40
                                    value: root.sysStats.net.up_raw
                                    lineColor: "#a6e3a1"
                                    autoScale: true
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 4
                                Text {
                                    text: "Download: " + root.sysStats.net.down + " " + root.sysStats.net.down_unit
                                    color: Theme.fg
                                    font.pixelSize: 12
                                    font.family: Theme.globalFont
                                }
                                LineChart {
                                    width: parent.width
                                    height: 40
                                    value: root.sysStats.net.down_raw
                                    lineColor: "#89b4fa"
                                    autoScale: true
                                    inverted: true
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                MyCapsule {
                    implicitHeight: 42
                    border.color: th1.pressed ? "#f38ba8" : Theme.capsule
                    IconImage {
                        anchors.centerIn: parent
                        source: Quickshell.iconPath("window-close")
                        implicitSize: 32
                        layer.enabled: true
                        layer.effect: ColorOverlay {
                            color: "#f38ba8"
                        }
                    }
                    TapHandler {
                        id: th1
                        onTapped: writeOutput({
                            "action": "close-window"
                        })
                    }
                }
                MyCapsule {
                    implicitHeight: 42
                    border.color: th2.pressed ? "#f9e2af" : Theme.capsule
                    IconImage {
                        anchors.centerIn: parent
                        source: Quickshell.iconPath("window-maximize")
                        implicitSize: 32
                        layer.enabled: true
                        layer.effect: ColorOverlay {
                            color: "#f9e2af"
                        }
                    }
                    TapHandler {
                        id: th2
                        onTapped: writeOutput({
                            "action": "maximize-column"
                        })
                    }
                }
                MyCapsule {
                    implicitHeight: 42
                    border.color: th3.pressed ? "#a6e3a1" : Theme.capsule
                    IconImage {
                        anchors.centerIn: parent
                        source: Quickshell.iconPath("view-fullscreen")
                        implicitSize: 28
                        layer.enabled: true
                        layer.effect: ColorOverlay {
                            color: "#a6e3a1"
                        }
                    }
                    TapHandler {
                        id: th3
                        onTapped: writeOutput({
                            "action": "toggle-fullscreen"
                        })
                    }
                }
                MyCapsule {
                    implicitHeight: 42
                    border.color: th4.pressed ? "#94e2d5" : Theme.capsule
                    IconImage {
                        anchors.centerIn: parent
                        source: Quickshell.iconPath("hand-grab-symbolic")
                        implicitSize: 26
                        layer.enabled: true
                        layer.effect: ColorOverlay {
                            color: "#94e2d5"
                        }
                    }
                    TapHandler {
                        id: th4
                        onTapped: writeOutput({
                            "action": "toggle_super"
                        })
                    }
                }
            }

            ColumnLayout {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8

                MyCapsule {
                    id: notificationCapsule
                    implicitHeight: 32
                    IconImage {
                        anchors.centerIn: parent
                        source: Quickshell.iconPath("notifications-symbolic")
                        implicitSize: 20
                        layer.enabled: true
                        layer.effect: ColorOverlay {
                            color: "#b4befe"
                        }
                    }

                    TapHandler {
                        onTapped: {
                            swaync.running = true;
                            panel.currentPopup = swaync;
                        }
                    }
                }

                MyCapsule {
                    id: batCapsule
                    implicitHeight: batColumn.implicitHeight + 8

                    Column {
                        id: batColumn
                        anchors.centerIn: parent
                        spacing: 4

                        Row {
                            IconImage {
                                source: Quickshell.iconPath(`battery-${root.sysStats.bat.approx}${root.sysStats.bat.charging ? "-charging" : ""}-symbolic`)
                                implicitSize: 17
                                layer.enabled: true
                                layer.effect: ColorOverlay {
                                    color: Theme.accent
                                }
                            }
                            Text {
                                id: batPercentage
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.sysStats.bat.value
                                font.pixelSize: 10
                                color: Theme.fg
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                                font.family: Theme.globalFont
                                visible: root.sysStats.bat.value != 100
                            }
                        }

                        IconImage {
                            anchors.horizontalCenter: parent.horizontalCenter
                            source: Quickshell.iconPath(`power-profile-${root.sysStats.power_profile}-symbolic`)
                            implicitSize: 17
                            layer.enabled: true
                            layer.effect: ColorOverlay {
                                color: Theme.accent
                            }
                        }

                        IconImage {
                            anchors.horizontalCenter: parent.horizontalCenter
                            source: Quickshell.iconPath(`my-caffeine-${root.sysStats.swayidle.active ? "off" : "on"}-symbolic`)
                            implicitSize: 17
                            layer.enabled: true
                            layer.effect: ColorOverlay {
                                color: Theme.accent
                            }
                        }
                    }

                    TapHandler {
                        onTapped: panel.currentPopup = batDetailPopup
                    }

                    MyPopup {
                        id: batDetailPopup
                        target: batCapsule
                        active: panel.currentPopup === batDetailPopup

                        Row {
                            spacing: 5
                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                source: Quickshell.iconPath(`battery-${root.sysStats.bat.approx}${root.sysStats.bat.charging ? "-charging" : ""}-symbolic`)
                                implicitSize: 16
                                layer.enabled: true
                                layer.effect: ColorOverlay {
                                    color: Theme.accent
                                }
                            }
                            Text {
                                text: `Battery: ${root.sysStats.bat.value}%`
                                color: Theme.fg
                            }
                        }

                        Row {
                            spacing: 5
                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                source: Quickshell.iconPath("preferences-system-time-symbolic")
                                implicitSize: 16
                                layer.enabled: true
                                layer.effect: ColorOverlay {
                                    color: Theme.accent
                                }
                            }
                            Text {
                                text: {
                                    let timeText = "";
                                    if (root.sysStats.bat.state === 1 && root.sysStats.bat.time_to_full > 0) {
                                        let hours = Math.floor(root.sysStats.bat.time_to_full / 3600);
                                        let minutes = Math.floor((root.sysStats.bat.time_to_full % 3600) / 60);
                                        timeText = `Full in ${hours} hours ${minutes} minutes`;
                                    } else if (root.sysStats.bat.state === 2 && root.sysStats.bat.time_to_empty > 0) {
                                        let hours = Math.floor(root.sysStats.bat.time_to_empty / 3600);
                                        let minutes = Math.floor((root.sysStats.bat.time_to_empty % 3600) / 60);
                                        timeText = `Empty in ${hours} hours ${minutes} minutes`;
                                    } else if (root.sysStats.bat.state === 4) {
                                        timeText = "Fully charged";
                                    } else {
                                        timeText = "Estimating...";
                                    }
                                    return timeText;
                                }
                                color: Theme.fg
                            }
                        }

                        RowLayout {
                            width: parent.width
                            spacing: 5
                            IconImage {
                                Layout.alignment: Qt.AlignVCenter
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
                                onActivated: writeOutput({
                                    "action": "set_power_profile",
                                    "profile": model[currentIndex].id
                                })
                            }
                        }

                        Item {
                            width: parent.width
                            height: inhibitRow.implicitHeight
                            Row {
                                id: inhibitRow
                                spacing: 5
                                IconImage {
                                    anchors.verticalCenter: parent.verticalCenter
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
                                }
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 40
                                height: 20
                                radius: 10
                                color: root.sysStats.swayidle.active ? Theme.bg : Theme.accent
                                border.color: Theme.border
                                border.width: 1

                                Rectangle {
                                    width: 16
                                    height: 16
                                    radius: 8
                                    color: Theme.fg
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: root.sysStats.swayidle.active ? 2 : 22
                                    Behavior on x {
                                        NumberAnimation {
                                            duration: 100
                                        }
                                    }
                                }
                            }

                            TapHandler {
                                onTapped: writeOutput({
                                    "action": "toggle_swayidle"
                                })
                            }
                        }
                    }
                }

                MyCapsule {
                    id: adjustCapsule
                    implicitHeight: adjustColumn.implicitHeight + 8
                    Column {
                        id: adjustColumn
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
                                    color: Theme.accent
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
                                    color: Theme.accent
                                }
                            }

                            MyThermo {
                                anchors.verticalCenter: parent.verticalCenter
                                progressValue: root.sysStats.volume.value
                            }
                        }
                    }

                    TapHandler {
                        onTapped: panel.currentPopup = adjustDetailPopup
                    }

                    MyPopup {
                        id: adjustDetailPopup
                        target: adjustCapsule
                        active: panel.currentPopup === adjustDetailPopup

                        Item {
                            width: parent.width
                            height: brightnessLabelRow.implicitHeight
                            Row {
                                id: brightnessLabelRow
                                spacing: 5
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
                                }
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: `${Math.round(root.sysStats.brightness.value * 100)}%`
                                color: Theme.fg
                            }
                        }

                        MySlider {
                            implicitWidth: parent.width
                            value: root.sysStats.brightness.value
                            onMoved: writeOutput({
                                "action": "set_brightness",
                                "value": value
                            })
                        }

                        Item {
                            width: parent.width
                            height: volumeLabelRow.implicitHeight
                            Row {
                                id: volumeLabelRow
                                spacing: 5
                                IconImage {
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: Quickshell.iconPath(`audio-volume-${root.sysStats.volume.approx}-symbolic`)
                                    implicitSize: 16
                                    layer.enabled: true
                                    layer.effect: ColorOverlay {
                                        color: Theme.accent
                                    }
                                    TapHandler {
                                        onTapped: writeOutput({
                                            "action": "toggle_mute"
                                        })
                                    }
                                }
                                Text {
                                    text: "Volume:"
                                    color: Theme.fg
                                }
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: `${Math.round(root.sysStats.volume.value * 100)}%`
                                color: Theme.fg
                            }
                        }

                        MySlider {
                            implicitWidth: parent.width
                            value: root.sysStats.volume.value
                            onMoved: writeOutput({
                                "action": "set_volume",
                                "value": value
                            })
                        }

                        MyCombo {
                            implicitWidth: parent.width
                            model: root.sysStats.volume.sinks
                            currentIndex: root.sysStats.volume.current_sink
                            onActivated: writeOutput({
                                "action": "set_sink",
                                "sink_id": model[currentIndex].id
                            })
                        }
                    }
                }

                MyCapsule {
                    id: trayCapsule
                    implicitHeight: Math.max(trayColumn.implicitHeight + 8, 10)

                    Column {
                        id: trayColumn
                        anchors.centerIn: parent
                        Repeater {
                            model: SystemTray.items

                            delegate: MouseArea {
                                implicitWidth: 20
                                implicitHeight: 20
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                visible: modelData.status !== 0

                                IconImage {
                                    implicitWidth: modelData.id.includes("Telegram") ? 16 : 20
                                    implicitHeight: 20
                                    anchors.centerIn: parent
                                    source: modelData.icon || Quickshell.iconPath("image-missing")
                                    layer.enabled: true
                                    layer.effect: ColorOverlay {
                                        color: "#bac2de"
                                    }
                                }

                                function showMenu(mouse) {
                                    panel.currentPopup = globalTrayMenu;
                                    globalTrayMenu.menuHandle = modelData.menu;
                                    globalTrayMenu.showAt(parent, panel.screen);
                                }

                                // Handle interaction
                                onClicked: mouse => {
                                    if (mouse.button === Qt.LeftButton) {
                                        modelData.activate(); // Left-click to activate (usually opens the main interface)
                                    } else if (mouse.button === Qt.RightButton) {
                                        showMenu(mouse);
                                    }
                                }

                                onPressAndHold: mouse => showMenu(mouse)
                            }
                        }
                    }
                }

                MyCapsule {
                    id: clockCapsule
                    border.width: 0
                    implicitHeight: clockColumn.implicitHeight + 8

                    Column {
                        id: clockColumn
                        anchors.centerIn: parent
                        spacing: -10

                        Text {
                            id: hours
                            text: "00"
                            font.pixelSize: 24
                            color: Theme.accent
                            font.bold: true
                            Layout.alignment: Qt.AlignHCenter
                            font.family: Theme.globalFont
                        }

                        Text {
                            id: minutes
                            text: "00"
                            font.pixelSize: 24
                            color: Theme.fg
                            font.bold: true
                            Layout.alignment: Qt.AlignHCenter
                            font.family: Theme.globalFont
                        }
                    }

                    TapHandler {
                        onTapped: panel.currentPopup = clockDetailPopup
                    }

                    MyPopup {
                        id: clockDetailPopup
                        target: clockCapsule
                        active: panel.currentPopup === clockDetailPopup
                        implicitHeight: 240
                        Text {
                            text: Qt.formatDateTime(new Date(), "dd, MM, yyyy")
                            color: Theme.fg
                            font.pixelSize: 20
                            font.family: Theme.globalFont
                            Layout.alignment: Qt.AlignHCenter
                        }

                        DayOfWeekRow {
                            locale: Qt.locale("zh_CN")
                            width: parent.width

                            delegate: Text {
                                text: model.narrowName
                                font.bold: true
                                font.pixelSize: 14
                                font.family: Theme.globalFont
                                color: Theme.accent
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        MonthGrid {
                            id: grid
                            width: parent.width
                            locale: Qt.locale("zh_CN")

                            month: new Date().getMonth()
                            year: new Date().getFullYear()

                            delegate: Rectangle {
                                implicitWidth: 25
                                implicitHeight: 25
                                radius: 4
                                color: "transparent"
                                border.width: model.today ? 1 : 0
                                border.color: Theme.fg

                                Text {
                                    anchors.centerIn: parent
                                    text: model.day
                                    opacity: model.month === grid.month ? 1.0 : 0.5
                                    color: model.today ? Theme.accent : Theme.fg
                                    font.pixelSize: 14
                                }
                            }
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

    OSDPopup {
        id: osd
        onMoved: (type, value) => {
            if (type === "brightness") {
                writeOutput({
                    "action": "set_brightness",
                    "value": value
                });
            } else {
                writeOutput({
                    "action": "set_volume",
                    "value": value
                });
            }
        }
    }
}
