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
    default property alias accordionContent: contentLoader.sourceComponent

    // Signal emitted when content becomes visible
    signal contentBecameVisible()

    // Inside another section: the modern look draws it as a flat row instead of a card
    readonly property bool nested: {
        for (var p = parent; p; p = p.parent)
            if (p.isOpen !== undefined && p.title !== undefined && p.accordionContent !== undefined)
                return true
        return false
    }

    spacing: 0
    Layout.fillWidth: true

    UiSectionHeader {
        visible: window.ui.modern
        title: rootElement.title
        isOpen: rootElement.isOpen
        nested: rootElement.nested
        chevron: "expand_more"
        onClicked: rootElement.isOpen = !rootElement.isOpen
    }

    // Open or close the section: a tap on the header, or the press action of a screen reader
    function toggle() {
        isOpen = !isOpen
        if (isOpen) {
            indicatImg.source = "qrc:/icons/arrow-expand-vertical.png"
        } else {
            indicatImg.source = "qrc:/icons/arrow-collapse-vertical.png"
        }
    }

    Rectangle {
        id: accordionHeader
        visible: !window.ui.modern
        color: "red"
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        height: 48

        Accessible.role: Accessible.Button         
        Accessible.name: title 
        Accessible.description: rootElement.isOpen ? "Expanded" : "Collapsed"
        Accessible.onPressAction: rootElement.toggle()

        Rectangle {
            id: indicatRect
            x: 16; y: 20
            width: 8; height: 8
            radius: 8
            color: "white"
        }

        Text {
            id: accordionText
            x: 34; y: 13
            color: "#FFFFFF"
            text: rootElement.title
        }

        Image {
            y: 13
            anchors.right: parent.right
            anchors.rightMargin: 20
            width: 30; height: 30
            id: indicatImg
            source: "qrc:/icons/arrow-collapse-vertical.png"
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: rootElement.toggle()
        }
    }

    // Loader with enhanced visibility handling
    Loader {
        id: contentLoader
        active: rootElement.isOpen
        visible: false // Start invisible
        Layout.fillWidth: true
        asynchronous: false

        onLoaded: {
            if (item) {
                item.Layout.fillWidth = true
                visible = true
                rootElement.contentBecameVisible()
            }
        }

        // Handle visibility changes
        onVisibleChanged: {
            if (visible && status === Loader.Ready) {
                rootElement.contentBecameVisible()
            }
        }
    }

    // Handle accordion closing
    onIsOpenChanged: {
        if (!isOpen) {
            contentLoader.visible = false
        }
    }
}
