import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

PanelWindow {
    id: osdRoot

    signal moved(string type, real value)

    property string type: "brightness"
    property real value: 0
    property string approx: "low"

    visible: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Bottom center positioning: anchor only to bottom
    anchors {
        bottom: true
    }

    // Float it above the bottom
    margins {
        bottom: 100
    }

    implicitWidth: 300
    implicitHeight: 70
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        border.color: Theme.border
        border.width: 2
        radius: 8
        opacity: 0.95

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            Item {
                width: parent.width
                height: labelRow.implicitHeight
                Row {
                    id: labelRow
                    spacing: 8
                    IconImage {
                        anchors.verticalCenter: parent.verticalCenter
                        source: Quickshell.iconPath(osdRoot.type === "brightness" ? `brightness-${osdRoot.approx}-symbolic` : `audio-volume-${osdRoot.approx}-symbolic`)
                        implicitSize: 20
                        layer.enabled: true
                        layer.effect: ColorOverlay {
                            color: Theme.accent
                        }
                    }
                    Text {
                        text: (osdRoot.type === "brightness" ? "Brightness" : "Volume") + ":"
                        color: Theme.fg
                        font.family: Theme.globalFont
                        font.pixelSize: 14
                        font.bold: true
                    }
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(osdRoot.value * 100) + "%"
                    color: Theme.fg
                    font.family: Theme.globalFont
                    font.pixelSize: 14
                    font.bold: true
                }
            }

            MySlider {
                width: parent.width
                value: osdRoot.value
                onMoved: {
                    osdRoot.moved(osdRoot.type, value);
                    hideTimer.restart();
                }
            }
        }
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: osdRoot.visible = false
    }

    function show(newType, newValue, newApprox) {
        osdRoot.type = newType;
        osdRoot.value = newValue;
        osdRoot.approx = newApprox;
        osdRoot.visible = true;
        hideTimer.restart();
    }
}
