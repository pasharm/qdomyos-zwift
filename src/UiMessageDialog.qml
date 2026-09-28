import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Controls.Material 2.12
import Qt.labs.platform 1.1 as P

// Yes/No question in place of Qt.labs.platform MessageDialog, with the same properties,
// signals, open()/close() and visible. The platform dialog is a native Android window
// whose look follows the system, not the app: the modern look draws a card in the app
// theme instead. Classic look: the native dialog, as before (this popup stays empty).
Popup {
    id: root

    property string title: ""
    property string text: ""
    property string informativeText: ""
    property int buttons: P.MessageDialog.Ok

    signal yesClicked()
    signal noClicked()
    signal okClicked()
    signal abortClicked()
    signal cancelClicked()
    signal accepted()
    signal rejected()

    readonly property bool modern: window.ui.modern

    // The card stays tappable during its closing animation: one answer per opening
    property bool answered: false
    onAboutToShow: answered = false

    function answer(button) {
        if (answered)
            return
        answered = true
        if (button === P.MessageDialog.Yes) yesClicked()
        else if (button === P.MessageDialog.No) noClicked()
        else if (button === P.MessageDialog.Ok) okClicked()
        else if (button === P.MessageDialog.Abort) abortClicked()
        else if (button === P.MessageDialog.Cancel) cancelClicked()
        close()
        if (button === P.MessageDialog.Yes || button === P.MessageDialog.Ok) accepted()
        else rejected()
    }

    parent: Overlay.overlay
    modal: modern
    dim: modern
    closePolicy: modern ? Popup.CloseOnEscape : Popup.NoAutoClose
    width: modern ? Math.min(parent.width - 48, 440) : 0
    height: modern ? implicitHeight : 0
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    padding: 24
    bottomPadding: 12

    onOpened: if (!modern) nativeDialog.open()
    onClosed: if (nativeDialog.visible) nativeDialog.close()

    P.MessageDialog {
        id: nativeDialog
        title: root.title
        text: root.text
        informativeText: root.informativeText
        buttons: root.buttons
        onYesClicked: root.answer(P.MessageDialog.Yes)
        onNoClicked: root.answer(P.MessageDialog.No)
        onOkClicked: root.answer(P.MessageDialog.Ok)
        onAbortClicked: root.answer(P.MessageDialog.Abort)
        onCancelClicked: root.answer(P.MessageDialog.Cancel)
        // Back button: no answer, only closes
        onRejected: if (root.visible) root.close()
    }

    background: Rectangle {
        visible: root.modern
        radius: 28
        color: window.ui.surfaceHigh
        border.width: window.ui.dark ? 0 : 1
        border.color: window.ui.outline
    }

    contentItem: Column {
        visible: root.modern
        spacing: 12

        Label {
            width: parent.width
            visible: text.length > 0
            text: root.title.length > 0 ? root.title : root.text
            wrapMode: Text.WordWrap
            font.pixelSize: 20
            font.weight: Font.DemiBold
            color: window.ui.textMain
        }

        Flickable {
            width: parent.width
            height: Math.min(body.implicitHeight, root.parent.height * 0.55)
            visible: body.text.length > 0
            contentHeight: body.implicitHeight
            clip: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            Label {
                id: body
                width: parent.width
                text: root.title.length > 0 && root.text.length > 0
                      ? root.text + (root.informativeText.length > 0 ? "\n\n" + root.informativeText : "")
                      : root.informativeText
                wrapMode: Text.WordWrap
                font.pixelSize: 16
                lineHeight: 1.15
                color: window.ui.textMuted
            }
        }

        Row {
            anchors.right: parent.right
            spacing: 4
            topPadding: 8

            Repeater {
                // Order of the buttons: negative ones first, the positive one on the right
                model: [P.MessageDialog.Cancel, P.MessageDialog.Abort, P.MessageDialog.No,
                        P.MessageDialog.Yes, P.MessageDialog.Ok].filter(function(b) { return (root.buttons & b) !== 0 })
                UiButton {
                    readonly property bool positive: modelData === P.MessageDialog.Yes || modelData === P.MessageDialog.Ok
                    text: modelData === P.MessageDialog.Yes ? qsTr("Yes")
                        : modelData === P.MessageDialog.No ? qsTr("No")
                        : modelData === P.MessageDialog.Ok ? qsTr("OK")
                        : qsTr("Cancel")
                    flat: !positive
                    highlighted: positive
                    onClicked: root.answer(modelData)
                }
            }
        }
    }
}
