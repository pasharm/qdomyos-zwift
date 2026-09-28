import QtQuick 2.12
import QtQuick.Controls 2.5
import QtQuick.Controls.Material 2.12
import QtGraphicalEffects 1.12
import QtQuick.Window 2.12
import Qt.labs.settings 1.0
import Qt.labs.platform 1.1
import QtMultimedia 5.15

HomeForm {
    objectName: "home"
    deviceLineHidden: gridView.contentY > -gridView.topMargin + 1
    background: Rectangle {
        anchors.fill: parent
        width: parent.fill
        height: parent.fill
        color: window.ui.modern ? window.ui.bg : settings.theme_background_color

        // VoiceOver accessibility - ignore decorative background
        Accessible.role: Accessible.Pane
        Accessible.ignored: true
    }
    signal start_clicked;
    signal stop_clicked;
    signal lap_clicked;
    signal peloton_start_workout;
    signal peloton_abort_workout;
    signal plus_clicked(string name)
    signal minus_clicked(string name)
    signal largeButton_clicked(string name)

    Settings {
        id: settings
        property real ui_zoom: 100.0
        property bool theme_tile_icon_enabled: true
        property string theme_tile_background_color: "#303030"
        property string theme_background_color: "#303030"
        property bool theme_tile_shadow_enabled: true
        property string theme_tile_shadow_color: "#9C27B0"
        property int theme_tile_secondline_textsize: 12
        property bool skipLocationServicesDialog: false
        property bool trainprogram_sound_on_segment: false
    }

    SoundEffect {
        id: trainingProgramSegmentSound
        source: "qrc:/sounds/training-program-segment.wav"
        volume: 0.9
    }

    Connections {
        target: rootItem
        onTrainingProgramIntervalSoundRequested: trainingProgramSegmentSound.play()
    }

    MessageDialog {
        id: messagePelotonAskStart
        text: qsTr("Peloton Workout in progress")
        informativeText: qsTr("Do you want to follow the resistance? ") + rootItem.pelotonProvider
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: {rootItem.pelotonAskStart = false; peloton_start_workout();}
        onNoClicked: {rootItem.pelotonAskStart = false; peloton_abort_workout();}
        visible: rootItem.pelotonAskStart
    }

    Popup {
        id: popupLap
         parent: Overlay.overlay

         x: Math.round((parent.width - width) / 2)
         y: Math.round((parent.height - height) / 2)
         width: 380
         height: 60
         modal: true
         focus: true
         palette.text: "white"
         closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
         enter: Transition
         {
             NumberAnimation { property: "opacity"; from: 0.0; to: 1.0 }
         }
         exit: Transition
         {
             NumberAnimation { property: "opacity"; from: 1.0; to: 0.0 }
         }
         Column {
             anchors.horizontalCenter: parent.horizontalCenter
         Label {
             anchors.horizontalCenter: parent.horizontalCenter
             text: qsTr("New lap started!")
            }
        }
    }

    MessageDialog {
        id: stopConfirmationDialog
        text: qsTr("Stop Workout")
        informativeText: qsTr("Do you really want to stop the current workout?")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: {
            close();
            inner_stop();
        }
        onNoClicked: close()
    }

    // Optional post-workout popup (settings.rpe_feel_popup_enabled) asking for perceived exertion
    // and how the user felt. Saving the FIT file (rootItem.finalizeFitSave) is suspended until this
    // popup is answered, so the values can be embedded in the FIT file before it's written/uploaded.
    Popup {
        id: rpeFeelPopup
        parent: Overlay.overlay

        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: 420
        height: 340
        modal: true
        focus: true
        palette.text: "white"
        closePolicy: Popup.NoAutoClose

        property int selectedRpe: 5
        property int selectedFeel: 50
        readonly property var rpeLabels: [
            qsTr("Rest"), qsTr("Very Light"), qsTr("Light"), qsTr("Moderate"),
            qsTr("Somewhat Hard"), qsTr("Hard"), qsTr("Harder"), qsTr("Very Hard"),
            qsTr("Very Very Hard"), qsTr("Extremely Hard"), qsTr("Maximum Effort")
        ]

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14

            Label {
                text: qsTr("How was this workout?")
                font.bold: true
                font.pixelSize: 18
                width: parent.width
                wrapMode: Text.WordWrap
            }

            Label {
                text: qsTr("Perceived Exertion (RPE): ") + rpeFeelPopup.selectedRpe + " - " + rpeFeelPopup.rpeLabels[rpeFeelPopup.selectedRpe]
                width: parent.width
                wrapMode: Text.WordWrap
            }

            Slider {
                id: rpeSlider
                width: parent.width
                from: 0
                to: 10
                stepSize: 1
                value: rpeFeelPopup.selectedRpe
                onValueChanged: rpeFeelPopup.selectedRpe = value
            }

            Label {
                text: qsTr("How did you feel?")
                width: parent.width
                wrapMode: Text.WordWrap
            }

            ComboBox {
                id: feelCombo
                width: parent.width
                model: [qsTr("Very Bad"), qsTr("Bad"), qsTr("OK"), qsTr("Good"), qsTr("Very Good")]
                currentIndex: 2
                onCurrentIndexChanged: rpeFeelPopup.selectedFeel = currentIndex * 25
            }

            Row {
                spacing: 12
                anchors.horizontalCenter: parent.horizontalCenter

                Button {
                    text: qsTr("Skip")
                    onClicked: {
                        rpeFeelPopup.close();
                        rootItem.finalizeFitSave(-1, -1);
                        finish_stop();
                    }
                }

                Button {
                    text: qsTr("Save")
                    highlighted: true
                    onClicked: {
                        rpeFeelPopup.close();
                        rootItem.finalizeFitSave(rpeFeelPopup.selectedRpe, rpeFeelPopup.selectedFeel);
                        finish_stop();
                    }
                }
            }
        }
    }

    Timer {
        id: popupLapAutoClose
        interval: 2000; running: false; repeat: false
        onTriggered: popupLap.close();
    }

    Timer {
        id: checkStartStopFromWeb
        interval: 200; running: true; repeat: true
        onTriggered: {if(rootItem.stopRequested) {rootItem.stopRequested = false; inner_stop(); }}
    }

    property bool locationServiceRequsted: false

    MessageDialog {
        id: locationServicesDialog
        text: qsTr("Permissions Required")
        informativeText: qsTr("QZ requires both Bluetooth and Location Services to be enabled.\nLocation Services are necessary on Android to allow the app to find Bluetooth devices.\nThe GPS will not be used.\n\nWould you like to enable them?")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: {
            locationServiceRequsted = true
            rootItem.enableLocationServices()
        }
        onNoClicked: remindLocationServicesDialog.visible = true
        visible: !rootItem.locationServices() && !locationServiceRequsted && !settings.skipLocationServicesDialog
    }

    MessageDialog {
        id: remindLocationServicesDialog
        text: qsTr("Reminder Preference")
        informativeText: qsTr("Would you like to be reminded about enabling Location Services next time?")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: settings.skipLocationServicesDialog = false
        onNoClicked: settings.skipLocationServicesDialog = true
        visible: false
    }

    MessageDialog {
        text: qsTr("Restart the app")
        informativeText: qsTr("To apply the changes, you need to restart the app.\nWould you like to do that now?")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: Qt.callLater(Qt.quit)
        onNoClicked: this.visible = false;
        visible: locationServiceRequsted
    }

    Timer {
        interval: 200; running: true; repeat: false
        onTriggered: {
            if(rootItem.firstRun()) {
                stackView.push("Wizard.qml")
            }
        }
    }

    function inner_stop() {
        stop_clicked();
        if (rootItem.rpeFeelPopupEnabled()) {
            rpeFeelPopup.selectedRpe = 5;
            rpeFeelPopup.selectedFeel = 50;
            rpeFeelPopup.open();
        } else {
            finish_stop();
        }
    }

    function finish_stop() {
        rootItem.save_screenshot();
        if(CHARTJS)
            stackView.push("ChartJsTest.qml")
        else
            stackView.push("ChartsEndWorkout.qml")
    }

    start.onClicked: { start_clicked(); }
    stop.onClicked: {
        if (rootItem.confirmStopEnabled()) {
            stopConfirmationDialog.open();
        } else {
            inner_stop();
        }
    }
    lap.onClicked: { lap_clicked(); popupLap.open(); popupLapAutoClose.running = true; }

    Component.onCompleted: {
        console.log("home.qml completed");
    }

    GridView {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.fill: parent
        cellWidth: 175 * settings.ui_zoom / 100
        cellHeight: 130 * settings.ui_zoom / 100
        focus: true
        model: appModel
        leftMargin: { if(OS_VERSION === "Android") (Screen.width % cellWidth) / 2; else (parent.width % cellWidth) / 2; }
        // The grid starts right under the Start/Stop buttons (they end 5 px above the bottom of
        // the top bar), so scrolled tiles leave no empty band under them
        readonly property real gridTopInset: window.lockTiles ? 0 : Math.max(0, rootItem.topBarHeight - 3)
        anchors.topMargin: gridTopInset
        // The gap above the first row is part of the content, so it scrolls away with the tiles.
        // In normal mode it holds the device name line and signal icon at the bottom of the
        // Start/Stop row: at rest the first row is 30 px below the top bar as before, the line
        // hides as soon as the tiles move into the gap (deviceLineHidden), and the grid itself
        // never moves, so nothing jumps. While the tiles are being moved it keeps the first row
        // off the toolbar instead of staying as an empty band.
        topMargin: window.lockTiles ? 30 : rootItem.topBarHeight + 30 - gridTopInset
        onTopMarginChanged: if (contentY <= 0) contentY = -topMargin
        interactive: !window.lockTiles
        id: gridView
        objectName: "gridview"
        // Tiles scroll under the Start/Stop row instead of being drawn over it
        clip: true

        // The app toolbar scrolls away while the tiles scroll down and comes back when they
        // scroll up (Material "hide on scroll"). It follows the finger, not the end of the
        // movement, and main.qml animates its height, so the page does not jump.
        // Hysteresis: the toolbar toggles only after the user has scrolled toolbarToggleDistance
        // in one direction since the last toggle. Collapsing it moves the page under the finger
        // by toolbarShift, which a per-frame check reads as scrolling back, and slow scrolling
        // made the toolbar flicker. The distance must stay larger than that shift, so it is
        // derived from it (a larger font makes the toolbar taller).
        readonly property real toolbarShift: headerToolbar.implicitHeight - headerToolbar.topPadding
        readonly property real toolbarToggleDistance: toolbarShift + 40
        property real toolbarTurnY: 0
        onContentYChanged: {
            // At the top of the gap everything comes back together with the device line. With
            // the gap scrolled away and the first row in full view the toolbar may stay hidden.
            if (window.lockTiles || contentY <= -topMargin + 1) {
                headerToolbar.scrolledAway = false
                toolbarTurnY = contentY
                return
            }
            // Movement of our own making: the view is not being scrolled by the user, or it is
            // resizing while the toolbar animates
            if (!(draggingVertically || flickingVertically) || headerToolbar.animating) {
                toolbarTurnY = contentY
                return
            }
            if (!headerToolbar.scrolledAway) {
                // Only while the tiles still overflow once the toolbar is gone, and not while the
                // view is pulled past its end: otherwise it would spring back to the top and bring
                // the toolbar back at once
                if (contentY - toolbarTurnY > toolbarToggleDistance
                        && contentHeight + topMargin - height > toolbarShift
                        && contentY <= originY + contentHeight - height) {
                    headerToolbar.scrolledAway = true
                    toolbarTurnY = contentY
                } else if (contentY < toolbarTurnY) {
                    toolbarTurnY = contentY
                }
            } else {
                if (toolbarTurnY - contentY > toolbarToggleDistance && !atYEnd) {
                    headerToolbar.scrolledAway = false
                    toolbarTurnY = contentY
                } else if (contentY > toolbarTurnY) {
                    // Not past the end: after pulling beyond it the view springs back, and the
                    // first move up would otherwise bring the toolbar back at once
                    toolbarTurnY = Math.min(contentY, originY + contentHeight - height)
                }
            }
        }
        // With the toolbar hidden, a scroll that stops near the first row settles on it in full
        // view (both bars hidden, no tile cut in half), or, inside the gap, on the nearer edge:
        // the first row or the top, where the toolbar and the device line come back. Not when
        // the list overflows by less than half a tile: its end would become unreachable.
        NumberAnimation { id: snapToFirstRow; target: gridView; property: "contentY"; duration: 150; easing.type: Easing.OutQuad }
        onMovementEnded: {
            if (window.lockTiles || !headerToolbar.scrolledAway)
                return
            if (contentY > -topMargin + 1 && contentY < 0)
                snapToFirstRow.to = contentY < -topMargin / 2 ? -topMargin : 0
            else if (contentY > 0 && contentY < cellHeight / 2 && originY + contentHeight - height >= cellHeight / 2)
                snapToFirstRow.to = 0
            else
                return
            snapToFirstRow.start()
        }
        onMovementStarted: snapToFirstRow.stop()
        Screen.orientationUpdateMask:  Qt.LandscapeOrientation | Qt.PortraitOrientation | Qt.InvertedLandscapeOrientation | Qt.InvertedPortraitOrientation
        Screen.onPrimaryOrientationChanged:{
            if(OS_VERSION === "Android")
                gridView.leftMargin = (Screen.width % cellWidth) / 2;
            else
                gridView.leftMargin = (parent.width % cellWidth) / 2;
        }

        Accessible.ignored: true

        delegate: Item {
            id: id1
            width: 170 * settings.ui_zoom / 100
            height: 125 * settings.ui_zoom / 100

            visible: visibleItem
            Component.onCompleted: console.log("completed " + objectName)

            // VoiceOver accessibility support
            Accessible.role: largeButton ? Accessible.Button : (writable ? Accessible.Pane : Accessible.StaticText)
            Accessible.name: name + (largeButton ? "" : (": " + value))
            Accessible.description: largeButton ? largeButtonLabel : (secondLine !== "" ? secondLine : (writable ? qsTr("Adjustable. Current value: ") + value : qsTr("Current value: ") + value))
            Accessible.focusable: true


            SequentialAnimation on rotation {
                NumberAnimation { to:  2; duration: 60 }
                NumberAnimation { to: -2; duration: 120 }
                NumberAnimation { to:  0; duration: 60 }
                running: loc.currentId !== -1 && id1.state !== "active" && window.lockTiles
                loops: Animation.Infinite; alwaysRunToEnd: true
            }

            states: State {
                name: "active"; when: loc.currentId === gridId && window.lockTiles
                PropertyChanges { target: id1; opacity: 0.3 }
            }

            transitions: Transition { NumberAnimation { property: "opacity"; duration: 200} }

            // Modern tile: a card with the label and a small icon on top, the value in the
            // middle, the zone colour as a bar on the left edge and as the value colour
            Item {
                id: modernTile
                anchors.fill: parent
                visible: window.ui.modern
                readonly property real zoom: settings.ui_zoom / 100
                readonly property bool zoned: !largeButton && valueFontColor !== "white"

                Rectangle {
                    id: modernCard
                    width: 168 * modernTile.zoom
                    height: 123 * modernTile.zoom
                    radius: 16 * modernTile.zoom
                    color: window.ui.surface
                    border.width: 1
                    border.color: window.ui.alpha(window.ui.onSurface, 0.06)
                    visible: !largeButton
                    Accessible.ignored: true
                }

                Rectangle {
                    visible: modernTile.zoned
                    x: 5 * modernTile.zoom
                    width: 4 * modernTile.zoom
                    height: modernCard.height - 36 * modernTile.zoom
                    anchors.verticalCenter: modernCard.verticalCenter
                    radius: width / 2
                    color: valueFontColor
                    Accessible.ignored: true
                }

                Image {
                    id: modernIcon
                    x: 12 * modernTile.zoom
                    y: 10 * modernTile.zoom
                    width: 20 * modernTile.zoom
                    height: 20 * modernTile.zoom
                    source: icon
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    visible: settings.theme_tile_icon_enabled && !largeButton
                    Accessible.ignored: true
                }

                Text {
                    anchors.left: modernIcon.visible ? modernIcon.right : modernCard.left
                    anchors.leftMargin: (modernIcon.visible ? 6 : 12) * modernTile.zoom
                    anchors.right: modernCard.right
                    anchors.rightMargin: 10 * modernTile.zoom
                    anchors.verticalCenter: modernIcon.verticalCenter
                    text: name
                    color: window.ui.onSurfaceVariant
                    font.pixelSize: 13 * modernTile.zoom
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    visible: !largeButton
                    Accessible.ignored: true
                }

                Text {
                    id: modernValue
                    anchors.horizontalCenter: modernCard.horizontalCenter
                    y: 34 * modernTile.zoom
                    width: Math.max(40, modernCard.width - (writable ? 100 : 20) * modernTile.zoom)
                    height: 50 * modernTile.zoom
                    text: value
                    color: modernTile.zoned ? valueFontColor : window.ui.onSurface
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pointSize: valueFontSize * modernTile.zoom
                    fontSizeMode: Text.Fit
                    minimumPointSize: 10
                    font.bold: true
                    visible: !largeButton
                    Accessible.ignored: true
                }

                Text {
                    anchors.top: modernValue.bottom
                    anchors.horizontalCenter: modernCard.horizontalCenter
                    width: modernCard.width - 16 * modernTile.zoom
                    height: 26 * modernTile.zoom
                    text: secondLine
                    color: window.ui.onSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pointSize: settings.theme_tile_secondline_textsize * modernTile.zoom
                    fontSizeMode: Text.Fit
                    minimumPointSize: 7
                    visible: !largeButton
                    Accessible.ignored: true
                }

                RoundButton {
                    id: modernMinus
                    objectName: minusName
                    autoRepeat: true
                    visible: writable && !largeButton
                    x: 6 * modernTile.zoom
                    anchors.verticalCenter: modernValue.verticalCenter
                    width: 44 * modernTile.zoom
                    height: 44 * modernTile.zoom
                    onClicked: minus_clicked(objectName)
                    background: Rectangle {
                        radius: width / 2
                        color: modernMinus.down ? window.ui.alpha(window.ui.accent, 0.35) : window.ui.surfaceHighest
                    }
                    contentItem: Item {
                        UiIcon {
                            anchors.centerIn: parent
                            width: 22 * modernTile.zoom
                            height: 22 * modernTile.zoom
                            name: "remove"
                            color: window.ui.onSurface
                        }
                    }

                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Decrease ") + name
                    Accessible.description: qsTr("Decrease the value of ") + name
                    Accessible.focusable: true
                    Accessible.onPressAction: { minus_clicked(objectName) }
                }

                RoundButton {
                    id: modernPlus
                    objectName: plusName
                    autoRepeat: true
                    visible: writable && !largeButton
                    x: modernCard.width - width - 6 * modernTile.zoom
                    anchors.verticalCenter: modernValue.verticalCenter
                    width: 44 * modernTile.zoom
                    height: 44 * modernTile.zoom
                    onClicked: plus_clicked(objectName)
                    background: Rectangle {
                        radius: width / 2
                        color: modernPlus.down ? window.ui.alpha(window.ui.accent, 0.35) : window.ui.surfaceHighest
                    }
                    contentItem: Item {
                        UiIcon {
                            anchors.centerIn: parent
                            width: 22 * modernTile.zoom
                            height: 22 * modernTile.zoom
                            name: "add"
                            color: window.ui.onSurface
                        }
                    }

                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Increase ") + name
                    Accessible.description: qsTr("Increase the value of ") + name
                    Accessible.focusable: true
                    Accessible.onPressAction: { plus_clicked(objectName) }
                }

                RoundButton {
                    id: modernLargeButton
                    objectName: identificator
                    autoRepeat: true
                    visible: largeButton
                    width: 168 * modernTile.zoom
                    height: 123 * modernTile.zoom
                    onClicked: largeButton_clicked(objectName)
                    background: Rectangle {
                        radius: 16 * modernTile.zoom
                        color: largeButtonColor
                        opacity: modernLargeButton.down ? 0.75 : 1
                    }
                    contentItem: Text {
                        text: largeButtonLabel
                        color: "white"
                        font.pixelSize: 20 * modernTile.zoom
                        font.bold: true
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    Accessible.role: Accessible.Button
                    Accessible.name: largeButtonLabel
                    Accessible.description: name + ": " + largeButtonLabel
                    Accessible.focusable: true
                    Accessible.onPressAction: { largeButton_clicked(objectName) }
                }
            }

            // Classic tile
            Item {
                anchors.fill: parent
                visible: !window.ui.modern

            Rectangle {
                width: 168 * settings.ui_zoom / 100
                height: 123 * settings.ui_zoom / 100
                radius: 3
                border.width: 1
                border.color: (settings.theme_tile_shadow_enabled ? settings.theme_tile_shadow_color : settings.theme_tile_background_color)
                color: settings.theme_tile_background_color
                id: rect

                // Ignore for VoiceOver - decorative background only
                Accessible.ignored: true
            }

            DropShadow {
                visible: settings.theme_tile_shadow_enabled
                anchors.fill: rect
                cached: true
                horizontalOffset: 3
                verticalOffset: 3
                radius: 8.0
                samples: 16
                color: settings.theme_tile_shadow_color
                source: rect
            }

            Timer {
                id: toggleIconTimer
                interval: 500; running: true; repeat: true
                onTriggered: { if(identificator === "inclination" && rootItem.autoInclinationEnabled()) myIcon.visible = !myIcon.visible; else myIcon.visible = settings.theme_tile_icon_enabled && !largeButton; }
            }

            Image {
                id: myIcon
                x: 5
                anchors {
                         bottom: id1.bottom
                }
                width: 48 * settings.ui_zoom / 100
                height: 48 * settings.ui_zoom / 100
                source: icon
                visible: settings.theme_tile_icon_enabled && !largeButton

                // Ignore for VoiceOver - decorative only
                Accessible.ignored: true
            }
            Text {
                objectName: "value"
                id: myValue
                color: valueFontColor
                y: 0
                anchors {
                    horizontalCenter: parent.horizontalCenter
                }
                text: value
                horizontalAlignment: Text.AlignHCenter
                width: Math.max(50, parent.width - (writable ? 100 * settings.ui_zoom / 100 : 12 * settings.ui_zoom / 100))
                height: 58 * settings.ui_zoom / 100
                font.pointSize: valueFontSize * settings.ui_zoom / 100
                fontSizeMode: Text.Fit
                minimumPointSize: 10
                font.bold: true
                visible: !largeButton

                // Ignore for VoiceOver - parent Item handles accessibility
                Accessible.ignored: true
            }
            Text {
                objectName: "secondLine"
                id: secondLineText
                color: "white"
                y: myValue.bottom
                anchors {
                    top: myValue.bottom
                    horizontalCenter: parent.horizontalCenter
                }
                text: secondLine
                horizontalAlignment: Text.AlignHCenter
                width: Math.max(50, parent.width - 12 * settings.ui_zoom / 100)
                height: 24 * settings.ui_zoom / 100
                font.pointSize: settings.theme_tile_secondline_textsize * settings.ui_zoom / 100
                fontSizeMode: Text.Fit
                minimumPointSize: 7
                font.bold: false
                visible: !largeButton

                // Ignore for VoiceOver - parent Item handles accessibility
                Accessible.ignored: true
            }
            Text {
                id: myText
                anchors {
                    top: myIcon.top
                    horizontalCenter: settings.theme_tile_icon_enabled ? undefined : parent.horizontalCenter
                    left: settings.theme_tile_icon_enabled ? parent.left : undefined
                }
                font.bold: true
                font.pointSize: labelFontSize
                fontSizeMode: Text.Fit
                minimumPointSize: 8
                color: "white"
                text: name
                horizontalAlignment: settings.theme_tile_icon_enabled ? Text.AlignLeft : Text.AlignHCenter
                anchors.leftMargin: settings.theme_tile_icon_enabled ? 55 * settings.ui_zoom / 100 : 0
                width: Math.max(40, parent.width - (settings.theme_tile_icon_enabled ? 61 : 12) * settings.ui_zoom / 100)
                height: 40 * settings.ui_zoom / 100
                anchors.topMargin: 20 * settings.ui_zoom / 100
                visible: !largeButton

                // Ignore for VoiceOver - parent Item handles accessibility
                Accessible.ignored: true
            }
            RoundButton {
                objectName: minusName
                autoRepeat: true
                text: "-"
                onClicked: minus_clicked(objectName)
                visible: writable && !largeButton
                anchors.top: myValue.top
                anchors.left: parent.left
                anchors.leftMargin: 2
                width: 48 * settings.ui_zoom / 100
                height: 48 * settings.ui_zoom / 100

                // VoiceOver accessibility
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Decrease ") + name
                Accessible.description: qsTr("Decrease the value of ") + name
                Accessible.focusable: true
                Accessible.onPressAction: { minus_clicked(objectName) }
            }
            RoundButton {
                autoRepeat: true
                objectName: plusName
                text: "+"
                onClicked: plus_clicked(objectName)
                visible: writable && !largeButton
                anchors.top: myValue.top
                anchors.right: parent.right
                anchors.rightMargin: 2
                width: 48 * settings.ui_zoom / 100
                height: 48 * settings.ui_zoom / 100

                // VoiceOver accessibility
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Increase ") + name
                Accessible.description: qsTr("Increase the value of ") + name
                Accessible.focusable: true
                Accessible.onPressAction: { plus_clicked(objectName) }
            }
            RoundButton {
                autoRepeat: true
                objectName: identificator
                text: largeButtonLabel
                onClicked: largeButton_clicked(objectName)
                visible: largeButton
                anchors.fill: rect
                      background: Rectangle {
                          color: largeButtonColor
                            radius: 20
                            }
                font.pointSize: 20 * settings.ui_zoom / 100

                // VoiceOver accessibility
                Accessible.role: Accessible.Button
                Accessible.name: largeButtonLabel
                Accessible.description: name + ": " + largeButtonLabel
                Accessible.focusable: true
                Accessible.onPressAction: { largeButton_clicked(objectName) }
            }
            }
        }
    }

    footer: Item {
        id: footerItem
        width: parent.width
        height: footerHeight
        property real footerHeight: (rootItem.chartFooterVisible ? parent.height / 4 : parent.height / 2)
        property real minHeight: parent.height / 4
        property real maxHeight: parent.height * 3 / 4
        anchors.bottom: parent.bottom
        clip: true
        visible: rootItem.chartFooterVisible || rootItem.videoVisible

        Rectangle {
            id: dragHandle
            width: parent.width / 5
            height: 10
            color: window.ui.modern ? window.ui.accent : "#9C27B0"
            radius: window.ui.modern ? 5 : 0
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            visible: rootItem.chartFooterVisible || rootItem.videoVisible

            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.strokeStyle = "#FFFFFF";
                    ctx.lineWidth = 2;

                    for (var i = 0; i < 3; i++) {
                        ctx.beginPath();
                        ctx.moveTo(0, (i + 1) * parent.height / 4);
                        ctx.lineTo(parent.width, (i + 1) * parent.height / 4);
                        ctx.stroke();
                    }
                }
            }

            MouseArea {
                id: dragArea
                anchors.fill: parent
                cursorShape: Qt.SizeVerCursor

                property real startY: 0
                property real startHeight: 0

                onPressed: {
                    startY = mouseY
                    startHeight = footerItem.height
                }

                onMouseYChanged: {
                    if (pressed) {
                        var newHeight = Math.max(footerItem.minHeight, Math.min(footerItem.maxHeight, startHeight + startY - mouseY))
                        footerItem.footerHeight = newHeight
                    }
                }
            }
        }

        Rectangle {
            id: chartFooterRectangle
            visible: rootItem.chartFooterVisible
            anchors.top: dragHandle.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            ChartFooter {
                anchors.fill: parent
                visible: rootItem.chartFooterVisible
            }
        }

        Rectangle {
            objectName: "footerrectangle"
            visible: rootItem.videoVisible
            anchors.top: dragHandle.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            onVisibleChanged: {
                if(visible === true) {
                    console.log("mediaPlayer onCompleted: " + rootItem.videoPath)
                    console.log("videoRate: " + rootItem.videoRate)
                    videoPlaybackHalf.source = rootItem.videoPath
                    videoPlaybackHalf.seek(rootItem.videoPosition)
                    videoPlaybackHalf.play()
                    videoPlaybackHalf.muted = rootItem.currentCoordinateValid
                } else {
                    videoPlaybackHalf.stop()
                }
            }

            MediaPlayer {
                id: videoPlaybackHalf
                objectName: "videoplaybackhalf"
                autoPlay: false
                playbackRate: rootItem.videoRate

                onError: {
                    if (videoPlaybackHalf.NoError !== error) {
                        console.log("[qmlvideo] VideoItem.onError error " + error + " errorString " + errorString)
                    }
                }
            }

            VideoOutput {
                id: videoPlayer
                anchors.fill: parent
                source: videoPlaybackHalf
            }
        }
    }

    Item {
        id: ghostTile
        visible: loc.currentId !== -1 && window.lockTiles
        x: loc.mouseX - width / 2
        y: loc.mouseY - height / 2
        width: 85 * settings.ui_zoom / 100
        height: 63 * settings.ui_zoom / 100
        z: 200

        Rectangle {
            anchors.fill: parent
            radius: window.ui.modern ? 12 : 3
            color: window.ui.modern ? window.ui.surfaceHighest : settings.theme_tile_background_color
            opacity: 0.9
            border.width: 2
            border.color: window.ui.modern ? window.ui.accent : settings.theme_tile_shadow_color

            Text {
                anchors.centerIn: parent
                color: "white"
                text: loc.tileName
                font.pointSize: 10 * settings.ui_zoom / 100
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                width: parent.width - 8
                wrapMode: Text.WordWrap
            }
        }
    }

    Timer {
        id: autoScrollTimer
        interval: 50
        repeat: true
        running: false
        property real scrollSpeed: 15
        onTriggered: {
            if (loc.currentId === -1) { running = false; return; }
            var edgeZone = 80
            if (loc.mouseY > gridView.height - edgeZone) {
                var factor = (loc.mouseY - (gridView.height - edgeZone)) / edgeZone
                gridView.contentY = Math.min(
                    gridView.contentHeight - gridView.height,
                    gridView.contentY + scrollSpeed * (1 + factor * 2)
                )
            } else if (loc.mouseY < edgeZone) {
                var factor2 = (edgeZone - loc.mouseY) / edgeZone
                gridView.contentY = Math.max(-gridView.topMargin, gridView.contentY - scrollSpeed * (1 + factor2 * 2))
            } else {
                running = false
            }
        }
    }

    MouseArea {
        property int currentId: -1
        property int newIndex
        property int startIndex: -1
        property string tileName: ""
        property real lastScrollY: 0
        property bool isSwiping: false

        function indexAtMouse(mx, my) {
            var cols = Math.max(1, Math.floor(gridView.width / gridView.cellWidth))
            var adjustedY = my + gridView.contentY
            var col = Math.floor(mx / gridView.cellWidth)
            var row = Math.floor(adjustedY / gridView.cellHeight)
            var idx = row * cols + col
            if (idx < 0 || idx >= appModel.count) return -1
            return idx
        }

        id: loc
        enabled: window.lockTiles
        anchors.fill: parent

        onPressed: {
            lastScrollY = mouseY
            isSwiping = false
        }

        onPressAndHold: {
            if (isSwiping) return
            var idx = indexAtMouse(mouseX, mouseY)
            if (idx !== -1) {
                startIndex = idx
                newIndex = idx
                currentId = appModel[idx].gridId
                tileName = appModel[idx].name
            } else {
                currentId = -1
                tileName = ""
            }
        }

        onReleased: {
            autoScrollTimer.running = false
            if (currentId !== -1) {
                var idx = indexAtMouse(mouseX, mouseY)
                if (idx !== -1 && idx !== startIndex)
                    rootItem.moveTile(tileName, idx, startIndex)
            }
            currentId = -1
            startIndex = -1
            tileName = ""
            isSwiping = false
        }

        onPositionChanged: {
            if (currentId === -1) {
                // No drag in progress: scroll the grid like a normal flick
                var dy = mouseY - lastScrollY
                if (Math.abs(dy) > 5) isSwiping = true
                gridView.contentY = Math.max(-gridView.topMargin,
                    Math.min(gridView.contentHeight - gridView.height,
                             gridView.contentY - dy))
                lastScrollY = mouseY
                return
            }
            var edgeZone = 80
            if (mouseY > gridView.height - edgeZone || mouseY < edgeZone)
                autoScrollTimer.running = true
            else
                autoScrollTimer.running = false

            var idx = indexAtMouse(mouseX, mouseY)
            if (idx !== -1 && idx !== newIndex) newIndex = idx
        }
    }
}
