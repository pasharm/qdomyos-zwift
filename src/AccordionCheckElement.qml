import QtQuick 2.7
import QtQuick.Layouts 1.3
import QtQuick.Controls 2.15
import Qt.labs.settings 1.0

ColumnLayout {
    property Settings settings: null
    id: rootElement
    property  bool linkedBoolSettingDefault: false
    property string linkedBoolSetting: "example_setting"
    property bool isOpen: false
    property string title: ""
    default property alias accordionContent: contentPlaceholder.data
    spacing: 0

    function convertValue(val) {
        let tpval = typeof(val);
        if (tpval==="undefined") return false;
        else if (tpval==="string") return val === "true";
        else if (tpval==="number") return val !== 0;
        else if (tpval==="boolean") return val;
        else return false;

    }

    Component.onCompleted: function() {
        if (typeof(settings[linkedBoolSetting])=="undefined")
            isOpen = convertValue(settings.value(linkedBoolSetting, linkedBoolSettingDefault));
        else
            isOpen = convertValue(settings[linkedBoolSetting]);
    }
 
    Layout.fillWidth: true;
 
    /*RowLayout {
        id: accordionHeader
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true;
 
        Rectangle{
           id:indicatRect
           Layout.alignment: Qt.AlignLeft | Qt.AlignTop
           width: 8; height: 8
           radius: 8
           color: "white"
        }
 
        Text {
            id: accordionText
            Layout.alignment: Qt.AlignLeft | Qt.AlignTop
            color: "#FFFFFF"
            text: rootElement.title
        }

    }*/
    function toggle(on) {
        rootElement.isOpen = on;
        if (typeof(settings[rootElement.linkedBoolSetting])=="undefined") {
            settings.setValue(rootElement.linkedBoolSetting, rootElement.convertValue(on));
        }
        else {
            settings[rootElement.linkedBoolSetting] = rootElement.convertValue(on);
        }
    }

    // Modern look: a plain switch row like the other switches of the settings (no card,
    // no accent: a page of tiles has dozens of them); a tap anywhere on the row switches it
    Rectangle {
        id: modernHeader
        visible: window.ui.modern
        Layout.fillWidth: true
        implicitHeight: Math.max(48, modernTitle.implicitHeight + 16)
        radius: 12
        color: modernArea.pressed ? window.ui.surfaceHigh : "transparent"

        Accessible.role: Accessible.CheckBox
        Accessible.name: rootElement.title
        Accessible.checked: rootElement.isOpen
        Accessible.onPressAction: rootElement.toggle(!rootElement.isOpen)

        MouseArea {
            id: modernArea
            anchors.fill: parent
            onClicked: rootElement.toggle(!rootElement.isOpen)
        }

        Label {
            id: modernTitle
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.right: modernSwitch.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: rootElement.title
            wrapMode: Text.WordWrap
            color: window.ui.textMain
        }

        Switch {
            id: modernSwitch
            anchors.right: parent.right
            anchors.rightMargin: 0
            anchors.verticalCenter: parent.verticalCenter
            checked: rootElement.isOpen
            onClicked: rootElement.toggle(checked)
            Accessible.ignored: true
        }
    }

    SwitchDelegate {
        visible: !window.ui.modern
        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
        Layout.fillWidth: true
        spacing: 0
        bottomPadding: 0
        topPadding: 0
        rightPadding: 0
        leftPadding: 0
        clip: false
        id: indicatCbx
        text: rootElement.title
        checked: rootElement.isOpen
        onClicked: {
            rootElement.isOpen = checked;
            if (typeof(settings[rootElement.linkedBoolSetting])=="undefined") {
                settings.setValue(rootElement.linkedBoolSetting, rootElement.convertValue(checked));
            }
            else {
                settings[rootElement.linkedBoolSetting] = rootElement.convertValue(checked);
            }
        }
    }
 
    // This will get filled with the content
    ColumnLayout {
        id: contentPlaceholder
        visible: rootElement.isOpen
        Layout.fillWidth: true;
        Layout.leftMargin: window.ui.modern ? 12 : 0
        Layout.rightMargin: window.ui.modern ? 8 : 0
    }
}
