import QtQuick 2.7
import QtQuick.Layouts 1.3

ColumnLayout {
    id: rootElement
    property bool isOpen: false
    property string title: ""
    property alias color: accordionHeader.color
    property alias textColor: accordionText.color
    property alias textFont: accordionText.font.family
    property alias textFontSize: accordionText.font.pixelSize
    property alias indicatRectColor: indicatRect.color
    property string accordionContent: ""
    // Inside another section: the modern look draws it as a flat row instead of a card
    readonly property bool nested: {
        for (var p = parent; p; p = p.parent)
            if (p.isOpen !== undefined && p.title !== undefined && p.accordionContent !== undefined)
                return true
        return false
    }

    spacing: 0

    Layout.fillWidth: true;

    UiSectionHeader {
        visible: window.ui.modern
        title: rootElement.title
        isOpen: rootElement.isOpen
        nested: rootElement.nested
        chevron: "chevron_right"
        onClicked: stackView.push(rootElement.accordionContent)
    }

    Rectangle {
        id: accordionHeader
        visible: !window.ui.modern
        color: "red"
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true;
        height: 48

        Accessible.role: Accessible.Button 
        Accessible.name: title 
        Accessible.description: expanded ? "Expanded" : "Collapsed"
        Accessible.onPressAction: toggle()

        Rectangle{
           id:indicatRect
           x: 16; y: 20
           width: 8; height: 8
           radius: 8
           color: "white"
        }

        Text {
            id: accordionText
            x:34;y:13
            color: "#FFFFFF"
            text: rootElement.title
        }
        Text {
            y:13
            anchors.right:  parent.right
            anchors.rightMargin: 20
            width: 30; height: 30
            id: indicatImg
            text: ">"
            font.pixelSize: 24
            color: "white"
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                stackView.push(accordionContent)
            }
        }
    }
}
