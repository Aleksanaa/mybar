import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

Item {
    id: root

    property int month: new Date().getMonth()
    property int year: new Date().getFullYear()

    implicitWidth: 200
    implicitHeight: mainLayout.implicitHeight

    Column {
        id: mainLayout
        width: parent.width
        spacing: 8

        RowLayout {
            id: monthHeader
            width: parent.width

            Button {
                id: prevButton
                flat: true

                onClicked: {
                    if (root.month === 0) {
                        root.month = 11;
                        root.year--;
                    } else {
                        root.month--;
                    }
                }

                contentItem: IconImage {
                    source: Quickshell.iconPath("go-previous-symbolic")
                    implicitSize: 16
                    layer.enabled: true
                    layer.effect: ColorOverlay {
                        color: prevButton.hovered ? Theme.accent : Theme.fg
                    }
                }

                background: null
            }

            Text {
                Layout.fillWidth: true
                text: Qt.formatDateTime(new Date(root.year, root.month, 1), "MMMM yyyy")
                color: Theme.fg
                font.pixelSize: 16
                font.family: Theme.globalFont
                horizontalAlignment: Text.AlignHCenter
            }

            Button {
                id: nextButton
                flat: true

                onClicked: {
                    if (root.month === 11) {
                        root.month = 0;
                        root.year++;
                    } else {
                        root.month++;
                    }
                }

                contentItem: IconImage {
                    source: Quickshell.iconPath("go-next-symbolic")
                    implicitSize: 16
                    layer.enabled: true
                    layer.effect: ColorOverlay {
                        color: nextButton.hovered ? Theme.accent : Theme.fg
                    }
                }

                background: null
            }
        }

        DayOfWeekRow {
            id: dowRow
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

            month: root.month
            year: root.year

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
                    opacity: (model.month === grid.month) ? 1.0 : 0.5
                    color: (model.today && model.month === grid.month) ? Theme.accent : Theme.fg
                    font.pixelSize: 14
                }
            }
        }

        Button {
            id: backToTodayButton
            anchors.horizontalCenter: parent.horizontalCenter
            flat: true
            text: "Go Back"

            visible: root.month !== new Date().getMonth() || root.year !== new Date().getFullYear()
            height: visible ? implicitHeight : 0
            opacity: visible ? 1 : 0

            onClicked: {
                let now = new Date();
                root.month = now.getMonth();
                root.year = now.getFullYear();
            }

            contentItem: Text {
                text: backToTodayButton.text
                color: backToTodayButton.hovered ? Theme.accent : Theme.fg
                font.family: Theme.globalFont
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
            }

            background: null

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                }
            }
        }
    }
}
