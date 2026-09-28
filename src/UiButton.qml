import QtQuick 2.12
import QtQuick.Templates 2.12 as T
import QtQuick.Controls 2.12
import QtQuick.Controls.impl 2.12
import QtQuick.Controls.Material 2.12
import QtQuick.Controls.Material.impl 2.12

// Button of the settings pages. Classic look: the Qt 5.15 Material Button, copied as is
// (qtquickcontrols2 5.15, src/imports/controls/material/Button.qml), so nothing changes
// with the modern look off. Modern look: a flat tonal pill, the accent for highlighted.
T.Button {
    id: control

    readonly property bool modern: window.ui.modern

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)

    topInset: 6
    bottomInset: 6
    padding: 12
    horizontalPadding: modern ? padding + 6 : padding - 4
    spacing: 6

    // Classic: the Material button font (Medium, all caps)
    font.capitalization: modern ? Font.MixedCase : Font.AllUppercase
    font.weight: modern ? Font.DemiBold : Font.Medium

    icon.width: 24
    icon.height: 24
    icon.color: !enabled ? Material.hintTextColor :
        flat && highlighted ? Material.accentColor :
        highlighted ? Material.primaryHighlightedTextColor : Material.foreground

    Material.elevation: flat ? control.down || control.hovered ? 2 : 0
                             : control.down ? 8 : 2
    Material.background: flat ? "transparent" : undefined

    contentItem: IconLabel {
        spacing: control.spacing
        mirrored: control.mirrored
        display: control.display

        icon: control.icon
        text: control.text
        font: control.font
        color: control.modern
               ? (!control.enabled ? window.ui.textMuted
                  : control.highlighted && !control.flat ? window.ui.accentInk
                  : control.flat ? window.ui.accent : window.ui.textMain)
               : (!control.enabled ? control.Material.hintTextColor :
                  control.flat && control.highlighted ? control.Material.accentColor :
                  control.highlighted ? control.Material.primaryHighlightedTextColor : control.Material.foreground)
    }

    background: Rectangle {
        implicitWidth: 64
        implicitHeight: control.Material.buttonHeight

        radius: control.modern ? height / 2 : 2
        color: control.modern
               ? (control.flat ? "transparent"
                  : !control.enabled ? window.ui.alpha(window.ui.textMain, 0.08)
                  : control.highlighted ? window.ui.accent : window.ui.surfaceHighest)
               : (!control.enabled ? control.Material.buttonDisabledColor :
                  control.highlighted ? control.Material.highlightedButtonColor : control.Material.buttonColor)

        PaddedRectangle {
            y: parent.height - 4
            width: parent.width
            height: 4
            radius: 2
            topPadding: -2
            clip: true
            visible: !control.modern && control.checkable && (!control.highlighted || control.flat)
            color: control.checked && control.enabled ? control.Material.accentColor : control.Material.secondaryTextColor
        }

        // The layer is disabled when the button color is transparent so you can do
        // Material.background: "transparent" and get a proper flat button without needing
        // to set Material.elevation as well. The modern pill has no shadow.
        layer.enabled: !control.modern && control.enabled && control.Material.buttonColor.a > 0
        layer.effect: ElevationEffect {
            elevation: control.Material.elevation
        }

        Ripple {
            clipRadius: control.modern ? height / 2 : 2
            width: parent.width
            height: parent.height
            pressed: control.pressed
            anchor: control
            active: control.down || control.visualFocus || control.hovered
            color: control.flat && control.highlighted ? control.Material.highlightedRippleColor : control.Material.rippleColor
        }
    }
}
