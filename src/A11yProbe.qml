import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    ToolButton {
        icon.source: "icons/icons/settings.png"
        onClicked: stack.push("settings.qml")
    }
    ToolButton {
        id: namedLater
        icon.source: "icons/icons/settings.png"
        Component.onCompleted: namedLater.Accessible.name = qsTr("Settings")
    }
    TextField {
        placeholderText: qsTr("Name")
    }
    Rectangle {
        MouseArea {
            anchors.fill: parent
            onClicked: close()
        }
    }
}
