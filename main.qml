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
        "volume": { "value": 0.01, "approx": "low", "sinks": [], "current_sink": 0 },
        "swayidle": { "active": true }
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

    Process {
        id: vicinae
        command: ["vicinae", "toggle"]
    }

    Process {
        id: swaync
        command: ["swaync-client", "-op"]
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
                        panel.currentPopup.closeAll()
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
                    source: Qt.resolvedUrl("nix-snowflake-colours.svg")
                    implicitSize: 28
                    Layout.alignment: Qt.AlignHCenter

                    TapHandler {
                        onTapped: vicinae.running = true
                    }
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
            
                        Behavior on height { NumberAnimation { duration: 500 } }
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
                        onTapped: panel.currentPopup = monitorDetailPopup
                    }

                    MyPopup {
                        target: monitorCapsule
                        id: monitorDetailPopup
                        active: panel.currentPopup === monitorDetailPopup
                        Row {
                            spacing: 5
                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                source: Quickshell.iconPath("cpu-symbolic")
                                implicitSize: 16
                                layer.enabled: true
                                layer.effect: ColorOverlay {
                                    color: Theme.accent
                                }
                            }
                            Text {
                                text: "CPU:"
                                color: Theme.fg
                            }
                        }

                        LineChart {
                            implicitWidth: parent.width
                            implicitHeight: 40
                            value: root.sysStats.cpu
                            lineColor: Theme.accent
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
                                    color:Theme.fg
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
                                    color:Theme.fg
                                    font.bold: true
                                    font.family: Theme.globalFont
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
                        onTapped: writeOutput({ "action": "close-window" })
                    }
                }
                MyCapsule {
                    implicitHeight: 42
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
                        onTapped: writeOutput({ "action": "maximize-column" })
                    }
                }
                MyCapsule {
                    implicitHeight: 42
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
                        onTapped: writeOutput({ "action": "toggle-fullscreen" })
                    }
                }
                MyCapsule {
                    implicitHeight: 42
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
                        onTapped: swaync.running = true
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
                                anchors.verticalCenter: parent.verticalCenter
                                id: batPercentage
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
                            source: Quickshell.iconPath(`my-caffeine-${root.sysStats.swayidle.active? "off": "on"}-symbolic`)
                            implicitSize: 17
                            layer.enabled: true
                            layer.effect: ColorOverlay {
                                color: Theme.accent
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
                        target: adjustCapsule
                        id: adjustDetailPopup
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
                            onMoved: writeOutput({ "action": "set_brightness", "value": value })
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
                                        onTapped: writeOutput({ "action": "toggle_mute" })
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
                            onMoved: writeOutput({ "action": "set_volume", "value": value })
                        }

                        MyCombo {
                            implicitWidth: parent.width
                            model: root.sysStats.volume.sinks
                            currentIndex: root.sysStats.volume.current_sink
                            onActivated: writeOutput({ "action": "set_sink", "sink_id": model[currentIndex].id })
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
                                    panel.currentPopup = globalTrayMenu
                                    globalTrayMenu.menuHandle = modelData.menu;
                                    globalTrayMenu.showAt(parent, panel.screen);
                                }

                                // Handle interaction
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.LeftButton) {
                                        modelData.activate(); // Left-click to activate (usually opens the main interface)
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
                        target: clockCapsule
                        id: clockDetailPopup
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
}
