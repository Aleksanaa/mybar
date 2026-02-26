import QtQuick

Rectangle {
    id: thermoRoot
    implicitWidth: 6
    implicitHeight: 20
    color: "#585b70"
    // radius: 3

    property real progressValue: 0

    Rectangle {
        width: parent.width
        height: parent.height * thermoRoot.progressValue
        anchors.bottom: parent.bottom
        color: Theme.accent
        Behavior on height {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }
        }
    }
}
