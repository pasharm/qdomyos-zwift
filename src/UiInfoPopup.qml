import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Controls.Material 2.12

// A notice with nothing to answer ("Your Strava account is now connected!", "Trial time
// expired!" ...). Classic look: the popup of the upstream as it was - fixed size, white text,
// the line breaks of the text. Modern look: the card of UiMessageDialog with an OK button,
// the text in the theme colours and wrapped by the card width.
UiPopup {
    id: control

    property string title: ""
    property string text: ""
    // Classic look: the sizes of the popup and of its label as they were (0 = implicit)
    property int classicWidth: 380
    property int classicHeight: 130
    property int classicLabelWidth: 0
    property int classicLabelHeight: 0
    // Modern look: the addresses in the text open the browser. Off where the address is only
    // named ("not affiliated with https://whatsonzwift.com/")
    property bool links: true

    // The texts break their lines by hand (\n, <br>) for the fixed classic width: in the card
    // the single breaks become spaces and only the empty lines between paragraphs stay
    function flowText(s) {
        return s.replace(/<br\s*\/?>/g, "\n")
                .replace(/([^\n])\n(?!\n)/g, "$1 ")
                .replace(/ {2,}/g, " ")
                .trim()
    }

    // The card text as StyledText: the markup characters escaped, the addresses made links
    function linkText(s) {
        var t = flowText(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        if (links)
            t = t.replace(/(https?:[^ \n]+[^ \n.,!?])/g, '<a href="$1">$1</a>')
        return t.replace(/\n/g, "<br>")
    }

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: modern ? Math.min(parent.width - 48, 440) : classicWidth
    height: modern ? implicitHeight : classicHeight
    modal: true
    focus: true
    palette.text: "white"
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: modern ? 24 : 12
    bottomPadding: 12

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0 }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0 }
    }

    contentItem: Item {
        implicitHeight: control.modern ? modernColumn.implicitHeight : classicColumn.implicitHeight

        Column {
            id: classicColumn
            visible: !control.modern
            anchors.horizontalCenter: parent.horizontalCenter
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                width: control.classicLabelWidth > 0 ? control.classicLabelWidth : implicitWidth
                height: control.classicLabelHeight > 0 ? control.classicLabelHeight : implicitHeight
                text: control.text
            }
        }

        Column {
            id: modernColumn
            visible: control.modern
            width: parent.width
            spacing: 12

            Label {
                width: parent.width
                visible: control.title.length > 0
                text: control.title
                wrapMode: Text.WordWrap
                font.pixelSize: 20
                font.weight: Font.DemiBold
                color: window.ui.textMain
            }

            Flickable {
                id: bodyFlick
                width: parent.width
                height: Math.min(body.implicitHeight, control.parent.height * 0.55)
                contentHeight: body.implicitHeight
                clip: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                Label {
                    id: body
                    width: parent.width
                    text: control.linkText(control.text)
                    textFormat: Text.StyledText
                    linkColor: Material.accent
                    onLinkActivated: Qt.openUrlExternally(link)
                    wrapMode: Text.Wrap
                    font.pixelSize: 16
                    lineHeight: 1.15
                    color: control.title.length > 0 ? window.ui.textMuted : window.ui.textMain
                }
                // A long text: the bar stays to show there is more below
                ScrollIndicator.vertical: ScrollIndicator {
                    active: bodyFlick.contentHeight > bodyFlick.height
                }
            }

            UiButton {
                anchors.right: parent.right
                // the OK of the question cards, already translated
                text: qsTranslate("UiMessageDialog", "OK")
                flat: true
                onClicked: control.close()
            }
        }
    }
}
