import QtQuick 2.7
import QtQuick.Layouts 1.3
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.0
import Qt.labs.settings 1.0

ColumnLayout {
    property Settings settings: null
    id: rootElement
    property  bool linkedBoolSettingDefault: false
    property string linkedBoolSetting: "example_setting"
    property bool isOpen: false
    property string title: ""
    // Help text under the element. Classic look: the bold italic lime note that the pages
    // used to place right after the element. Modern look: muted text inside the card.
    property string description: ""
    // Modern look: the element as a card of its own (the tile page: one card per tile).
    // Off for the elements nested in the settings accordions.
    property bool card: false
    default property alias accordionContent: contentPlaceholder.data
    spacing: 0

    readonly property bool modernCard: window.ui.modern && card
    // How deep it is among the settings sections (as AccordionElement): switched on inside a
    // section, it is framed as a subsection of it
    readonly property int depth: {
        var d = 1
        for (var p = parent; p; p = p.parent)
            if (p.isOpen !== undefined && p.title !== undefined && p.accordionContent !== undefined)
                d++
        return d
    }

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
    Layout.topMargin: modernCard ? 4 : 0
    Layout.bottomMargin: modernCard ? 4 : 0

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

    // Everything sits in one item, so that the modern card can be drawn behind all of it
    // (a layout would place a background child as one more row). Classic: no padding, no
    // background - the rows lie on the page as before.
    Item {
        id: cardItem
        Layout.fillWidth: true
        // Set on a change, not bound: a binding made a loop with the layout of the section
        // around it (as the content of StaticAccordionElement)
        implicitHeight: 0
        function updateHeight() {
            implicitHeight = cardColumn.implicitHeight + cardColumn.anchors.topMargin + cardColumn.anchors.bottomMargin
        }
        Connections {
            target: cardColumn
            function onImplicitHeightChanged() { cardItem.updateHeight() }
        }
        Connections {
            target: rootElement
            function onModernCardChanged() { cardItem.updateHeight() }
        }
        Component.onCompleted: updateHeight()

        // A thin frame instead of a fill, as the settings in the sections; a tile that is on
        // (shown on the main page) in the accent like an open section
        UiFrame {
            visible: rootElement.modernCard
            anchors.fill: parent
            radius: 16
            stroke: rootElement.isOpen ? window.ui.accent : window.ui.outline
            strokeWidth: 1
        }

        ColumnLayout {
            id: cardColumn
            spacing: 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: rootElement.modernCard ? 12 : 0
            anchors.rightMargin: rootElement.modernCard ? 8 : 0
            anchors.topMargin: rootElement.modernCard ? 4 : 0
            anchors.bottomMargin: rootElement.modernCard ? 12 : 0

            // Modern look: a plain switch row like the other switches of the settings (no
            // accent: a page of tiles has dozens of them); a tap anywhere on the row switches it
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
                    // settings.qml (search): a result named as the title lights the element
                    objectName: "accordionTitle"
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.right: modernSwitch.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: rootElement.title
                    wrapMode: Text.WordWrap
                    color: rootElement.modernCard && rootElement.isOpen ? window.ui.accent : window.ui.textMain
                    font.weight: rootElement.modernCard ? Font.DemiBold : Font.Normal
                }

                UiSwitch {
                    id: modernSwitch
                    anchors.right: parent.right
                    anchors.rightMargin: 0
                    anchors.verticalCenter: parent.verticalCenter
                    checked: rootElement.isOpen
                    onClicked: rootElement.toggle(checked)
                    Accessible.ignored: true
                }
            }

            UiSwitchDelegate {
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

            // Modern card: the help text right under the title, before the options
            Label {
                visible: rootElement.modernCard && rootElement.description.length > 0
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 8
                Layout.bottomMargin: 4
                text: rootElement.description
                font.pixelSize: Qt.application.font.pixelSize - 2
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: window.ui.textMuted
            }

            // This will get filled with the content. Held in a plain item: in a settings section
            // the modern look lays the frames of its settings beside it (a column would lay them
            // out as rows), the switch row on top of the block
            Item {
                id: contentBox
                readonly property bool framed: window.ui.modern && !rootElement.modernCard
                visible: rootElement.isOpen
                Layout.fillWidth: true
                // Set on a change, not bound: a binding made a loop with the layout of the column
                implicitHeight: 0
                Connections {
                    target: contentPlaceholder
                    function onImplicitHeightChanged() { contentBox.implicitHeight = contentPlaceholder.implicitHeight }
                }
                Component.onCompleted: implicitHeight = contentPlaceholder.implicitHeight
                // A tile card: its options under the title, clear of the right line of the frame
                Layout.leftMargin: framed ? settingFrames.insetLeft : rootElement.modernCard ? 4 : 0
                Layout.rightMargin: framed ? settingFrames.insetRight : rootElement.modernCard ? 10 : 0
                Layout.topMargin: framed ? settingFrames.insetTop : 0
                Layout.bottomMargin: framed ? settingFrames.insetBottom : 0
                // Under the switch row: the block frame starts behind it
                z: -1

                UiSettingFrames {
                    id: settingFrames
                    z: -1
                    visible: contentBox.framed
                    content: contentBox.framed && contentPlaceholder.children.length > 0
                             ? contentPlaceholder.children[0] : null
                    header: modernHeader
                    depth: rootElement.depth
                }

                ColumnLayout {
                    id: contentPlaceholder
                    width: parent.width
                }
            }

            // Classic look (and the modern look outside a card): the note after the element,
            // as the pages had it
            Label {
                visible: !rootElement.modernCard && rootElement.description.length > 0
                text: rootElement.description
                font.bold: !window.ui.modern
                font.italic: !window.ui.modern
                font.pixelSize: Qt.application.font.pixelSize - 2
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                Layout.fillWidth: true
                color: window.ui.modern ? window.ui.textMuted : Material.color(Material.Lime)
            }
        }
    }
}
