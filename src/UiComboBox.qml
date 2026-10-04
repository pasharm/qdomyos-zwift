import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.impl 2.15
import QtQuick.Templates 2.15 as T
import QtQuick.Controls.Material 2.15
import QtQuick.Controls.Material.impl 2.15

// ComboBox of the settings pages and the wizard: the Qt 5.15 Material ComboBox, copied as
// is (qtquickcontrols2 5.15, src/imports/controls/material/ComboBox.qml), so nothing changes
// with the modern look off. Modern look: the box is one step lighter than the page (Material
// painted it with dialogColor = the page colour, and it vanished into the page), rounded
// like the text fields and without the shadow; the list is rounded as well.
T.ComboBox {
    id: control

    readonly property bool modern: window.ui.modern

    // Shown text for a raw value: ValueComboBox puts its translated labels here; values
    // missing from the map are shown unchanged
    property var itemLabels: null
    function labelFor(v) {
        return itemLabels && itemLabels.hasOwnProperty(v) ? itemLabels[v] : v
    }

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding,
                             implicitIndicatorHeight + topPadding + bottomPadding)

    topInset: 6
    bottomInset: 6

    leftPadding: padding + (!control.mirrored || !indicator || !indicator.visible ? 0 : indicator.width + spacing)
    rightPadding: padding + (control.mirrored || !indicator || !indicator.visible ? 0 : indicator.width + spacing)

    Material.elevation: flat ? control.pressed || control.hovered ? 2 : 0
                             : control.pressed ? 8 : 2
    Material.background: modern ? window.ui.surfaceHighest : (flat ? "transparent" : undefined)
    Material.foreground: flat ? undefined : Material.primaryTextColor

    delegate: MenuItem {
        id: menuItem
        width: ListView.view.width
        text: control.labelFor(control.textRole ? (Array.isArray(control.model) ? modelData[control.textRole] : model[control.textRole]) : modelData)
        Material.foreground: control.currentIndex === index ? ListView.view.contentItem.Material.accent : ListView.view.contentItem.Material.foreground
        highlighted: control.highlightedIndex === index
        hoverEnabled: control.hoverEnabled

        // Material's MenuItem background; modern: the highlight is a rounded block inset from
        // the edges, not a square bar across the whole list
        background: Rectangle {
            x: control.modern ? 8 : 0
            implicitWidth: 200
            implicitHeight: menuItem.Material.menuItemHeight
            width: menuItem.width - 2 * x
            height: menuItem.height
            radius: control.modern ? 10 : 0
            color: menuItem.highlighted ? menuItem.Material.listHighlightColor : "transparent"

            Ripple {
                width: parent.width
                height: parent.height
                clip: visible
                clipRadius: parent.radius
                pressed: menuItem.pressed
                anchor: menuItem
                active: menuItem.down || menuItem.highlighted
                color: menuItem.Material.rippleColor
            }
        }
    }

    indicator: ColorImage {
        x: control.mirrored ? control.padding : control.width - width - control.padding
        y: control.topPadding + (control.availableHeight - height) / 2
        color: control.modern ? window.ui.textMuted
                              : (control.enabled ? control.Material.foreground : control.Material.hintTextColor)
        opacity: control.modern && !control.enabled ? 0.38 : 1
        source: "qrc:/qt-project.org/imports/QtQuick/Controls.2/Material/images/drop-indicator.png"
    }

    contentItem: T.TextField {
        padding: 6
        leftPadding: control.editable ? 2 : control.mirrored ? 0 : (control.modern ? 16 : 12)
        rightPadding: control.editable ? 2 : control.mirrored ? (control.modern ? 16 : 12) : 0

        text: control.editable ? control.editText : control.displayText

        enabled: control.editable
        autoScroll: control.editable
        readOnly: control.down
        inputMethodHints: control.inputMethodHints
        validator: control.validator
        selectByMouse: control.selectTextByMouse

        font: control.font
        color: control.enabled ? control.Material.foreground : control.Material.hintTextColor
        selectionColor: control.Material.accentColor
        selectedTextColor: control.Material.primaryHighlightedTextColor
        verticalAlignment: Text.AlignVCenter

        cursorDelegate: CursorDelegate { }
    }

    background: Rectangle {
        implicitWidth: 120
        implicitHeight: control.Material.buttonHeight

        radius: control.modern ? 12 : control.flat ? 0 : 2
        color: !control.editable ? control.Material.dialogColor : "transparent"

        layer.enabled: !control.modern && control.enabled && !control.editable && control.Material.background.a > 0
        layer.effect: ElevationEffect {
            elevation: control.Material.elevation
        }

        Rectangle {
            visible: control.editable
            y: parent.y + control.baselineOffset
            width: parent.width
            height: control.activeFocus ? 2 : 1
            color: control.editable && control.activeFocus ? control.Material.accentColor : control.Material.hintTextColor
        }

        Ripple {
            clip: control.flat || control.modern
            clipRadius: control.modern ? 12 : control.flat ? 0 : 2
            x: control.editable && control.indicator ? control.indicator.x : 0
            width: control.editable && control.indicator ? control.indicator.width : parent.width
            height: parent.height
            pressed: control.pressed
            anchor: control.editable && control.indicator ? control.indicator : control
            active: control.pressed || control.visualFocus || control.hovered
            color: control.Material.rippleColor
        }
    }

    popup: T.Popup {
        y: control.editable ? control.height - 5 : 0
        width: control.width
        height: Math.min(contentItem.implicitHeight + topPadding + bottomPadding, control.Window.height - topMargin - bottomMargin)
        transformOrigin: Item.Top
        // The window runs under the status and gesture bars (edge to edge) in both looks, a
        // long list pushed to the top hid its first item under the status bar (#5236)
        topMargin: 12 + window.getTopPadding()
        bottomMargin: 12 + window.getBottomPadding()

        Material.theme: control.Material.theme
        Material.accent: control.Material.accent
        Material.primary: control.Material.primary

        // Modern: the list keeps clear of the rounded corners, the highlight of the first and
        // the last item was a square block in them
        topPadding: control.modern ? 8 : 0
        bottomPadding: control.modern ? 8 : 0

        enter: Transition {
            // grow_fade_in. The end values are given (as in Qt 6): Qt 5.15 restores opacity and
            // scale after the exit to what they were when it began, and a list closed during
            // its own opening kept a part of them - opened again, it stayed invisible and took
            // the next tap on an item nobody could see (the second tap on a combo did nothing)
            NumberAnimation { property: "scale"; from: 0.9; to: 1.0; easing.type: Easing.OutQuint; duration: 220 }
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; easing.type: Easing.OutCubic; duration: 150 }
        }

        exit: Transition {
            // shrink_fade_out
            NumberAnimation { property: "scale"; to: 0.9; easing.type: Easing.OutQuint; duration: 220 }
            NumberAnimation { property: "opacity"; to: 0.0; easing.type: Easing.OutCubic; duration: 150 }
        }

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.delegateModel
            currentIndex: control.highlightedIndex
            highlightMoveDuration: 0

            T.ScrollIndicator.vertical: ScrollIndicator { }
        }

        background: Rectangle {
            radius: control.modern ? 12 : 2
            color: parent.Material.dialogColor

            layer.enabled: control.enabled
            layer.effect: ElevationEffect {
                elevation: 8
            }
        }
    }
}
