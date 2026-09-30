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
    readonly property int modernInset: modern ? 6 : 0

    implicitWidth: implicitBackgroundWidth + leftInset + rightInset
                   || Math.max(contentWidth, placeholder.implicitWidth) + leftPadding + rightPadding
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             contentHeight + topPadding + bottomPadding,
                             placeholder.implicitHeight + topPadding + bottomPadding)

    // Modern: 48 tall with the 6 inset of Material buttons and combo boxes, so the visible
    // field is 36 like the OK button and the combo box next to it
    topInset: modernInset
    bottomInset: modernInset
    topPadding: modern ? 12 : 8
    bottomPadding: modern ? 12 : 16
    leftPadding: modern ? 14 : padding
    rightPadding: modern ? 14 : padding

    color: enabled ? Material.foreground : Material.hintTextColor
    selectionColor: Material.accentColor
    selectedTextColor: Material.primaryHighlightedTextColor
    placeholderTextColor: modern ? window.ui.textMuted : Material.hintTextColor
    verticalAlignment: TextInput.AlignVCenter

    // Modern look: a number field (digit keyboard hint) or a time field ("04:12:00") takes no
    // letters, the OK button next to it saved them as they were. Only the characters of the
    // formats in use pass: sign, decimal point or comma, ":" of times, ' and " of feet and
    // inches. A field with its own validator keeps it; the classic look has none, as before
    readonly property bool numericHint: (inputMethodHints & (Qt.ImhDigitsOnly | Qt.ImhFormattedNumbersOnly)) !== 0
    property bool timeShaped: false
    // An IP address field (set by the page): digits and points only
    property bool ipAddress: false
    Component.onCompleted: timeShaped = /^\d+:\d{2}(:\d{2})?$/.test(text)
    validator: !modern ? null
             : ipAddress ? ipValidator
             : numericHint ? numberValidator
             : timeShaped ? timeValidator : null
    RegExpValidator { id: numberValidator; regExp: /^-?[0-9.,:'"]*$/ }
    RegExpValidator { id: timeValidator; regExp: /^[0-9:]*$/ }
    RegExpValidator { id: ipValidator; regExp: /^[0-9.]*$/ }

    // Modern look: a time field ("00:32:00", the paces) is picked on wheels instead of typed:
    // the text keyboard had no digits row and the digit one no colon, and a bare "320" was
    // saved as garbage. The picker writes the text; the OK button of the row saves it as before
    readOnly: modern && timeShaped
    TapHandler {
        enabled: control.modern && control.timeShaped && control.enabled
        onTapped: pickerLoader.item.openFor(control.text)
    }
    // Made only for the time fields: a settings page has hundreds of text fields
    Loader {
        id: pickerLoader
        active: control.modern && control.timeShaped
        sourceComponent: pickerComponent
    }
    Component {
        id: pickerComponent
    UiPopup {
        id: timePicker
        parent: Overlay.overlay
        modal: true
        // A fixed size: sized by its content, the popup grew out of the corner while the
        // wheels laid out on the first open, and anchors.centerIn followed it
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: 292
        height: 16 + 20 + 4 + 200 + 12 + 48 + 16
        padding: 16
        property bool withSeconds: true

        function openFor(value) {
            var parts = String(value).split(":").map(function (v) { return parseInt(v, 10) || 0 })
            withSeconds = parts.length > 2
            hours.currentIndex = Math.min(parts[0], 99)
            minutes.currentIndex = Math.min(parts[1] || 0, 59)
            seconds.currentIndex = withSeconds ? Math.min(parts[2] || 0, 59) : 0
            open()
        }
        function pad(n) { return n < 10 ? "0" + n : "" + n }

        contentItem: Column {
            spacing: 12
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4
                // Which wheel is what: "00" alone does not say hours or minutes
                Row {
                    spacing: 4
                    Label { text: qsTr("hours"); width: 64; horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: 12; color: window.ui.textMuted }
                    Item { width: timeColon.width; height: 1 }
                    Label { text: qsTr("min"); width: 64; horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: 12; color: window.ui.textMuted }
                    Item { width: timeColon.width; height: 1; visible: timePicker.withSeconds }
                    Label { text: qsTr("sec"); width: 64; horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: 12; color: window.ui.textMuted; visible: timePicker.withSeconds }
                }
                Row {
                    spacing: 4
                    height: 200
                    Tumbler { id: hours; model: 100; visibleItemCount: 5; width: 64; height: 200
                              delegate: timeDigit }
                    Label { id: timeColon; text: ":"; font.pixelSize: 24; anchors.verticalCenter: parent.verticalCenter }
                    Tumbler { id: minutes; model: 60; visibleItemCount: 5; width: 64; height: 200
                              delegate: timeDigit }
                    Label { text: ":"; font.pixelSize: 24; visible: timePicker.withSeconds
                            anchors.verticalCenter: parent.verticalCenter }
                    Tumbler { id: seconds; model: 60; visibleItemCount: 5; width: 64; height: 200
                              visible: timePicker.withSeconds; delegate: timeDigit }
                }
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                UiButton { text: qsTranslate("settings", "Cancel"); flat: true; onClicked: timePicker.close() }
                UiButton {
                    text: qsTranslate("settings", "OK")
                    highlighted: true
                    onClicked: {
                        control.text = timePicker.pad(hours.currentIndex) + ":" + timePicker.pad(minutes.currentIndex)
                                       + (timePicker.withSeconds ? ":" + timePicker.pad(seconds.currentIndex) : "")
                        timePicker.close()
                    }
                }
            }
        }
    }
    }
    Component {
        id: timeDigit
        Label {
            text: index < 10 ? "0" + index : index
            font.pixelSize: 22
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: Tumbler.tumbler && Tumbler.tumbler.currentIndex === index ? window.ui.accent : window.ui.textMain
            opacity: 1.0 - Math.abs(Tumbler.displacement) / (Tumbler.tumbler ? Tumbler.tumbler.visibleItemCount / 2 : 3)
        }
    }
    // A decimal comma (the keyboard of the phone's language) is read by parseFloat as the end
    // of the number: "2,5" saved 2. Turned into a point while typing
    onTextEdited: {
        if (modern && numericHint && text.indexOf(",") >= 0 && !/[:'"]/.test(text)) {
            var pos = cursorPosition
            text = text.replace(/,/g, ".")
            cursorPosition = pos
        }
    }

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
        implicitHeight: control.modern ? 48 - 2 * control.modernInset : 0

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
