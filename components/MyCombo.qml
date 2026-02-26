import QtQuick
import QtQuick.Controls

ComboBox {
    id: myCombo
    width: 200

    textRole: "name"

    background: Rectangle {
        implicitWidth: 200
        implicitHeight: 30
        color: Theme.bg
        border.color: myCombo.visualFocus ? Theme.accent : Theme.border
        border.width: 1
        radius: 4
    }

    delegate: ItemDelegate {
        width: myCombo.width
        contentItem: Text {
            text: modelData.name
            color: highlighted ? Theme.accent : Theme.fg
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            color: highlighted ? Theme.accent : "transparent"
        }
    }
}
