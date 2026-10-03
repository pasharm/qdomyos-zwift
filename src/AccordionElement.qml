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

    // How deep the section is: 1 - a top-level one, 2 - inside it, and so on. The modern look
    // frames an open section of the first two levels as one block, a deeper one only indents
    readonly property int depth: {
        var d = 1
        for (var p = parent; p; p = p.parent)
            if (p.isOpen !== undefined && p.title !== undefined && p.accordionContent !== undefined)
                d++
        return d
    }
    // Inside another section: the modern look draws it as a flat row instead of a card
    readonly property bool nested: depth > 1

    spacing: 0
    Layout.fillWidth: true

    // Modern look: an open top-level section keeps a short copy of its header at the top of the
    // page while its content scrolls under it, so it stays clear which section this is. The copy
    // lives on the flickable, not in its content, and goes up with the end of the section; a tap
    // on it scrolls back to the real header.
    readonly property int stickyHeight: 44
    property Item stickyHeader: null
    readonly property Item pageFlickable: {
        for (var p = parent; p; p = p.parent)
            if (p.contentY !== undefined && p.contentItem !== undefined && p.flickableDirection !== undefined)
                return p
        return null
    }
    function updateSticky() {
        var f = pageFlickable
        var want = f && window.ui.modern && depth === 1 && isOpen && visible
        var top = 0, bottom = 0
        if (want) {
            top = sectionHeader.mapToItem(f, 0, 0).y
            bottom = rootElement.mapToItem(f, 0, 0).y + rootElement.height
            // Until the very end of the section: the copy goes up with its last row
            // As soon as the real header starts going up: the copy covers what is left of it and
            // shrinks with the scroll down to its compact height, so the change is gradual
            want = top < 0 && bottom > 0
        }
        if (!want) {
            if (stickyHeader)
                stickyHeader.visible = false
            return
        }
        if (!stickyHeader)
            stickyHeader = stickyComponent.createObject(f)
        // On the outline of the section block, which runs 1 px outside the real header
        stickyHeader.x = sectionHeader.mapToItem(f, 0, 0).x - 1
        stickyHeader.width = sectionHeader.width + 2
        // At the end its bottom line lies on the bottom line of the block (1 px below the section)
        var h = Math.max(stickyHeight, Math.min(sectionHeader.height, top + sectionHeader.height))
        stickyHeader.height = h
        stickyHeader.y = Math.min(0, bottom + 1 - h)
        stickyHeader.visible = true
    }
    function scrollToHeader() {
        var f = pageFlickable
        if (!f)
            return
        var at = sectionHeader.mapToItem(f.contentItem, 0, 0).y - sectionHeader.Layout.topMargin
        f.contentY = Math.max(0, Math.min(at, f.contentHeight - f.height))
    }
    Connections {
        target: rootElement.pageFlickable
        enabled: rootElement.isOpen && rootElement.depth === 1
        function onContentYChanged() { rootElement.updateSticky() }
        function onHeightChanged() { rootElement.updateSticky() }
    }
    onHeightChanged: if (isOpen) updateSticky()
    onVisibleChanged: updateSticky()
    Component.onDestruction: if (stickyHeader) stickyHeader.destroy()

    Component {
        id: stickyComponent
        UiFrame {
            id: sticky
            z: 10
            height: rootElement.stickyHeight
            // As the corners of the block it slides into at the end
            radius: sectionHeader.radius + 1
            fill: window.ui.surfaceHigh
            stroke: window.ui.accent
            strokeWidth: 1

            Accessible.role: Accessible.Button
            Accessible.name: rootElement.title
            Accessible.onPressAction: rootElement.scrollToHeader()

            // Under the copy: the page above it and its upper half in the page colour, so the
            // side lines of the section block start at the middle of the copy, not above it
            Rectangle {
                z: -1
                x: -3
                y: -24
                width: parent.width + 6
                height: 24 + parent.height / 2
                color: window.ui.bg
            }
            // The accent bar of the open header, on the outline like there
            Rectangle {
                width: 4
                // As long as on the real header at its height; shorter as the copy shrinks, so that
                // at the compact height it stays within the straight part of the side
                height: Math.min(parent.height - 24, 14 + 1.5 * (parent.height - rootElement.stickyHeight))
                anchors.verticalCenter: parent.verticalCenter
                radius: 2
                color: window.ui.accent
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: window.ui.plainTitle(rootElement.title)
                elide: Text.ElideRight
                // From the size of the real header down to the compact one as the copy shrinks
                font.pixelSize: parent.height > rootElement.stickyHeight + 6 ? 16 : 15
                font.weight: Font.Medium
                color: window.ui.accent
            }
            // The chevron of the real header, fading out as the copy shrinks
            UiIcon {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24
                name: "expand_more"
                rotation: 180
                color: window.ui.textMuted
                opacity: Math.max(0, Math.min(1, (parent.height - rootElement.stickyHeight)
                                                 / Math.max(1, sectionHeader.height - rootElement.stickyHeight)))
                visible: opacity > 0
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: rootElement.scrollToHeader()
            }
        }
    }

    UiSectionHeader {
        id: sectionHeader
        visible: window.ui.modern
        title: rootElement.title
        isOpen: rootElement.isOpen
        nested: rootElement.nested
        depth: rootElement.depth
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
        // Modern look: inside the block of the section and inside the frames of its settings
        Layout.leftMargin: settingFrames.insetLeft
        Layout.rightMargin: settingFrames.insetRight
        Layout.topMargin: settingFrames.insetTop
        Layout.bottomMargin: settingFrames.insetBottom
        // Under the header: the block frame starts behind it
        z: -1
        asynchronous: false

        UiSettingFrames {
            id: settingFrames
            z: -1
            content: contentLoader.item
            header: sectionHeader
            depth: rootElement.depth
        }

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
        updateSticky()
    }
}
