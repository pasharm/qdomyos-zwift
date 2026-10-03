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

    // Modern look: every setting of the open section in a thin frame. A setting is not an item
    // of its own in settings.qml but loose neighbours in the column of the section (a switch,
    // then its description), so the frames are a layer under the content: the column is cut
    // into groups - a control and the descriptions after it - and each group gets the space
    // around it by its layout margins and a frame drawn by the geometry of its first and last
    // item. Sections inside are left out: they draw their own block.
    readonly property int framePadH: 10
    readonly property int framePadV: 8
    readonly property int frameGap: 6
    readonly property int blockPad: 6
    property var itemFrames: []
    // The layout margins of the content as settings.qml set them, to add to and to give back
    property var baseMargins: []

    function isSectionLike(c) {
        return c.title !== undefined && (c.nested !== undefined || c.accordionContent !== undefined)
    }
    function isDescription(c) {
        return c.text !== undefined && c.wrapMode !== undefined && c.color !== undefined
            && Qt.colorEqual(c.color, window.ui.textMuted)
    }
    // A label of its own, not a description: the name of the control below it
    function isTitle(c) {
        return c.text !== undefined && c.wrapMode !== undefined && c.checked === undefined && c.readOnly === undefined
            && !isDescription(c)
    }
    function baseOf(c) {
        for (var i = 0; i < baseMargins.length; i++)
            if (baseMargins[i].item === c)
                return baseMargins[i]
        var b = { item: c, top: c.Layout.topMargin, bottom: c.Layout.bottomMargin,
                  left: c.Layout.leftMargin, right: c.Layout.rightMargin }
        baseMargins.push(b)
        return b
    }
    function setMargin(c, key, v) {
        if (c.Layout[key] !== v)
            c.Layout[key] = v
    }
    function regroup() {
        var content = contentLoader.item
        if (!content) {
            if (itemFrames.length)
                itemFrames = []
            return
        }
        var kids = content.children
        var entries = []
        var cur = null
        for (var i = 0; i < kids.length; i++) {
            var c = kids[i]
            var b = baseOf(c)
            var want = { item: c, top: b.top, bottom: b.bottom, left: b.left, right: b.right }
            entries.push(want)
            if (!window.ui.modern || !c.visible || (c.height <= 0 && c.implicitHeight <= 0))
                continue
            if (isSectionLike(c)) {
                // Out to the edges of the frames around it
                want.left = b.left - framePadH
                want.right = b.right - framePadH
                want.section = true
                want.groupStart = true
                cur = null
            } else if (cur && (isDescription(c) || (cur.titleOnly && c.checked === undefined))) {
                // A description joins the setting above it; a lone title ("FTMS Treadmill:")
                // takes the picker below it into its frame, but not a switch: a warning line
                // above a switch is a setting of its own
                cur.last = want
                cur.titleOnly = false
            } else {
                cur = { first: want, last: want, titleOnly: isTitle(c) }
                want.group = cur
                want.groupStart = true
            }
        }
        var frames = []
        var seen = false
        for (i = 0; i < entries.length; i++) {
            var e = entries[i]
            if (!e.groupStart)
                continue
            if (e.section) {
                e.top += seen ? frameGap : 0
            } else {
                e.group.first.top += framePadV + (seen ? frameGap : 0)
                e.group.last.bottom += framePadV
                frames.push({ first: e.group.first.item, last: e.group.last.item })
            }
            seen = true
        }
        for (i = 0; i < entries.length; i++) {
            setMargin(entries[i].item, "topMargin", entries[i].top)
            setMargin(entries[i].item, "bottomMargin", entries[i].bottom)
            setMargin(entries[i].item, "leftMargin", entries[i].left)
            setMargin(entries[i].item, "rightMargin", entries[i].right)
        }
        var same = frames.length === itemFrames.length
        for (i = 0; same && i < frames.length; i++)
            same = frames[i].first === itemFrames[i].first && frames[i].last === itemFrames[i].last
        if (!same)
            itemFrames = frames
    }

    Connections {
        target: contentLoader.item
        ignoreUnknownSignals: true
        function onImplicitHeightChanged() { Qt.callLater(rootElement.regroup) }
    }
    Connections {
        target: window.ui
        function onModernChanged() { Qt.callLater(rootElement.regroup) }
    }

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
            want = top < 0 && bottom > stickyHeight / 2
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
        stickyHeader.y = Math.min(0, bottom - stickyHeight)
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
            radius: 12
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

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: window.ui.plainTitle(rootElement.title)
                elide: Text.ElideRight
                font.pixelSize: 15
                font.weight: Font.Medium
                color: window.ui.accent
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
        // Modern look: the content inside the block of the section and inside the frames of its
        // settings; a section deeper than two levels has no block and only indents
        readonly property int inset: !window.ui.modern ? 0
                                   : rootElement.depth === 1 ? sectionHeader.Layout.leftMargin + rootElement.blockPad + rootElement.framePadH
                                   : rootElement.depth === 2 ? rootElement.blockPad + rootElement.framePadH
                                   : 2 * rootElement.framePadH
        Layout.leftMargin: inset
        Layout.rightMargin: window.ui.modern && rootElement.depth > 2 ? rootElement.framePadH : inset
        Layout.topMargin: window.ui.modern && rootElement.depth <= 2 ? rootElement.blockPad : 0
        Layout.bottomMargin: window.ui.modern && rootElement.depth <= 2 ? rootElement.blockPad : 0
        // Under the header: the block frame starts behind it
        z: -1
        asynchronous: false

        // The block of an open section: its header is the top of it
        UiFrame {
            visible: window.ui.modern && rootElement.depth <= 2
            z: -2
            x: sectionHeader.x - contentLoader.x - 1
            y: sectionHeader.y - contentLoader.y - 1
            width: sectionHeader.width + 2
            height: contentLoader.y + contentLoader.height + contentLoader.Layout.bottomMargin - sectionHeader.y + 2
            radius: sectionHeader.radius + 1
            stroke: rootElement.depth === 1 ? window.ui.accent : window.ui.outline
            strokeWidth: 1
        }

        // A frame for every setting
        Repeater {
            model: rootElement.itemFrames
            UiFrame {
                z: -1
                x: -rootElement.framePadH
                width: contentLoader.width + 2 * rootElement.framePadH
                y: modelData.first.y - rootElement.framePadV
                height: modelData.last.y + modelData.last.height - modelData.first.y + 2 * rootElement.framePadV
                radius: 14
                stroke: window.ui.outline
                strokeWidth: 1
            }
        }

        onLoaded: {
            if (item) {
                item.Layout.fillWidth = true
                visible = true
                rootElement.baseMargins = []
                rootElement.regroup()
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
            itemFrames = []
        }
        updateSticky()
    }
}
