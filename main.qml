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

        // Explicitly trigger signals for top-level keys updated
        for (var key in source) {
            if (target.hasOwnProperty(key + "Changed")) {
                target[key + "Changed"]();
            }
        }

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

                    if (jsonObject.notifications !== undefined) {
                        notificationPanel.updateTrigger++;
                    }

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

                    if (jsonObject.close_notification_popup !== undefined) {
                        notificationPopup.hideIfIdMatches(jsonObject.close_notification_popup);
                    }

                    if (jsonObject.clear_notification_popup !== undefined) {
                        notificationPopup.visible = false;
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
                                                            source: Theme.resolveAppIcon(modelData.app_id, "", "image-missing")
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

                            MyPillBar {
                                anchors.verticalCenter: parent.verticalCenter
                                progress: root.sysStats.cpu
                                vertical: true
                                implicitHeight: 20
                                implicitWidth: 6
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

                            MyPillBar {
                                anchors.verticalCenter: parent.verticalCenter
                                progress: root.sysStats.mem
                                vertical: true
                                implicitHeight: 20
                                implicitWidth: 6
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

                            MyPillBar {
                                anchors.verticalCenter: parent.verticalCenter
                                progress: root.sysStats.temp
                                vertical: true
                                implicitHeight: 20
                                implicitWidth: 6
                            }
                        }
                    }

                    TapHandler {
                        onTapped: panel.currentPopup = monitorPopup
                    }

                    MonitorPopup {
                        id: monitorPopup
                        target: monitorCapsule
                        active: panel.currentPopup === monitorPopup
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

                    NetworkPopup {
                        id: netPopup
                        target: netCapsule
                        active: panel.currentPopup === netPopup
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
                        source: Quickshell.iconPath(`notifications${root.sysStats.notifications.dnd ? "-disabled" : ""}-symbolic`)
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
                        onLongPressed: root.writeOutput({
                            "action": "toggle-dnd"
                        })
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

                    BatteryPopup {
                        id: batDetailPopup
                        target: batCapsule
                        active: panel.currentPopup === batDetailPopup
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

                            MyPillBar {
                                anchors.verticalCenter: parent.verticalCenter
                                progress: root.sysStats.brightness.value
                                vertical: true
                                implicitHeight: 20
                                implicitWidth: 6
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

                            MyPillBar {
                                anchors.verticalCenter: parent.verticalCenter
                                progress: root.sysStats.volume.value
                                vertical: true
                                implicitHeight: 20
                                implicitWidth: 6
                            }
                        }
                    }

                    TapHandler {
                        onTapped: panel.currentPopup = adjustDetailPopup
                    }

                    AdjustPopup {
                        id: adjustDetailPopup
                        target: adjustCapsule
                        active: panel.currentPopup === adjustDetailPopup
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
