import QtQuick 2.12
import QtQuick.Controls 2.5
import QtQuick.Controls.Material 2.12
import QtGraphicalEffects 1.12
import Qt.labs.settings 1.0
import QtQml 2.15

Page {

    title: qsTr("QZ Fitness")
    id: page

    // VoiceOver accessibility - ignore Page itself, only children are accessible
    Accessible.ignored: true

    property alias start: start
    property alias stop: stop
    property alias lap: lap
    property alias row: row
    // Set by Home.qml while the tiles are scrolled into the gap under the Start/Stop row
    property bool deviceLineHidden: false
    // Set by Home.qml: whether the modern status line has anything the drawer does not show
    property bool modernInfoShown: true
    // Search for the equipment ("Next search in 12 s"), set by Home.qml while no device is connected
    property string searchStatus: ""
    // The search has stopped: the empty state says so instead of "Looking for your equipment"
    property bool searchStopped: false
    // Gym mode: the trainer picked in the window, set by Home.qml until it is connected
    property string connectingDevice: ""
    // Home.qml sets the new values from the settings page in it (the background color of the top bar)
    property alias homeFormSettings: settings
    // Modern look, for the grid of tiles in Home.qml: where the first row starts - 16 dp under the
    // letters of the status line, or under the buttons without it (scrolled tiles stop 4 dp above). One line of the status counts: two lines come only before the first
    // connection, when the grid is empty, and they grow down
    // The top bar can be turned off (top_bar_enabled: topBarHeight 0, no labels): no controls then,
    // the grid and the status line as before
    readonly property bool modernControlsShown: window.ui.modern && topBar.height > 0
    // How much of the app toolbar is shown, 0..1: it scrolls away with the tiles and main.qml
    // animates its height down to the status bar inset (headerToolbar.scrolledAway)
    readonly property real toolbarShown: headerToolbar.implicitHeight > headerToolbar.topPadding
                                         ? Math.max(0, Math.min(1, (headerToolbar.height - headerToolbar.topPadding)
                                                                   / (headerToolbar.implicitHeight - headerToolbar.topPadding)))
                                         : 1
    readonly property real modernControlsBottom: topBar.y + modernRow.y + modernRow.height
    readonly property real modernTilesTop: modernInfoShown ? topBar.y + modernInfo.y + statusLine.height + 13
                                                           : modernControlsBottom + 16

    Settings {
	     id: settings
	     Component.onCompleted: window.retakeSettingsSnapshot(settings)
		  property real ui_zoom: 100.0
		  property bool theme_tile_icon_enabled: true
		  property string theme_background_color: "#303030"
		}

    Item {
        width: parent.width
        height: rootItem.topBarHeight
        id: topBar
        visible: !window.lockTiles

        // One line of the modern status line at the text size, for the place of the tiles under it
        Text {
            id: statusLine
            visible: false
            text: "A"
            font.pixelSize: window.ui.fontCaption
        }

        // Modern controls. They forward to the classic buttons below, which Home.qml listens to.
        // The workout state picks them: one wide Start or Pause, while paused Resume and Stop -
        // stopping takes a pause first, so a running workout is not ended by a slip of the finger.
        // The row is as wide in every state, so Bluetooth stays where it is
        Row {
            id: modernRow
            visible: page.modernControlsShown
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            // 12 dp under the toolbar: the top bar starts 8 dp above its edge. With the toolbar
            // scrolled away nothing covers those 8 dp, so the row follows it up: 12 dp under the
            // status bar as well
            anchors.topMargin: 12 + 8 * page.toolbarShown
            spacing: 8

            readonly property bool paired: rootItem.workoutPaused
            // Room left at the ends of a pill beside its label: smaller in the 148 dp pair, so
            // "Продолжить" (ru) and the like fit there and the short variant is not needed
            readonly property int labelInset: paired ? 12 : 24
            // A new set of buttons fades in and takes taps only once it is all there: the second
            // tap of a double tap on Pause would otherwise land on Stop (or Resume) under the finger
            readonly property int workoutState: rootItem.workoutStopped ? 2 : (rootItem.workoutPaused ? 1 : 0)
            property real shown: 1
            readonly property bool ready: shown === 1
            onWorkoutStateChanged: appear.restart()
            NumberAnimation {
                id: appear
                target: modernRow
                property: "shown"
                from: 0
                to: 1
                duration: 500
                easing.type: Easing.OutCubic
            }

            Item {
                width: 48
                height: 56
                Rectangle {
                    anchors.centerIn: parent
                    width: 48
                    height: 48
                    radius: 24
                    color: rootItem.device ? window.ui.alpha(window.ui.ok, 0.16) : window.ui.surfaceHigh
                    UiIcon {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        name: rootItem.device ? "bluetooth_connected" : "bluetooth"
                        color: rootItem.device ? window.ui.ok : window.ui.textMuted
                    }
                    // No device yet: a tap searches right away instead of waiting for the next search;
                    // with a device connected it restarts the DirCon (Wi-Fi) servers, see bluetoothSearchNow(),
                    // and looks for the chosen heart rate sensor again (reconnectHeartRateBelt() waits for the device)
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { rootItem.bluetoothSearchNow(); rootItem.reconnectHeartRateBelt(); }

                        // VoiceOver/TalkBack: a button that searches. The state is in the name: TalkBack (Qt 5.15)
                        // reads no description when the name is set
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Bluetooth connection") + ": " + (rootItem.device ? qsTr("Device connected") : qsTr("Device not connected"))
                        Accessible.description: rootItem.device ? qsTr("Device connected") : qsTr("Device not connected")
                        Accessible.focusable: true
                        Accessible.onPressAction: { rootItem.bluetoothSearchNow(); rootItem.reconnectHeartRateBelt(); }
                    }
                }
            }

            AbstractButton {
                id: modernStart
                // alone it takes the place of two buttons and the gap between them
                width: modernRow.paired ? 148 : 248
                height: 56
                opacity: modernRow.shown
                enabled: modernRow.ready
                onClicked: start.clicked()
                background: Rectangle {
                    radius: height / 2
                    // Steady green while stopped/paused ("Start"), accent while running ("Pause");
                    // the classic blinking startColor is not used here
                    color: rootItem.startIcon.indexOf("pause") >= 0 ? window.ui.accent : window.ui.accentOf("green")
                    opacity: modernStart.down ? 0.8 : 1
                }
                contentItem: Item {
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        UiIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26
                            height: 26
                            name: rootItem.startIcon.indexOf("pause") >= 0 ? "pause" : "play_arrow"
                            color: window.ui.accentInk
                            visible: rootItem.startIcon !== ""
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            // At most what the pill has left beside the icon: with the elide on, a
                            // label with a long and a short variant ("Resume" in ru, de, cs ...)
                            // shows the first that fits, like the classic button
                            width: Math.min(implicitWidth, modernStart.width - modernRow.labelInset - 26 - 6)
                            elide: Text.ElideRight
                            text: rootItem.startText
                            color: window.ui.accentInk
                            font.pixelSize: window.ui.fontBody
                            font.weight: Font.DemiBold
                            visible: text !== ""
                            // the button carries the name; this node gave the screen reader both
                            // variants ("Продолжить.Далее" in the emulator dump)
                            Accessible.ignored: true
                        }
                    }
                }
                Accessible.role: Accessible.Button
                // only the long variant of the label (see the Label above)
                Accessible.name: rootItem.startText.split("\u009C")[0]
                Accessible.description: qsTr("Start workout")
                Accessible.focusable: true
                Accessible.onPressAction: if (modernStart.enabled) start.clicked()
            }

            // Only while paused, in the place of Lap: the reminder to end the workout
            AbstractButton {
                id: modernStop
                visible: modernRow.paired
                width: 148
                height: 56
                opacity: modernRow.shown
                enabled: modernRow.ready
                onClicked: stop.clicked()
                // Filled red once the workout is long (homeform workoutLong): the pause most likely
                // ends it. A short one keeps Resume the main button, Stop is outlined as it was
                readonly property bool filled: rootItem.workoutLong
                background: UiFrame {
                    radius: height / 2
                    fill: modernStop.filled ? window.ui.alpha(window.ui.danger, modernStop.down ? 0.8 : 1)
                                            : (modernStop.down ? window.ui.surfaceHighest : window.ui.surfaceHigh)
                    stroke: window.ui.alpha(window.ui.danger, 0.45)
                    strokeWidth: modernStop.filled ? 0 : 1
                }
                contentItem: Item {
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        UiIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24
                            height: 24
                            name: "stop"
                            color: modernStop.filled ? window.ui.dangerInk : window.ui.danger
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            // at most what the pill has left beside the icon, as on Start
                            width: Math.min(implicitWidth, modernStop.width - modernRow.labelInset - 24 - 6)
                            elide: Text.ElideRight
                            text: rootItem.stopText
                            color: modernStop.filled ? window.ui.dangerInk : window.ui.textMain
                            font.pixelSize: window.ui.fontBody
                            font.weight: Font.DemiBold
                            visible: text !== ""
                            Accessible.ignored: true
                        }
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: rootItem.stopText
                Accessible.description: qsTr("Stop workout")
                Accessible.focusable: true
                Accessible.onPressAction: if (modernStop.enabled) stop.clicked()
            }

            // Hidden while paused: Stop takes its place
            AbstractButton {
                id: modernLap
                visible: !modernRow.paired
                width: 48
                height: 56
                enabled: rootItem.lap && modernRow.ready
                opacity: (rootItem.lap ? 1 : 0.4) * modernRow.shown
                onClicked: lap.clicked()
                background: Rectangle {
                    anchors.centerIn: parent
                    width: 48
                    height: 48
                    radius: 24
                    color: modernLap.down ? window.ui.surfaceHighest : window.ui.surfaceHigh
                }
                contentItem: Item {
                    UiIcon {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        name: "flag"
                        color: window.ui.textMain
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Lap")
                Accessible.description: qsTr("Record a new lap")
                Accessible.focusable: true
                Accessible.onPressAction: if (modernLap.enabled) lap.clicked()
            }
        }

        Row {
            id: row
            visible: !window.ui.modern
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            height: topBar.height - 20
            spacing: 5
            padding: 5

            Rectangle {
                width: 50
                height: row.height
					 color: settings.theme_background_color
                Accessible.ignored: true

                Column {
                    id: column
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: row.height
                    spacing: 0
                    padding: 0
                    Accessible.ignored: true

                    Rectangle {
                        width: 50
                        height: row.height
                        color: settings.theme_background_color
                        Accessible.ignored: true

                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            id: treadmill_connection
                            width: 48
                            height: row.height - 52
                            source: "icons/icons/bluetooth-icon.png"
                            enabled: rootItem.device
                            smooth: true

                            // VoiceOver accessibility: the MouseArea below is the button, read once
                            Accessible.ignored: true
                        }
                        ColorOverlay {
                            anchors.fill: treadmill_connection
                            source: treadmill_connection
                            color: treadmill_connection.enabled ? "#00000000" : "#B0D3d3d3"
                        }
                        // No device yet: a tap searches right away instead of waiting for the next search;
                        // with a device connected it restarts the DirCon (Wi-Fi) servers, see bluetoothSearchNow(),
                        // and looks for the chosen heart rate sensor again (reconnectHeartRateBelt() waits for the device)
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { rootItem.bluetoothSearchNow(); rootItem.reconnectHeartRateBelt(); }

                            // VoiceOver/TalkBack: a button that searches. The state is in the name: TalkBack (Qt 5.15)
                            // reads no description when the name is set
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Bluetooth connection") + ": " + (rootItem.device ? qsTr("Device connected") : qsTr("Device not connected"))
                            Accessible.description: rootItem.device ? qsTr("Device connected") : qsTr("Device not connected")
                            Accessible.focusable: true
                            Accessible.onPressAction: { rootItem.bluetoothSearchNow(); rootItem.reconnectHeartRateBelt(); }
                        }
                    }
                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        id: treadmill_signal
                        width: 24
                        height: row.height - 76
                        source: rootItem.signal
                        smooth: true
                        Accessible.ignored: true
                        // It hangs below the row, into the gap above the tiles
                        visible: !page.deviceLineHidden
                    }
                }
            }

            Rectangle {
                width: 120
                height: row.height
					 color: settings.theme_background_color
                Accessible.ignored: true

                RoundButton {
                    icon.source: rootItem.startIcon
                    icon.height: row.height - 54
                    icon.width: 46
                    text: rootItem.startText
                    // fixed width: keep the size it had before the Text size setting
                    Binding on font.pixelSize { when: window.scaledFontPx > 0; value: window.appFontPx; restoreMode: Binding.RestoreBindingOrValue }
                    enabled: true
                    id: start
                    width: 120
                    height: row.height - 4

                    // VoiceOver accessibility
                    Accessible.role: Accessible.Button
                    // the label may hold a long and a short variant (U+009C between them, the
                    // button shows the one that fits): the screen reader gets only the long one
                    Accessible.name: rootItem.startText.split("\u009C")[0]
                    Accessible.description: qsTr("Start workout")
                    Accessible.focusable: true
                }
                ColorOverlay {
                    anchors.fill: start
                    source: start
                    color: rootItem.startColor
                    enabled: rootItem.startColor === "red" ? true : false
                    // startColor() toggles on every read: the blink needs an odd number of reads per
                    // tick (the signal argument, color, enabled), so use color here. A transparent
                    // overlay would still draw the button a second time, its shadow cut square
                    visible: color.a > 0
                    // Red on the pill only: the faint tail of the shadow reaches far past the button,
                    // and tinted it shows as a red square wherever the source ends
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Item {
                            width: start.width
                            height: start.height
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 6 // the insets of RoundButton in the Material style
                                radius: start.radius
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: 120
                height: row.height
					 color: settings.theme_background_color
                Accessible.ignored: true

                RoundButton {
                    icon.source: rootItem.stopIcon
                    icon.height: row.height - 54
                    icon.width: 46
                    text: rootItem.stopText
                    Binding on font.pixelSize { when: window.scaledFontPx > 0; value: window.appFontPx; restoreMode: Binding.RestoreBindingOrValue }
                    enabled: true
                    id: stop
                    width: 120
                    height: row.height - 4

                    // VoiceOver accessibility
                    Accessible.role: Accessible.Button
                    Accessible.name: rootItem.stopText
                    Accessible.description: qsTr("Stop workout")
                    Accessible.focusable: true
                }
                ColorOverlay {
                    anchors.fill: stop
                    source: stop
                    color: rootItem.stopColor
                    enabled: rootItem.stopColor === "red" ? true : false
                    visible: color.a > 0
                }
            }

            Rectangle {
                id: item2
                width: 50
                height: row.height
					 color: settings.theme_background_color
                Accessible.ignored: true

                RoundButton {
                    anchors.verticalCenter: parent.verticalCenter
                    id: lap
                    width: 48
                    height: row.height - 52
                    icon.source: "icons/icons/lap.png"
                    icon.width: 48
                    icon.height: 48
                    enabled: rootItem.lap
                    smooth: true

                    // VoiceOver accessibility
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Lap")
                    Accessible.description: qsTr("Record a new lap")
                    Accessible.focusable: true
                }
                ColorOverlay {
                    anchors.fill: lap
                    source: lap
                    color: lap.enabled ? "#00000000" : "#B0D3d3d3"
                    visible: color.a > 0
                }
            }
        }

        Row {
            id: row1
            width: parent.width
            anchors.bottom: row.bottom
            // a bigger text grows down into the gap above the tiles, not up into the buttons
            anchors.bottomMargin: window.textScale !== 1 ? -10 - Math.round(statusLabel.height * (1 - 1 / window.textScale)) : -10

            Label {
                id: statusLabel
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                // the search status may have two lines ("<device> found" and the countdown): the line
                // grows upwards, so they are set closer to keep the first one off the buttons
                horizontalAlignment: Text.AlignHCenter
                lineHeight: text.indexOf("\n") >= 0 ? 0.8 : 1
                text: page.searchStatus !== "" ? page.searchStatus : rootItem.info
                visible: !window.ui.modern && !page.deviceLineHidden
                color: Material.foreground
                font.pixelSize: (window.textScale === 1 ? Qt.application.font.pixelSize : window.fontPx(window.appFontPx))
            }
        }

        // Modern status line: signal bars and the device status on one line
        Row {
            id: modernInfo
            // Over the empty state only the last device found and the time to the next search
            // ("HRM-Pro found" and "Next search in 12 s" under it): its heading says the rest
            // ("Looking for your equipment"). The line has its own place under the buttons, so
            // it comes and goes without moving the page
            readonly property bool countdown: !page.searchStopped && page.searchStatus !== "" && page.connectingDevice === ""
                                              && page.searchStatus !== qsTranslate("homeform", "Searching for the device...")
            // with the top bar off it is not shown either: its place is under the controls.
            // It is the state of the buttons, so it stays with them while the tiles scroll
            visible: page.modernControlsShown && page.modernInfoShown && (!modernEmpty.visible || countdown)
            anchors.horizontalCenter: parent.horizontalCenter
            // 8 dp from the buttons to the letters; a second line grows down (see modernTilesTop)
            anchors.top: modernRow.bottom
            anchors.topMargin: 5
            spacing: 8
            // Bluetooth is off: a warning, drawn here because the app font has no warning sign
            readonly property bool bluetoothOff: page.searchStatus === qsTranslate("homeform", "Bluetooth is off")

            Rectangle {
                visible: modernInfo.bluetoothOff
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                radius: 8
                color: window.ui.danger
                Accessible.ignored: true
                Label {
                    anchors.centerIn: parent
                    text: "!"
                    color: window.ui.dangerInk
                    font.pixelSize: window.ui.modern ? window.ui.fontCaption : 12
                    font.bold: true
                }
            }
            Image {
                visible: !modernEmpty.visible
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 13
                fillMode: Image.PreserveAspectFit
                source: rootItem.signal
                smooth: true
                Accessible.ignored: true
                // The bars are white: on a light page paint them in the text colour
                layer.enabled: !window.ui.dark
                layer.effect: ColorOverlay { color: window.ui.textMuted }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                // "Connecting..." is the untranslated start value of homeform::m_info: before the
                // first search it means the same as the search status
                text: page.searchStatus !== "" ? page.searchStatus : (rootItem.info === "Connecting..." ? qsTranslate("homeform", "Searching for the device...") : rootItem.info)
                horizontalAlignment: Text.AlignHCenter
                // two lines ("<device> found" and the countdown) grow down, set closer
                lineHeight: text.indexOf("\n") >= 0 ? 0.8 : 1
                color: modernInfo.bluetoothOff ? window.ui.danger : window.ui.textMuted
                font.pixelSize: window.ui.fontCaption
            }
        }

        Label {
            id: lblHelp
            width: parent.width
            leftPadding: window.contentSideMargin
            rightPadding: window.contentSideMargin
            anchors.top: row1.bottom
            anchors.topMargin: 30
            text: qsTr("This app should automatically connect to your bike/treadmill/rower. <b>If it doesn't, please check</b>:<br>1) your Echelon/Domyos App MUST be closed while qdomyos-zwift is running;<br>2) both Bluetooth and Bluetooth permissions MUST be enabled<br>3) your bike/treadmill/rower should be turned on BEFORE starting this app<br>4) try to restart your device<br><br>If your bike/treadmill disconnects every 30 seconds try to disable the 'virtual device' setting on the left bar.<br><br>In case of issues, please feel free to contact me at roberto.viola83@gmail.com.<br><br><b>Have a nice ride!</b><br/ ><i>QZ specifically disclaims liability for<br>incidental or consequential damages and assumes<br>no responsibility or liability for any loss<br>or damage suffered by any person as a result of<br>the use or misuse of the app.</i><br><br>Roberto Viola")
            wrapMode: Label.WordWrap
            // The look first: the hidden one then never reads rootItem, which is not there yet
            // in the first second (see main.qml rootReady) and would leave both shown
            visible: !window.ui.modern && rootItem.labelHelp
        }

        // Modern look: while nothing is connected, a short "searching" state instead of the
        // wall of text, and a short checklist cut from the same help text (already translated)
        Flickable {
            id: modernEmpty
            visible: window.ui.modern && rootItem.labelHelp
            anchors.top: row1.bottom
            anchors.topMargin: 24
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width - 2 * window.contentSideMargin, 560)
            height: page.height - (row1.y + row1.height) - 24
            contentHeight: emptyColumn.height + 24
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            // qsTr inside an expression looks the text up under the context of the file that
            // creates the page (Home), not this one: the context is given explicitly
            Column {
                id: emptyColumn
                width: parent.width
                spacing: 12

                Label {
                    width: parent.width
                    topPadding: 4
                    text: page.connectingDevice !== "" ? qsTranslate("homeform", "Connecting to %1...").arg(page.connectingDevice)
                          : page.searchStopped ? qsTranslate("HomeForm.ui", "Equipment not found") : qsTranslate("HomeForm.ui", "Looking for your equipment…")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: window.ui.textMain
                    font.pixelSize: window.ui.fontTitle
                    font.weight: Font.DemiBold
                }

                Label {
                    width: parent.width
                    // Connecting to the picked trainer: nothing to turn on, the heading says it all
                    visible: page.connectingDevice === ""
                    text: page.searchStopped ? qsTranslate("HomeForm.ui", "Turn on your bike, treadmill or rower, then tap the Bluetooth icon at the top to search again.")
                                             : qsTranslate("HomeForm.ui", "Turn on your bike, treadmill or rower: QZ connects to it automatically.")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: window.ui.textMuted
                    font.pixelSize: window.ui.fontLabel
                }

                Item { width: 1; height: 8 }

                // "Not connecting?": a short checklist, always open, cut from the old help text
                // (already translated): the numbered checks and the hint about the virtual device,
                // then the rest (the e-mail, the disclaimer, the author) in small muted text.
                // Without the lead sentence (the subtitle says it) and the bold "If it doesn't,
                // please check" (the heading says it)
                Rectangle {
                    width: parent.width
                    height: helpColumn.height + 32
                    radius: window.ui.radius
                    color: window.ui.surface

                    // [checks, rest]
                    readonly property var helpParts: {
                        var t = lblHelp.text
                        var b = t.indexOf("<b>")
                        if (b < 0)
                            return [t, ""]
                        t = t.substring(b)
                        var br = t.indexOf("<br>")
                        if (br < 0)
                            return [t, ""]
                        t = t.substring(br + 4)
                        var p1 = t.indexOf("<br><br>")
                        var p2 = p1 < 0 ? -1 : t.indexOf("<br><br>", p1 + 8)
                        if (p2 < 0)
                            return [t, ""]
                        // The disclaimer is broken into short lines by hand for the wide
                        // classic page: here it wraps by itself
                        var rest = t.substring(p2 + 8).replace(/<i>([\s\S]*?)<\/i>/, function (m, x) {
                            return "<i>" + x.replace(/<br\s*\/?\s*>/g, " ") + "</i>"
                        })
                        return [t.substring(0, p2), rest]
                    }

                    Column {
                        id: helpColumn
                        x: 16
                        y: 16
                        width: parent.width - 32
                        spacing: 8

                        Row {
                            spacing: 10
                            UiIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20
                                height: 20
                                name: "help"
                                color: window.ui.textMuted
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("Not connecting?")
                                color: window.ui.textMain
                                font.pixelSize: window.ui.fontLabel
                                font.weight: Font.Medium
                            }
                        }

                        Label {
                            width: parent.width
                            text: helpColumn.parent.helpParts[0]
                            textFormat: Text.StyledText
                            wrapMode: Text.WordWrap
                            color: window.ui.textMuted
                            font.pixelSize: window.ui.fontCaption
                            lineHeight: 1.1
                        }

                        Label {
                            visible: text !== ""
                            width: parent.width
                            topPadding: 4
                            text: helpColumn.parent.helpParts[1]
                            textFormat: Text.StyledText
                            wrapMode: Text.WordWrap
                            color: window.ui.textMuted
                            opacity: 0.75
                            font.pixelSize: window.ui.modern ? window.ui.fontCaption : 11
                            lineHeight: 1.1
                        }
                    }
                }
            }
        }
    }
}

/*##^##
Designer {
    D{i:0;autoSize:true;formeditorZoom:0.6600000262260437;height:480;width:640}
}
##^##*/

