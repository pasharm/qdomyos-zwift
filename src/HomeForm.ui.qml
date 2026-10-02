import QtQuick 2.12
import QtQuick.Controls 2.5
import QtQuick.Controls.Material 2.12
import QtGraphicalEffects 1.12
import Qt.labs.settings 1.0

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

    Settings {
	     id: settings
		  property real ui_zoom: 100.0
		  property bool theme_tile_icon_enabled: true
		  property string theme_background_color: "#303030"
		}

    Item {
        width: parent.width
        height: rootItem.topBarHeight
        id: topBar
        visible: !window.lockTiles

        // Modern controls. They forward to the classic buttons below, which Home.qml listens to
        Row {
            id: modernRow
            visible: window.ui.modern
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: row.verticalCenter
            spacing: 8

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
                    Accessible.role: Accessible.Indicator
                    Accessible.name: qsTr("Bluetooth connection")
                    Accessible.description: rootItem.device ? qsTr("Device connected") : qsTr("Device not connected")
                    // No device yet: a tap searches right away instead of waiting for the next search
                    // (with a device connected bluetoothSearchNow() does nothing)
                    MouseArea {
                        anchors.fill: parent
                        onClicked: rootItem.bluetoothSearchNow()
                    }
                }
            }

            AbstractButton {
                id: modernStart
                width: 120
                height: 56
                onClicked: start.clicked()
                background: Rectangle {
                    radius: height / 2
                    color: rootItem.startColor === "red" ? window.ui.danger : window.ui.accent
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
                            text: rootItem.startText
                            color: window.ui.accentInk
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            visible: text !== ""
                        }
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: rootItem.startText
                Accessible.description: qsTr("Start workout")
                Accessible.focusable: true
                Accessible.onPressAction: start.clicked()
            }

            AbstractButton {
                id: modernStop
                width: 120
                height: 56
                onClicked: stop.clicked()
                background: UiFrame {
                    radius: height / 2
                    fill: modernStop.down ? window.ui.surfaceHighest : window.ui.surfaceHigh
                    stroke: window.ui.alpha(window.ui.danger, 0.45)
                    strokeWidth: 1
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
                            color: window.ui.danger
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: rootItem.stopText
                            color: window.ui.textMain
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            visible: text !== ""
                        }
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: rootItem.stopText
                Accessible.description: qsTr("Stop workout")
                Accessible.focusable: true
                Accessible.onPressAction: stop.clicked()
            }

            AbstractButton {
                id: modernLap
                width: 48
                height: 56
                enabled: rootItem.lap
                opacity: enabled ? 1 : 0.4
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
                Accessible.onPressAction: lap.clicked()
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

                            // VoiceOver accessibility
                            Accessible.role: Accessible.Indicator
                            Accessible.name: qsTr("Bluetooth connection")
                            Accessible.description: rootItem.device ? qsTr("Device connected") : qsTr("Device not connected")
                            Accessible.focusable: true
                        }
                        ColorOverlay {
                            anchors.fill: treadmill_connection
                            source: treadmill_connection
                            color: treadmill_connection.enabled ? "#00000000" : "#B0D3d3d3"
                        }
                        // No device yet: a tap searches right away instead of waiting for the next search
                        // (with a device connected bluetoothSearchNow() does nothing)
                        MouseArea {
                            anchors.fill: parent
                            onClicked: rootItem.bluetoothSearchNow()
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
                    enabled: true
                    id: start
                    width: 120
                    height: row.height - 4

                    // VoiceOver accessibility
                    Accessible.role: Accessible.Button
                    Accessible.name: rootItem.startText
                    Accessible.description: qsTr("Start workout")
                    Accessible.focusable: true
                }
                ColorOverlay {
                    anchors.fill: start
                    source: start
                    color: rootItem.startColor
                    enabled: rootItem.startColor === "red" ? true : false
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
                }
            }
        }

        Row {
            id: row1
            width: parent.width
            anchors.bottom: row.bottom
            anchors.bottomMargin: -10

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                text: page.searchStatus !== "" ? page.searchStatus : rootItem.info
                visible: !window.ui.modern && !page.deviceLineHidden
                color: Material.foreground
                font.pixelSize: Qt.application.font.pixelSize
            }
        }

        // Modern status line: signal bars and the device status on one line
        Row {
            id: modernInfo
            // Over the empty state only the time to the next search ("Next search in 12 s"): its
            // heading says the rest ("Looking for your equipment"). The line has its own place
            // under the buttons, so it comes and goes without moving the page
            readonly property bool countdown: !page.searchStopped && page.searchStatus !== ""
                                              && page.searchStatus !== qsTranslate("homeform", "Searching for the device...")
            visible: window.ui.modern && !page.deviceLineHidden && page.modernInfoShown && (!modernEmpty.visible || countdown)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: row1.bottom
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
                    color: window.ui.dark ? "#000000" : "#FFFFFF"
                    font.pixelSize: 12
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
                color: modernInfo.bluetoothOff ? window.ui.danger : window.ui.textMuted
                font.pixelSize: 13
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
            visible: rootItem.labelHelp && !window.ui.modern
        }

        // Modern look: while nothing is connected, a short "searching" state instead of the
        // wall of text, and a short checklist cut from the same help text (already translated)
        Flickable {
            id: modernEmpty
            visible: rootItem.labelHelp && window.ui.modern
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
                    text: page.searchStopped ? qsTranslate("HomeForm.ui", "Equipment not found") : qsTranslate("HomeForm.ui", "Looking for your equipment…")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: window.ui.textMain
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }

                Label {
                    width: parent.width
                    text: page.searchStopped ? qsTranslate("HomeForm.ui", "Turn on your bike, treadmill or rower, then tap the Bluetooth icon at the top to search again.")
                                             : qsTranslate("HomeForm.ui", "Turn on your bike, treadmill or rower: QZ connects to it automatically.")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: window.ui.textMuted
                    font.pixelSize: 15
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
                    radius: 16
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
                                font.pixelSize: 15
                                font.weight: Font.Medium
                            }
                        }

                        Label {
                            width: parent.width
                            text: helpColumn.parent.helpParts[0]
                            textFormat: Text.StyledText
                            wrapMode: Text.WordWrap
                            color: window.ui.textMuted
                            font.pixelSize: 13
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
                            font.pixelSize: 11
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

