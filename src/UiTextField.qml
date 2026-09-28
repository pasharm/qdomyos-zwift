import QtQuick 2.12
import QtQuick.Templates 2.12 as T
import QtQuick.Controls 2.12
import QtQuick.Controls.impl 2.12
import QtQuick.Controls.Material 2.12
import QtQuick.Controls.Material.impl 2.12

// TextField of the settings pages and the lists: the Qt 5.15 Material TextField, copied as
// is (qtquickcontrols2 5.15, src/imports/controls/material/TextField.qml), so nothing
// changes with the modern look off. Modern look: a filled field with rounded corners, like
// the ones of the workout editor, instead of the underline; the accent ring shows focus.
T.TextField {
    id: control

    readonly property bool modern: window.ui.modern

    implicitWidth: implicitBackgroundWidth + leftInset + rightInset
                   || Math.max(contentWidth, placeholder.implicitWidth) + leftPadding + rightPadding
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             contentHeight + topPadding + bottomPadding,
                             placeholder.implicitHeight + topPadding + bottomPadding)

    topPadding: modern ? 12 : 8
    bottomPadding: modern ? 12 : 16
    leftPadding: modern ? 14 : padding
    rightPadding: modern ? 14 : padding

    color: enabled ? Material.foreground : Material.hintTextColor
    selectionColor: Material.accentColor
    selectedTextColor: Material.primaryHighlightedTextColor
    placeholderTextColor: modern ? window.ui.textMuted : Material.hintTextColor
    verticalAlignment: TextInput.AlignVCenter

    cursorDelegate: CursorDelegate { }

    PlaceholderText {
        id: placeholder
        x: control.leftPadding
        y: control.topPadding
        width: control.width - (control.leftPadding + control.rightPadding)
        height: control.height - (control.topPadding + control.bottomPadding)
        text: control.placeholderText
        font: control.font
        color: control.placeholderTextColor
        verticalAlignment: control.verticalAlignment
        elide: Text.ElideRight
        renderType: control.renderType
        visible: !control.length && !control.preeditText && (!control.activeFocus || control.horizontalAlignment !== Qt.AlignHCenter)
    }

    background: Item {
        implicitWidth: 120
        implicitHeight: control.modern ? 48 : 0

        // Classic: the Material underline
        Rectangle {
            visible: !control.modern
            y: control.height - height - control.bottomPadding + 8
            width: parent.width
            height: control.activeFocus || control.hovered ? 2 : 1
            color: control.activeFocus ? control.Material.accentColor
                                       : (control.hovered ? control.Material.primaryTextColor : control.Material.hintTextColor)
        }

        // Modern: a filled rounded field, the accent ring while it has the focus
        UiFrame {
            visible: control.modern
            anchors.fill: parent
            radius: 12
            fill: window.ui.surfaceHighest
            stroke: window.ui.accent
            strokeWidth: control.activeFocus ? 2 : 0
            opacity: control.enabled ? 1 : 0.5
        }
    }
}
