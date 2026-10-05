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
    // Modern look: rootItem comes from C++ only after main.qml is loaded (main.cpp). Until
    // then every binding on it fails and leaves its default, visible, so the first frames
    // drew the classic help text and the unstyled buttons over the searching state. The
    // content waits for it, the background is drawn at once
    contentItem.visible: !window.ui.modern || typeof rootItem !== "undefined"
    // Modern look: the line under Start/Stop only while it names a loaded workout. "<device>
    // found" (homeform.cpp) and the signal are in the drawer header already
    modernInfoShown: {
        // The search for the equipment ("Next search in 12 s") is not in the drawer
        if (searchStatus !== "")
            return true
        var info = typeof rootItem !== "undefined" && rootItem ? rootItem.info : ""
        if (!info)
            return false
        var found = qsTranslate("homeform", "%1 found").split("%1")
        return !(found.length === 2 && info.indexOf(found[0]) === 0
                 && info.length >= found[0].length + found[1].length
                 && info.lastIndexOf(found[1]) === info.length - found[1].length)
    }
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

    UiMessageDialog {
        id: messagePelotonAskStart
        text: qsTr("Peloton Workout in progress")
        informativeText: qsTr("Do you want to follow the resistance? ") + rootItem.pelotonProvider
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: {rootItem.pelotonAskStart = false; peloton_start_workout();}
        onNoClicked: {rootItem.pelotonAskStart = false; peloton_abort_workout();}
        visible: rootItem.pelotonAskStart
    }

    UiNotice {
        id: popupLap
        text: qsTr("New lap started!")
    }

    UiMessageDialog {
        id: stopConfirmationDialog
        text: qsTr("Stop Workout")
        informativeText: qsTr("Do you really want to stop the current workout?")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        yesText: qsTr("Stop")
        noText: qsTr("Cancel")
        destructive: true
        onYesClicked: {
            close();
            inner_stop();
        }
        onNoClicked: close()
    }

    // Optional post-workout popup (settings.rpe_feel_popup_enabled) asking for perceived exertion
    // and how the user felt. Saving the FIT file (rootItem.finalizeFitSave) is suspended until this
    // popup is answered, so the values can be embedded in the FIT file before it's written/uploaded.
    UiPopup {
        id: rpeFeelPopup
        parent: Overlay.overlay

        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        // Modern: a card that fits a phone in portrait (420 is wider than most of them) and as
        // tall as its content; classic: the fixed size as before
        width: modern ? Math.min(parent.width - 48, 440) : 420
        height: modern ? rpeFeelColumn.implicitHeight + 2 * 16 + topPadding + bottomPadding : 340
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
            id: rpeFeelColumn
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14

            Label {
                text: qsTr("How was this workout?")
                // Modern: the title of UiMessageDialog
                font.weight: rpeFeelPopup.modern ? Font.DemiBold : Font.Bold
                font.pixelSize: rpeFeelPopup.modern ? 20 : 18
                color: rpeFeelPopup.modern ? window.ui.textMain : Material.foreground
                width: parent.width
                wrapMode: Text.WordWrap
            }

            Label {
                text: qsTr("Perceived Exertion (RPE): ") + rpeFeelPopup.selectedRpe + " - " + rpeFeelPopup.rpeLabels[rpeFeelPopup.selectedRpe]
                width: parent.width
                wrapMode: Text.WordWrap
                color: rpeFeelPopup.modern ? window.ui.textMain : Material.foreground
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
                color: rpeFeelPopup.modern ? window.ui.textMain : Material.foreground
            }

            UiComboBox {
                id: feelCombo
                width: parent.width
                model: [qsTr("Very Bad"), qsTr("Bad"), qsTr("OK"), qsTr("Good"), qsTr("Very Good")]
                currentIndex: 2
                onCurrentIndexChanged: rpeFeelPopup.selectedFeel = currentIndex * 25
            }

            Row {
                spacing: 12
                anchors.horizontalCenter: parent.horizontalCenter

                UiButton {
                    text: qsTr("Skip")
                    flat: rpeFeelPopup.modern
                    onClicked: {
                        rpeFeelPopup.close();
                        rootItem.finalizeFitSave(-1, -1);
                        finish_stop();
                    }
                }

                UiButton {
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
        id: searchStatusTimer
        // Always running: rootItem.device blinks while no device is connected (it drives the icon),
        // and bluetoothSearchStatus() is empty once a device is connected
        interval: 1000; repeat: true; triggeredOnStart: true; running: true
        onTriggered: {
            searchStatus = rootItem.bluetoothSearchStatus()
            searchStopped = rootItem.bluetoothSearchStopped()
        }
    }

    Timer {
        id: checkStartStopFromWeb
        interval: 200; running: true; repeat: true
        onTriggered: {if(rootItem.stopRequested) {rootItem.stopRequested = false; inner_stop(); }}
    }

    property bool locationServiceRequsted: false
    // Bluetooth and Location as Android reports them now, not only at app start: switched on from
    // the quick settings, the questions about them go away.
    // Home.qml is created before homeform sets rootItem: until then assume "on", so the question
    // doesn't flash at start; setting rootItem re-evaluates the binding with the real value
    property bool locationServicesOn: typeof rootItem === "undefined" || rootItem.locationServices()
    // "No" answered: not asked again until the next start
    property bool locationServicesDeclined: false

    Timer {
        interval: 2000; repeat: true
        // only while a question about them is open: devices without GPS never report Location on
        running: !locationServicesOn && (locationServicesDialog.visible || locationServiceRequsted)
        onTriggered: locationServicesOn = rootItem.refreshLocationServices()
    }

    UiMessageDialog {
        id: locationServicesDialog
        text: qsTr("Permissions Required")
        informativeText: qsTr("QZ requires both Bluetooth and Location Services to be enabled.\nLocation Services are necessary on Android to allow the app to find Bluetooth devices.\nThe GPS will not be used.\n\nWould you like to enable them?")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: {
            locationServiceRequsted = true
            rootItem.enableLocationServices()
        }
        onNoClicked: {
            locationServicesDeclined = true
            remindLocationServicesDialog.visible = true
        }
        visible: !locationServicesOn && !locationServiceRequsted && !locationServicesDeclined && !settings.skipLocationServicesDialog
    }

    UiMessageDialog {
        id: remindLocationServicesDialog
        text: qsTr("Reminder Preference")
        informativeText: qsTr("Would you like to be reminded about enabling Location Services next time?")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: settings.skipLocationServicesDialog = false
        onNoClicked: settings.skipLocationServicesDialog = true
        visible: false
    }

    UiMessageDialog {
        text: qsTr("Restart the app")
        informativeText: qsTr("To apply the changes, you need to restart the app.\nWould you like to do that now?")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: Qt.callLater(window.quitApp)
        onNoClicked: this.visible = false;
        visible: locationServiceRequsted && !locationServicesOn
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
        anchors.top: parent.top
        // TEMP-LOG: QZ-NAV - scrolling of home-grid, to find a page that stops scrolling
        Connections {
            target: gridView
            ignoreUnknownSignals: true
            function onMovementStarted() { console.log("QZ-NAV home-grid move start y=" + Math.round(gridView.contentY) + " h=" + Math.round(gridView.height) + " ch=" + Math.round(gridView.contentHeight) + " interactive=" + gridView.interactive + " enabled=" + gridView.enabled) }
            function onMovementEnded() { console.log("QZ-NAV home-grid move end y=" + Math.round(gridView.contentY)) }
            function onDraggingChanged() { console.log("QZ-NAV home-grid dragging=" + gridView.dragging + " y=" + Math.round(gridView.contentY) + " ch=" + Math.round(gridView.contentHeight) + " h=" + Math.round(gridView.height) + " interactive=" + gridView.interactive) }
            function onContentHeightChanged() { console.log("QZ-NAV home-grid contentHeight=" + Math.round(gridView.contentHeight) + " h=" + Math.round(gridView.height)) }
            function onHeightChanged() { console.log("QZ-NAV home-grid viewport " + Math.round(gridView.width) + "x" + Math.round(gridView.height) + " ch=" + Math.round(gridView.contentHeight) + " y=" + Math.round(gridView.contentY)) }
        }
        anchors.bottom: parent.bottom
        // The tiles stretch to fill the row: the space left over by a whole number of columns
        // is shared between the columns, up to a quarter of the tile width, and what remains
        // centres the grid. Measured on the page, so the Android insets are excluded.
        // The grid is exactly as wide as its columns and centred by the anchor above, not
        // by leftMargin: Qt 5.15 does not recount the columns when leftMargin changes, so
        // after a resize a row could come out one column short
        readonly property real tileBaseWidth: 175 * settings.ui_zoom / 100
        // Every tile is narrower than its cell by tileGap and sits at the cell's left edge, so the
        // last column ends with the gap: the grid is shifted by half the gap, so the outer margins
        // are equal. The modern look also adds the page side margin of its other screens (the
        // "Not connecting?" card, the header): the outer tile edges line up with the card
        readonly property real tileGap: 5 * settings.ui_zoom / 100
        readonly property real tileSideMargin: window.ui.modern ? window.contentSideMargin : 0
        readonly property real tileRowWidth: parent.width - (window.ui.modern ? 2 * tileSideMargin - tileGap : 0)
        // Columns counted on the whole page, as before the margins: on a 360 dp phone the margins
        // would leave one column instead of two. The tiles get narrower there instead (165 dp)
        readonly property int tileColumns: Math.max(1, Math.floor(parent.width / tileBaseWidth))
        cellWidth: Math.floor(Math.min(tileRowWidth / tileColumns, tileBaseWidth * 1.25))
        width: tileColumns * cellWidth
        anchors.horizontalCenterOffset: tileGap / 2
        cellHeight: 130 * settings.ui_zoom / 100
        focus: true
        model: appModel
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
        // Modern look without the line (see modernInfoShown): a small gap only
        topMargin: window.lockTiles ? 30 : rootItem.topBarHeight + (window.ui.modern && !modernInfoShown ? 12 : 30) - gridTopInset
        onTopMarginChanged: if (contentY <= 0) contentY = -topMargin
        interactive: !window.lockTiles
        // Modern look before connection: the grid is still empty but lies over the "searching"
        // state (HomeForm modernEmpty) and would take its taps and scrolling
        enabled: !(window.ui.modern && rootItem.labelHelp)
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
        // A scroll that stops settles on the nearest whole row at the top (no tile cut in half)
        // or on the end of the list, whichever is nearer; inside the gap, on the nearer edge:
        // the first row or the top with the device line. It runs once the movement has ended,
        // so a flick settles by the row where it stopped by itself, not by the one where the
        // finger let go. With the toolbar shown or hidden alike: the snap is not a finger move,
        // so it does not toggle the toolbar. Moving a tile scrolls the grid by contentY, which
        // ends no movement, so it does not snap. Off in Settings (ui.tileSnap)
        // The end is taken from the grid height at the moment the movement ends: when the
        // toolbar is still sliding away, the grid grows after that and the end moves up, so
        // the snap could stop past it. Back within the bounds once it is done
        NumberAnimation { id: snapToRow; target: gridView; property: "contentY"; duration: 150; easing.type: Easing.OutQuad
                          onFinished: gridView.returnToBounds() }
        onMovementEnded: {
            if (window.lockTiles || !window.ui.tileSnap)
                return
            var endY = originY + contentHeight - height
            var to
            if (contentY <= -topMargin + 1 || endY <= -topMargin)
                return
            if (contentY < 0) {
                to = contentY < -topMargin / 2 ? -topMargin : Math.min(0, endY)
            } else {
                var row = originY + Math.round((contentY - originY) / cellHeight) * cellHeight
                to = row > endY || Math.abs(endY - contentY) < Math.abs(row - contentY) ? endY : row
            }
            if (Math.abs(to - contentY) < 1)
                return
            snapToRow.to = to
            snapToRow.start()
        }
        onMovementStarted: snapToRow.stop()
        Screen.orientationUpdateMask:  Qt.LandscapeOrientation | Qt.PortraitOrientation | Qt.InvertedLandscapeOrientation | Qt.InvertedPortraitOrientation
        Screen.onPrimaryOrientationChanged:{
            // Nothing to recompute: cellWidth and the grid width follow the page width
        }

        Accessible.ignored: true

        delegate: Item {
            id: id1
            width: gridView.cellWidth - gridView.tileGap
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

                // UiFrame, not Rectangle.border: a thin border breaks up on Android
                UiFrame {
                    id: modernCard
                    width: modernTile.width - 2 * modernTile.zoom
                    height: 123 * modernTile.zoom
                    radius: 16 * modernTile.zoom
                    fill: window.ui.surface
                    stroke: window.ui.alpha(window.ui.textMain, 0.06)
                    strokeWidth: 1
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
                    visible: settings.theme_tile_icon_enabled && !largeButton
                    Accessible.ignored: true
                    // Some tile icons are plain black and some plain white, so either kind
                    // gets lost on one of the themes: paint those in the text colour.
                    // Coloured icons (heart, watt, kcal, resistance) stay as they are.
                    readonly property bool mono: /\/(cadence|clock|elevationgain|fan|inclination|joul|odometer|pace|speed)\.png$/.test(String(source))
                    layer.enabled: mono
                    layer.effect: ColorOverlay { color: window.ui.textMuted }
                }

                Text {
                    anchors.left: modernIcon.visible ? modernIcon.right : modernCard.left
                    anchors.leftMargin: (modernIcon.visible ? 6 : 12) * modernTile.zoom
                    anchors.right: modernCard.right
                    anchors.rightMargin: 10 * modernTile.zoom
                    anchors.verticalCenter: modernIcon.verticalCenter
                    text: name
                    color: window.ui.textMuted
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
                    color: modernTile.zoned ? window.ui.zoneInk(valueFontColor) : window.ui.textMain
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
                    color: window.ui.textMuted
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
                    // A touch area of 64 x 80, easier to hit while riding, around the circle as it
                    // always looked: 32 (a 44 button less the 6 insets of Material), 12 from the
                    // edge, on the value's centre
                    x: (6 - 8) * modernTile.zoom
                    y: modernValue.y + modernValue.height / 2 + 3 * modernTile.zoom - height / 2
                    width: 64 * modernTile.zoom
                    height: 80 * modernTile.zoom
                    topInset: 0
                    bottomInset: 0
                    leftInset: 0
                    rightInset: 0
                    onClicked: minus_clicked(objectName)
                    background: Item {
                        Rectangle {
                            x: 14 * modernTile.zoom
                            y: parent.height / 2 - 19 * modernTile.zoom
                            width: 32 * modernTile.zoom
                            height: 32 * modernTile.zoom
                            radius: width / 2
                            color: modernMinus.down ? window.ui.alpha(window.ui.accent, 0.35) : window.ui.surfaceHighest
                            UiIcon {
                                anchors.centerIn: parent
                                width: 22 * modernTile.zoom
                                height: 22 * modernTile.zoom
                                name: "remove"
                                color: window.ui.textMain
                            }
                        }
                    }
                    contentItem: Item {}

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
                    // A touch area of 64 x 80, easier to hit while riding, around the circle as it
                    // always looked: 32 (a 44 button less the 6 insets of Material), 12 from the
                    // edge, on the value's centre
                    x: modernCard.width - width + (8 - 6) * modernTile.zoom
                    y: modernValue.y + modernValue.height / 2 + 3 * modernTile.zoom - height / 2
                    width: 64 * modernTile.zoom
                    height: 80 * modernTile.zoom
                    topInset: 0
                    bottomInset: 0
                    leftInset: 0
                    rightInset: 0
                    onClicked: plus_clicked(objectName)
                    background: Item {
                        Rectangle {
                            x: 18 * modernTile.zoom
                            y: parent.height / 2 - 19 * modernTile.zoom
                            width: 32 * modernTile.zoom
                            height: 32 * modernTile.zoom
                            radius: width / 2
                            color: modernPlus.down ? window.ui.alpha(window.ui.accent, 0.35) : window.ui.surfaceHighest
                            UiIcon {
                                anchors.centerIn: parent
                                width: 22 * modernTile.zoom
                                height: 22 * modernTile.zoom
                                name: "add"
                                color: window.ui.textMain
                            }
                        }
                    }
                    contentItem: Item {}

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
                    width: modernTile.width - 2 * modernTile.zoom
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
                width: id1.width - 2 * settings.ui_zoom / 100
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
                         // parent, not id1: the classic tile sits in a wrapper filling id1
                         bottom: parent.bottom
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

        // UiFrame: in the modern look a thin border breaks up on Android
        UiFrame {
            anchors.fill: parent
            radius: window.ui.modern ? 12 : 3
            fill: window.ui.modern ? window.ui.surfaceHighest : settings.theme_tile_background_color
            opacity: 0.9
            strokeWidth: 2
            stroke: window.ui.modern ? window.ui.accent : settings.theme_tile_shadow_color

            Text {
                anchors.centerIn: parent
                color: window.ui.ink("white")
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
            var cols = gridView.tileColumns
            var adjustedY = my + gridView.contentY
            var col = Math.floor((mx - gridView.x) / gridView.cellWidth)
            if (col < 0 || col >= cols) return -1
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
