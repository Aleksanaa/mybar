import QtQuick
import QtQuick.Controls

Slider {
    id: customSlider
    value: 0
    handle: Rectangle {
        x: customSlider.leftPadding + customSlider.visualPosition * (customSlider.availableWidth - width)
        y: customSlider.topPadding + customSlider.availableHeight / 2 - height / 2
        implicitWidth: 14
        implicitHeight: 14
        radius: 7
        color: Theme.fg
    }

    background: Rectangle {
        x: customSlider.leftPadding
        y: customSlider.topPadding + customSlider.availableHeight / 2 - height / 2
        implicitWidth: 100
        implicitHeight: 4
        width: customSlider.availableWidth
        height: implicitHeight
        radius: 2
        color: Theme.border

        Rectangle {
            width: customSlider.visualPosition * customSlider.width
            height: parent.height
            color: Theme.accent
            radius: 2
        }
    }
}
