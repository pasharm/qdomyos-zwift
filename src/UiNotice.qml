import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Controls.Material 2.12

// Short notice ("New lap started!", "The tiles are locked now"): the caller opens it and
// closes it with its own timer. Classic look: the old 380x60 popup in the middle of the page,
// modal, as before. Modern look: a snackbar at the bottom - no dimming, the page under it
// stays usable, a long text wraps instead of running off the card.
UiPopup {
    id: control

    property string text: ""
    readonly property bool snackbar: modern

    inverse: snackbar
    parent: Overlay.overlay

    x: Math.round((parent.width - width) / 2)
    y: snackbar ? parent.height - height - 24 : Math.round((parent.height - height) / 2)
    width: snackbar ? Math.min(parent.width - 32, 560) : 380
    height: snackbar ? Math.max(52, noticeLabel.implicitHeight + topPadding + bottomPadding) : 60
    leftPadding: snackbar ? 20 : padding
    rightPadding: snackbar ? 20 : padding
    topPadding: snackbar ? 14 : padding
    bottomPadding: snackbar ? 14 : padding
    modal: !snackbar
    focus: !snackbar
    palette.text: "white"
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0 }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0 }
    }

    Column {
        anchors.horizontalCenter: control.snackbar ? undefined : parent.horizontalCenter
        anchors.verticalCenter: control.snackbar ? parent.verticalCenter : undefined
        width: control.snackbar ? parent.width : implicitWidth

        Label {
            id: noticeLabel
            anchors.horizontalCenter: control.snackbar ? undefined : parent.horizontalCenter
            width: control.snackbar ? parent.width : implicitWidth
            text: control.text
            wrapMode: control.snackbar ? Text.WordWrap : Text.NoWrap
            color: control.snackbar ? window.ui.bg : Material.foreground
            font.pixelSize: control.snackbar ? 15 : control.font.pixelSize
        }
    }
}
