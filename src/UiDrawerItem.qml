import QtQuick 2.12
import QtQuick.Controls 2.5

// Navigation drawer entry of the modern look: icon, label and a pill highlight
ItemDelegate {
    id: control
    property string iconName: ""
    property bool external: false

    width: parent ? parent.width : implicitWidth
    height: 48
    leftPadding: 28
    rightPadding: 24
    focusPolicy: Qt.NoFocus

    background: Rectangle {
        x: 12
        y: 2
        width: control.width - 24
        height: control.height - 4
        radius: height / 2
        color: control.down ? window.ui.alpha(window.ui.accent, 0.22)
             : control.hovered ? window.ui.alpha(window.ui.onSurface, 0.06)
             : "transparent"
    }

    contentItem: Item {
        UiIcon {
            id: itemIcon
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            name: control.iconName
            color: control.down ? window.ui.accent : window.ui.onSurfaceVariant
        }
        Label {
            anchors.left: itemIcon.right
            anchors.leftMargin: 16
            anchors.right: externalIcon.visible ? externalIcon.left : parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: control.text
            font.pixelSize: 15
            font.weight: Font.Medium
            color: window.ui.onSurface
            elide: Text.ElideRight
        }
        UiIcon {
            id: externalIcon
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            name: "open_in_new"
            color: window.ui.onSurfaceVariant
            visible: control.external
        }
    }
}
