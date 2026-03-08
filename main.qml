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
import "components"

ShellRoot {
    id: root

    property real lastBrightness: 0.5
    property real lastVolume: 0.5
    property string lastVolumeApprox: ""

    property var sysStats: ({
            "cpu": 0.01,
            "cpus": [],
            "cpu_freq": {
                "current": 0.0,
                "max": 0.0
            },
            "mem": 0.01,
            "swap": 0.01,
            "temp": 0.01,
            "temp_c": 0,
            "bat": {
                "value": "XX",
                "approx": "050",
                "charging": true,
                "time_to_empty": 0,
                "time_to_full": 0,
                "state": 0,
                "energy_rate": 0.0,
                "voltage": 0.0,
                "capacity": 100.0
            },
            "bat_history": [],
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
            "visualizer": new Array(24).fill(0),
            "mpris": null,
            "swayidle": {
                "active": true
            },
            "notifications": {
                "list": [],
                "dnd": false
            }
        })

    function recursiveUpdate(target, source) {
        function update(t, s) {
            for (var key in s) {
                if (s[key] === null) {
                    delete t[key];
                    continue;
                }
                // if target is missing this key or is null, create an empty object first
                if (typeof s[key] === 'object' && !Array.isArray(s[key])) {
                    if (t[key] === undefined || t[key] === null || typeof t[key] !== 'object') {
                        t[key] = {};
                    }
                    update(t[key], s[key]);
                } else {
                    t[key] = s[key];
                }
            }
        }

        update(target, source);
        // Force trigger UI update signal
        root.sysStatsChanged();
    }

    function workspaceList(workspaces) {
        if (!workspaces)
            return [];
        var list = [];
        for (var key in workspaces) {
            if (workspaces[key] === null)
                continue;
            list.push(workspaces[key]);
        }
        return list.sort(function (a, b) {
            return a.idx - b.idx;
        });
    }

    function windowList(windows) {
        if (!windows)
            return [];
        var list = [];
        for (var key in windows) {
            var win = windows[key];
            if (win === null)
                continue;

            // Create a new object manually to avoid modifying the input data
            // and avoid compatibility issues with the spread operator.
            var newWin = {};
            for (var prop in win) {
                newWin[prop] = win[prop];
            }
            newWin.id = key;
            list.push(newWin);
        }
        return list;
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

                    if (jsonObject.notification_popup !== undefined) {
                        if (panel.currentPopup !== notificationPanel) {
                            notificationPopup.show(jsonObject.notification_popup);
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
        function open() {
            command = ["vicinae", "open"];
            running = true;
        }
        function closeAll() {
            command = ["vicinae", "close"];
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
                            vicinae.open();
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
                                            if (modelData.cmd && modelData.cmd[0] === "vicinae") {
                                                panel.currentPopup = vicinae;
                                            } else {
                                                panel.currentPopup = null;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Column {
                    spacing: 4
                    Repeater {
                        model: root.workspaceList(root.sysStats.workspaces)
                        delegate: MyCapsule {
                            id: wsCapsule
                            height: modelData.is_focused ? 32 : 20
                            border.width: modelData.is_focused ? 2 : 0
                            Text {
                                text: modelData.idx
                                anchors.centerIn: parent
                                font.family: Theme.globalFont
                                color: Theme.fg
                                font.pixelSize: 16
                            }

                            TapHandler {
                                onTapped: root.writeOutput({
                                    "action": "focus-workspace",
                                    "index": modelData.idx
                                })
                                onLongPressed: panel.currentPopup = wsPopup
                            }

                            MyPopup {
                                id: wsPopup
                                target: wsCapsule
                                active: panel.currentPopup === wsPopup

                                Column {
                                    spacing: 4
                                    Text {
                                        text: "Workspace " + modelData.idx
                                        font.bold: true
                                        color: Theme.fg
                                        font.family: Theme.globalFont
                                    }

                                    Repeater {
                                        model: modelData.windows ? root.windowList(modelData.windows) : []
                                        delegate: Rectangle {
                                            width: 200
                                            height: 32
                                            color: modelData.is_focused ? Theme.border : "transparent"
                                            radius: 4

                                            Row {
                                                anchors.fill: parent
                                                anchors.margins: 4
                                                spacing: 4

                                                // Focus area: Icon and Title
                                                Item {
                                                    height: parent.height
                                                    width: 160 // Reserve space for close button

                                                    Row {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 4
                                                        spacing: 8
                                                        IconImage {
                                                            source: (modelData.app_id && Quickshell.iconPath(modelData.app_id)) ? Quickshell.iconPath(modelData.app_id) : Quickshell.iconPath("image-missing")
                                                            implicitSize: 20
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                        Text {
                                                            text: modelData.title || "Unknown"
                                                            color: Theme.fg
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            font.pixelSize: 12
                                                            elide: Text.ElideRight
                                                            width: 120
                                                        }
                                                    }

                                                    TapHandler {
                                                        onTapped: {
                                                            root.writeOutput({
                                                                "action": "focus-window",
                                                                "id": parseInt(modelData.id)
                                                            });
                                                            panel.currentPopup = null;
                                                        }
                                                    }
                                                }

                                                // Close button area
                                                Item {
                                                    width: 32
                                                    height: 32
                                                    anchors.verticalCenter: parent.verticalCenter

                                                    IconImage {
                                                        anchors.centerIn: parent
                                                        source: Quickshell.iconPath("window-close-symbolic")
                                                        implicitSize: 20
                                                        layer.enabled: true
                                                        layer.effect: ColorOverlay {
                                                            color: closeHover.hovered ? "#f38ba8" : Theme.capsule
                                                        }
                                                    }

                                                    HoverHandler {
                                                        id: closeHover
                                                    }

                                                    TapHandler {
                                                        onTapped: {
                                                            root.writeOutput({
                                                                "action": "close-window-by-id",
                                                                "id": parseInt(modelData.id)
                                                            });
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
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
                                        Rectangle {
                                            width: (parent.width - (root.sysStats.cpus.length - 1) * parent.spacing) / root.sysStats.cpus.length
                                            height: 12
                                            color: "#313244"
                                            radius: 2
                                            Rectangle {
                                                width: parent.width
                                                height: parent.height * modelData
                                                anchors.bottom: parent.bottom
                                                radius: 2
                                                color: modelData > 0.8 ? "#f38ba8" : (modelData > 0.5 ? "#fab387" : "#a6e3a1")
                                                Behavior on height {
                                                    NumberAnimation {
                                                        duration: 300
                                                    }
                                                }
                                            }
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
                                    Rectangle {
                                        height: 4
                                        Layout.fillWidth: true
                                        color: "#313244"
                                        radius: 2
                                        Rectangle {
                                            height: parent.height
                                            width: parent.width * root.sysStats.mem
                                            color: "#fab387"
                                            radius: 2
                                            Behavior on width {
                                                NumberAnimation {
                                                    duration: 300
                                                }
                                            }
                                        }
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
                                    Rectangle {
                                        height: 4
                                        Layout.fillWidth: true
                                        color: "#313244"
                                        radius: 2
                                        Rectangle {
                                            height: parent.height
                                            width: parent.width * root.sysStats.swap
                                            color: "#f9e2af"
                                            radius: 2
                                            Behavior on width {
                                                NumberAnimation {
                                                    duration: 300
                                                }
                                            }
                                        }
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
                                    Rectangle {
                                        height: 4
                                        Layout.fillWidth: true
                                        color: "#313244"
                                        radius: 2
                                        Rectangle {
                                            height: parent.height
                                            width: parent.width * root.sysStats.temp
                                            color: "#a6e3a1"
                                            radius: 2
                                            Behavior on width {
                                                NumberAnimation {
                                                    duration: 300
                                                }
                                            }
                                        }
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
                                    Rectangle {
                                        height: 4
                                        Layout.fillWidth: true
                                        color: "#313244"
                                        radius: 2
                                        Rectangle {
                                            height: parent.height
                                            width: parent.width * (root.sysStats.cpu_freq.max > 0 ? (root.sysStats.cpu_freq.current / root.sysStats.cpu_freq.max) : 0)
                                            color: "#89b4fa"
                                            radius: 2
                                            Behavior on width {
                                                NumberAnimation {
                                                    duration: 300
                                                }
                                            }
                                        }
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
                            panel.currentPopup = notificationPanel;
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
                                    onActivated: writeOutput({
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
                                        onTapped: writeOutput({
                                            "action": "toggle_swayidle"
                                        })
                                    }
                                }
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
                            onMoved: writeOutput({
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
                                        onTapped: writeOutput({
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
                            onMoved: writeOutput({
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
                                    model: root.sysStats.visualizer.length
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
                                            source: root.sysStats.mpris ? root.sysStats.mpris.art_url : ""
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
                                                writeOutput({
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
                                                writeOutput({
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
                                                writeOutput({
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
                        MyCalendar {}
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

    NotificationPopup {
        id: notificationPopup
    }

    NotificationPanel {
        id: notificationPanel
        target: notificationCapsule
        active: panel.currentPopup === notificationPanel
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
