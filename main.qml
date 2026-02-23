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

    component MyPopup: PopupWindow {
        id: root
        property Item target: null
    
        default property alias content: contentContainer.data
        property bool active: panel.currentPopup === root

        visible: active
        width: 220
        height: 160
        color: "transparent"

        anchor {
            item: target
            edges: Edges.Left | Edges.Top
            gravity: Edges.Left | Edges.Bottom
            adjustment: PopupAdjustment.Slide
        }

        Rectangle {
            anchors.fill: parent
            color: colors.bg
            border.color: colors.border
            border.width: 2
            radius: 8
            opacity: 0.95

            // 这里是内容插槽
            Column {
                id: contentContainer
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8
                // 外部定义的内容会显示在这里
            }
        }
    }

    component LineChart: Canvas {
        id: chart
        // 暴露给外部的接口
        property real value: 0        // 当前数值 (0.0 - 1.0)
        property color lineColor: root.colors.accent
        property int maxPoints: 40

        // 内部私有记忆
        property var _history: []

        // 核心逻辑：当外部传入的数值变化时，自动更新历史记录
        onValueChanged: {
            let data = _history;
            data.push(value);
            if (data.length > maxPoints) data.shift();
            _history = data;
            chart.requestPaint(); // 触发重绘
        }

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            if (_history.length < 2) return;

            let stepX = width / (maxPoints - 1);
        
            ctx.beginPath();
            ctx.strokeStyle = lineColor;
            ctx.lineWidth = 2;
            for (let i = 0; i < _history.length; i++) {
                let x = i * stepX;
                let y = height - (_history[i] * height);
                if (i === 0) ctx.moveTo(x, y);
                else ctx.lineTo(x, y);
            }
            ctx.stroke();

            ctx.lineTo((_history.length - 1) * stepX, height);
            ctx.lineTo(0, height);
            ctx.closePath();
            let grad = ctx.createLinearGradient(0, 0, 0, height);
            grad.addColorStop(0, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.3));
            grad.addColorStop(1, "transparent");
            ctx.fillStyle = grad;
            ctx.fill();
        }
    }

    component MySlider: Slider {
        id: customSlider
        value: 0
        handle: Rectangle {
            x: customSlider.leftPadding + customSlider.visualPosition * (customSlider.availableWidth - width)
            y: customSlider.topPadding + customSlider.availableHeight / 2 - height / 2
            implicitWidth: 14
            implicitHeight: 14
            radius: 7
            color: colors.fg 
        }

        background: Rectangle {
            x: customSlider.leftPadding
            y: customSlider.topPadding + customSlider.availableHeight / 2 - height / 2
            implicitWidth: 100
            implicitHeight: 4
            width: customSlider.availableWidth
            height: implicitHeight
            radius: 2
            color: colors.border

            Rectangle {
                width: customSlider.visualPosition * customSlider.width
                height: parent.height
                color: colors.accent
                radius: 2
            }
        }
    }

    component MyCombo: ComboBox {
        id: myCombo
        width: 200

        textRole: "name" 

        background: Rectangle {
            implicitWidth: 200
            implicitHeight: 30
            color: colors.bg
            border.color: myCombo.visualFocus ? colors.accent : colors.border
            border.width: 1
            radius: 4
        }

        delegate: ItemDelegate {
            width: myCombo.width
            contentItem: Text {
                text: modelData.name
                color: highlighted ? colors.accent : colors.fg
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                color: highlighted ? colors.accent : "transparent"
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

        // Holds the currently visible popup object. null means none are open.
        property QtObject currentPopup: null

        MouseArea {
            anchors.fill: parent
            enabled: panel.currentPopup !== null
            z: 998 
            onPressed: panel.currentPopup = null // Clearing this closes the popup
        }

        RectangularShadow {
            anchors.fill: contentRect
            radius: contentRect.radius
            blur: 5
            spread: 0.1
            color: "#B811111b"
            z: -1
        }

        TrayMenu {
            id: globalTrayMenu
            backgroundColor: colors.bg
            borderColor: colors.border
            textColor: colors.fg
            highlightColor: colors.accent
            borderRadius: 8
            visible: panel.currentPopup === globalTrayMenu
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
                    id: monitorCapsule

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

                    TapHandler {
                        onTapped: panel.currentPopup = monitorDetailPopup
                    }

                    MyPopup {
                        target: monitorCapsule
                        id: monitorDetailPopup
                        Row {
                            spacing: 5
                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                source: Quickshell.iconPath("cpu-symbolic")
                                implicitSize: 16
                                layer.enabled: true
                                layer.effect: ColorOverlay {
                                    color: colors.accent
                                }
                            }
                            Text {
                                text: "CPU:"
                                color: colors.fg
                            }
                        }

                        LineChart {
                            width: parent.width
                            height: 40
                            value: root.sysStats.cpu
                            lineColor: root.colors.accent
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
                                visible: root.sysStats.bat.value != 100
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
                    id: adjustCapsule
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

                    TapHandler {
                        onTapped: panel.currentPopup = adjustDetailPopup
                    }

                    MyPopup {
                        target: adjustCapsule
                        id: adjustDetailPopup

                        Row {
                            spacing: 5
                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                source: Quickshell.iconPath("brightness-symbolic")
                                implicitSize: 16
                                layer.enabled: true
                                layer.effect: ColorOverlay {
                                    color: colors.accent
                                }
                            }
                            Text {
                                text: "Brightness:"
                                color: colors.fg
                            }
                        }

                        MySlider {}

                        Row {
                            spacing: 5
                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                source: Quickshell.iconPath("volume-symbolic")
                                implicitSize: 16
                                layer.enabled: true
                                layer.effect: ColorOverlay {
                                    color: colors.accent
                                }
                            }
                            Text {
                                text: "Volume:"
                                color: colors.fg
                            }
                        }

                        MySlider {}

                        MyCombo {}
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
                                width: 20
                                height: 20
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                visible: modelData.status !== 0

                                IconImage {
                                    width: modelData.id.includes("Telegram") ? 16 : 20
                                    height: 20
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

                    
                    TapHandler {
                        onTapped: panel.currentPopup = clockDetailPopup
                    }

                    MyPopup {
                        target: clockCapsule
                        id: clockDetailPopup
                        height: 240
                        Text {
                            text: Qt.formatDateTime(new Date(), "dd, MM, yyyy")
                            color: colors.fg
                            font.pixelSize: 20
                            font.family: globalFont
                            Layout.alignment: Qt.AlignHCenter
                        }

                        DayOfWeekRow {
                            locale: Qt.locale("zh_CN")
                            width: parent.width
        
                            delegate: Text {
                                text: model.narrowName
                                font.bold: true
                                font.pixelSize: 14
                                font.family: globalFont
                                color: colors.accent
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
                                border.color: colors.fg

                                Text {
                                    anchors.centerIn: parent
                                    text: model.day
                                    opacity: model.month === grid.month ? 1.0 : 0.5
                                    color: model.today ? colors.accent : colors.fg
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
