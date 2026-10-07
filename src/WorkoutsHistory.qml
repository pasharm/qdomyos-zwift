import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtCharts 2.15
import Qt.labs.calendar 1.0
import Qt.labs.settings 1.0
import Qt.labs.platform 1.1 as P
import QtQuick.Dialogs 1.0 as Dialogs

Page {
    id: workoutHistoryPage

    // Modern look: theme colours and icons instead of the fixed light palette and emoji of
    // this page; the classic look keeps them
    readonly property bool modern: window.ui.modern

    function sportIconName(sport) {
        switch(parseInt(sport)) {
            case 1: return "directions_run"
            case 11: return "directions_walk"
            case 2: return "pedal_bike"
            case 15: return "rowing"
            default: return "fitness_center"
        }
    }


    Settings {
        id: settings
        property bool miles_unit: false
    }

    // Signal for chart preview
    signal fitfile_preview_clicked(var url)

    // a pending offer to recover the workouts of a previous install is made here
    Component.onCompleted: rootItem.historyPageOpened()

    // Helper function to wrap text with emoji font only on Android
    function wrapEmoji(emoji) {
        return Qt.platform.os === "android" ? 
            '<font face="' + fontManager.emojiFontFamily + '">' + emoji + '</font>' : 
            emoji;
    }

    // Sport type to icon mapping (using FIT_SPORT values)
    function getSportIcon(sport) {
        switch(parseInt(sport)) {
            case 1:  // FIT_SPORT_RUNNING
            case 11: // FIT_SPORT_WALKING
                return "🏃"; // Running/Walking
            case 2:  // FIT_SPORT_CYCLING
                return "🚴"; // Cycling
            case 4:  // FIT_SPORT_FITNESS_EQUIPMENT (Elliptical)
                return "⭕"; // Elliptical
            case 15: // FIT_SPORT_ROWING
                return "🚣"; // Rowing
            case 84: // FIT_SPORT_JUMPROPE
                return "🪢"; // Jump Rope
            default: 
                return "💪"; // Generic workout
        }
    }

    function hasAnyUploadServiceConfigured(workoutId) {
        return (rootItem &&
                (rootItem.isStravaLoggedIn() ||
                 rootItem.isGarminUploadConfigured() ||
                 rootItem.isIntervalsICUUploadConfigured())) ||
               (Qt.platform.os === "ios" &&
                workoutModel &&
                workoutModel.canWriteAppleHealth(workoutId))
    }

    function openUploadMenu(delegateItem, workoutId, workoutTitle) {
        if (!workoutModel || !hasAnyUploadServiceConfigured(workoutId)) {
            return
        }

        var details = workoutModel.getWorkoutDetails(workoutId)
        if (!details.filePath || details.filePath === "") {
            return
        }

        uploadMenu.workoutId = workoutId
        uploadMenu.workoutTitle = workoutTitle
        uploadMenu.filePath = details.filePath

        var popupPoint = delegateItem.mapToItem(workoutHistoryPage, delegateItem.width / 2, delegateItem.height / 2)
        uploadMenu.x = Math.max(8, popupPoint.x - 40)
        uploadMenu.y = Math.max(8, popupPoint.y - 20)
        uploadMenu.open()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // Modern header: the title on the left, the streak (or the date filter) under it as a
        // small chip, the calendar and import on the right. The streak used to be a big orange
        // banner at the bottom, the loudest thing on the page even at zero days. The filter
        // chip clears the filter itself: a "Clear Filter" button beside the round ones cut the
        // title down to a few letters on a phone
        Item {
            id: modernHeader
            visible: workoutHistoryPage.modern
            Layout.fillWidth: true
            Layout.leftMargin: Math.max(16, window.contentSideMargin)
            Layout.rightMargin: Math.max(16, window.contentSideMargin)
            implicitHeight: Math.max(modernHeaderButtons.implicitHeight, modernTitleColumn.implicitHeight)

            readonly property int streak: workoutModel ? workoutModel.currentStreak : 0
            readonly property bool filtered: workoutModel ? workoutModel.isDateFiltered : false

            Column {
                id: modernTitleColumn
                anchors.left: parent.left
                anchors.right: modernHeaderButtons.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    width: parent.width
                    text: qsTr("Workout History")
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    color: window.ui.textMain
                    elide: Text.ElideRight
                }

                AbstractButton {
                    id: filterChip
                    visible: modernHeader.filtered
                    // From the text's implicit width, not the row's: the row's width follows the
                    // elided text, and measuring by it would loop
                    width: Math.min(implicitWidth, parent.width)
                    implicitWidth: 24 + 2 * 18 + 2 * filterChipRow.spacing + filterChipText.implicitWidth
                    height: 32
                    onClicked: workoutModel.clearDateFilter()
                    background: Rectangle {
                        radius: 16
                        color: window.ui.alpha(window.ui.accent, filterChip.down ? 0.28 : 0.16)
                    }
                    contentItem: Item {
                        Row {
                            id: filterChipRow
                            anchors.verticalCenter: parent.verticalCenter
                            x: 12
                            spacing: 6
                            UiIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                height: 18
                                name: "calendar_month"
                                color: window.ui.accent
                            }
                            Text {
                                id: filterChipText
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, Math.min(implicitWidth, filterChip.width - (filterChip.implicitWidth - implicitWidth)))
                                // "пн, 5 жовт.", the year only when it is not this one: the month
                                // as a word reads the same in every language, 5.10 does not
                                text: {
                                    if (!modernHeader.filtered)
                                        return ""
                                    // Qt 5 hands a QDate over as midnight UTC: read west of
                                    // Greenwich, that is the day before
                                    var d0 = workoutModel.filteredDate
                                    var d = d0.getUTCHours() === 0 && d0.getUTCMinutes() === 0
                                            ? new Date(d0.getUTCFullYear(), d0.getUTCMonth(), d0.getUTCDate())
                                            : d0
                                    var f = d.getFullYear() === new Date().getFullYear() ? "ddd, d MMM" : "ddd, d MMM yyyy"
                                    return d.toLocaleDateString(Qt.locale(), f)
                                }
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                color: window.ui.accent
                                elide: Text.ElideRight
                            }
                            UiIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                height: 18
                                name: "close"
                                color: window.ui.accent
                            }
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Clear Filter")
                }

                Rectangle {
                    visible: !modernHeader.filtered && modernHeader.streak > 0
                    // The height of the filter chip in the same place: switching between them
                    // keeps the header still
                    width: streakChipRow.implicitWidth + 24
                    height: 32
                    radius: 16
                    color: window.ui.alpha(window.ui.accent, 0.16)

                    Row {
                        id: streakChipRow
                        anchors.centerIn: parent
                        spacing: 4
                        UiIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18
                            height: 18
                            name: "local_fire_department"
                            color: window.ui.accent
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: (modernHeader.streak !== 1 ? qsTr("%1 days streak") : qsTr("%1 day streak")).arg(modernHeader.streak)
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: window.ui.accent
                        }
                    }
                }
            }

            Row {
                id: modernHeaderButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                // Icon buttons as elsewhere in the modern look (the parent folder button of the
                // GPX and workout lists): UiButton 48 wide, its pill 36 high inside 48 to touch
                spacing: 4

                UiButton {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 48
                    leftPadding: 0
                    rightPadding: 0
                    onClicked: calendarPopup.open()
                    Accessible.name: qsTr("Calendar")
                    UiIcon {
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        name: "calendar_month"
                        color: window.ui.textMain
                    }
                }

                UiButton {
                    id: modernImportButton
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 48
                    leftPadding: 0
                    rightPadding: 0
                    onClicked: modernImportMenu.openUnder(modernImportButton)
                    Accessible.name: qsTr("Import FIT File...")
                    // The icon of loading settings from a file in the toolbar: both take a file
                    // from the phone
                    UiIcon {
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        name: "upload_file"
                        color: window.ui.textMain
                    }
                }
            }
        }

        // Header
        Rectangle {
            visible: !workoutHistoryPage.modern
            Layout.fillWidth: true
            height: 60
            color: workoutHistoryPage.modern ? "transparent" : "#f5f5f5"

            // Calendar Icon Button - positioned absolutely on the left
            Button {
                id: calendarButton
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: window.contentSideMargin
                width: 48
                height: 48
                
                background: Rectangle {
                    radius: workoutHistoryPage.modern ? 24 : 8
                    color: workoutHistoryPage.modern ? (calendarButton.pressed ? window.ui.surfaceHighest : window.ui.surfaceHigh)
                                 : (calendarButton.pressed ? "#e0e0e0" : "#f0f0f0")
                    border.color: "#d0d0d0"
                    border.width: workoutHistoryPage.modern ? 0 : 1
                }

                UiIcon {
                    anchors.centerIn: parent
                    visible: workoutHistoryPage.modern
                    width: 22
                    height: 22
                    name: "calendar_month"
                    color: window.ui.textMain
                }

                contentItem: Text {
                    visible: !workoutHistoryPage.modern
                    text: Qt.platform.os === "android" ?
                          wrapEmoji("📅") :
                          "📅"
                    textFormat: Qt.platform.os === "android" ? Text.RichText : Text.PlainText
                    font.pixelSize: 26
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: {
                    calendarPopup.open()
                }
            }

            // Title with filter status - between the buttons, shrinking on narrow screens
            Column {
                anchors.left: clearFilterButton.visible ? clearFilterButton.right : calendarButton.right
                anchors.right: importButton.left
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Workout History")
                    font.pixelSize: workoutHistoryPage.modern ? 22 : 24
                    font.weight: workoutHistoryPage.modern ? Font.DemiBold : Font.Bold
                    color: window.ui.ink("black")
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 14
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: workoutModel && workoutModel.isDateFiltered ?
                          qsTr("Filtered: %1").arg(workoutModel.filteredDate.toLocaleDateString()) : ""
                    font.pixelSize: 12
                    color: window.ui.inkMuted("#666666")
                    elide: Text.ElideRight
                    visible: workoutModel && workoutModel.isDateFiltered
                }
            }

            // Import Button - on the right: a single .fit file, or every workout of the QZ folder
            Button {
                id: importButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: window.contentSideMargin
                width: 48
                height: 48

                background: Rectangle {
                    radius: 8
                    color: importButton.pressed ? "#e0e0e0" : "#f0f0f0"
                    border.color: "#d0d0d0"
                    border.width: 1
                }

                contentItem: Item {
                    // Android draws emoji only with the downloaded emoji font; until it is
                    // there (or when the download failed) the icon is drawn as a shape
                    readonly property bool emojiFontMissing: Qt.platform.os === "android" &&
                        (!fontManager || fontManager.emojiFontFamily === "Arial")

                    Text {
                        anchors.fill: parent
                        visible: !parent.emojiFontMissing
                        text: Qt.platform.os === "android" ?
                              wrapEmoji("📥") :
                              "📥"
                        textFormat: Qt.platform.os === "android" ? Text.RichText : Text.PlainText
                        font.pixelSize: 26
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    // tray with a down arrow
                    Canvas {
                        anchors.centerIn: parent
                        width: 26
                        height: 26
                        visible: parent.emojiFontMissing
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.strokeStyle = "#444444"
                            ctx.lineWidth = 2.5
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            ctx.beginPath()
                            ctx.moveTo(13, 3)
                            ctx.lineTo(13, 16)
                            ctx.moveTo(8, 11)
                            ctx.lineTo(13, 16)
                            ctx.lineTo(18, 11)
                            ctx.moveTo(3, 15)
                            ctx.lineTo(3, 23)
                            ctx.lineTo(23, 23)
                            ctx.lineTo(23, 15)
                            ctx.stroke()
                        }
                    }
                }

                onClicked: importMenu.popup(importButton, 0, importButton.height)
            }

            // Clear Filter Button - left of the import button
            Button {
                id: clearFilterButton
                // next to the calendar that set the filter; small, so the title keeps its room
                anchors.left: calendarButton.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 6
                width: 32
                height: 32
                visible: workoutModel && workoutModel.isDateFiltered

                background: Rectangle {
                    radius: 16
                    color: workoutHistoryPage.modern ? window.ui.alpha(window.ui.danger, clearFilterButton.pressed ? 0.28 : 0.16)
                                 : (clearFilterButton.pressed ? "#ff6666" : "#ff8888")
                    border.color: "#ff4444"
                    border.width: workoutHistoryPage.modern ? 0 : 1
                }

                contentItem: Text {
                    text: "×"
                    Accessible.name: qsTr("Clear Filter")
                    color: workoutHistoryPage.modern ? window.ui.danger : "white"
                    font.pixelSize: 20
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: {
                    workoutModel.clearDateFilter()
                }
            }
        }

        // Loading indicator
        BusyIndicator {
            id: loadingIndicator
            Layout.alignment: Qt.AlignHCenter
            visible: (workoutModel ? (workoutModel.isLoading || workoutModel.isDatabaseProcessing) : false) ||
                     (rootItem && rootItem.fitImportRunning)
            running: visible
        }

        // Workout import message: copying the picked files can take a while
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: window.contentSideMargin
            Layout.rightMargin: window.contentSideMargin
            visible: rootItem ? rootItem.fitImportRunning : false
            text: qsTr("Importing workouts...")
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: "#666666"
            font.pixelSize: 16
        }

        // Database processing message
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: window.contentSideMargin
            Layout.rightMargin: window.contentSideMargin
            visible: workoutModel ? workoutModel.isDatabaseProcessing : false
            text: qsTr("Processing workout files...\nThis may take a few moments on first startup.")
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: window.ui.inkMuted("#666666")
            font.pixelSize: 16
        }

        // Workout List
        ListView {
            id: workoutListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.bottomMargin: streakBanner.visible ? streakBanner.height + 10 : 10
            model: workoutModel
            spacing: 8
            clip: true

            // Modern look: an empty list says so, instead of a blank page
            Column {
                // On the list itself: children of a ListView land in its content item
                parent: workoutListView
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 360)
                spacing: 10
                visible: workoutHistoryPage.modern && workoutListView.count === 0
                         && !(workoutModel && (workoutModel.isLoading || workoutModel.isDatabaseProcessing))

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 88
                    height: 88
                    radius: 44
                    color: window.ui.alpha(window.ui.accent, 0.14)
                    UiIcon {
                        anchors.centerIn: parent
                        width: 44
                        height: 44
                        name: "history"
                        color: window.ui.accent
                    }
                }
                Text {
                    width: parent.width
                    topPadding: 4
                    text: workoutModel && workoutModel.isDateFiltered ? qsTr("No workouts on this day")
                                                                      : qsTr("No workouts yet")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    color: window.ui.textMain
                }
                Text {
                    width: parent.width
                    visible: !(workoutModel && workoutModel.isDateFiltered)
                    text: qsTr("Finished workouts appear here: open one to see its charts.")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.pixelSize: 15
                    color: window.ui.textMuted
                }
            }

            onContentYChanged: {
                // Hide banner when scrolling down, show when at top (the modern look has
                // the streak as a chip in the header instead)
                streakBanner.visible = !workoutHistoryPage.modern && contentY <= 20
            }

            delegate: SwipeDelegate {
                id: swipeDelegate
                width: parent.width
                height: 135

                Component.onCompleted: {
                    console.log("Delegate data:", JSON.stringify({
                        sport: sport,
                        title: title,
                        date: date,
                        duration: duration,
                        distance: distance,
                        calories: calories,
                        id: id
                    }))
                }

                swipe.right: Rectangle {
                    width: parent.width
                    height: parent.height
                    color: "#FF4444"
                    clip: true

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 20

                        Text {
                            text: Qt.platform.os === "android" ? 
                                  wrapEmoji("🗑️") + " " + qsTr("Delete") : 
                                  "🗑️ " + qsTr("Delete")
                            textFormat: Qt.platform.os === "android" ? Text.RichText : Text.PlainText
                            color: "white"
                            font.pixelSize: 16
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                swipe.onCompleted: {
                    if (workoutHistoryPage.modern) {
                        modernDeleteDialog.workoutId = model.id
                        modernDeleteDialog.workoutTitle = model.title
                        modernDeleteDialog.swipeItem = swipeDelegate
                        modernDeleteDialog.open()
                        return
                    }
                    // Show confirmation dialog
                    confirmDialog.workoutId = model.id
                    confirmDialog.workoutTitle = model.title
                    confirmDialog.open()
                }

                // Card-like container
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 8
                    anchors.leftMargin: window.contentSideMargin
                    anchors.rightMargin: window.contentSideMargin
                    radius: workoutHistoryPage.modern ? 16 : 10
                    color: workoutHistoryPage.modern ? window.ui.surface : "white"
                    border.color: workoutHistoryPage.modern ? "transparent" : "#e0e0e0"

                    // Workout Type Tag - positioned absolutely in top-right
                    WorkoutTypeTag {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        workoutSource: workoutModel ? workoutModel.getWorkoutSource(model.id) : "QZ"
                    }

                    // Action buttons - positioned absolutely in bottom-right
                    Row {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 12
                        spacing: 8
                        
                        // Peloton URL button
                        Button {
                            width: 40
                            height: 45
                            visible: workoutModel && workoutModel.getWorkoutSource(model.id) === "PELOTON" && 
                                    workoutModel.getPelotonUrl(model.id) !== ""
                            
                            background: Rectangle {
                                color: workoutHistoryPage.modern ? (parent.pressed ? window.ui.surfaceHigh : window.ui.surfaceHighest)
                                             : (parent.pressed ? "#ff8855" : "#ff6b35")
                                radius: workoutHistoryPage.modern ? 20 : 6
                                border.color: "#cc5529"
                                border.width: workoutHistoryPage.modern ? 0 : 1
                            }
                            
                            contentItem: Text {
                                text: Qt.platform.os === "android" ? 
                                      wrapEmoji("🌐") : 
                                      "🌐"
                                textFormat: Qt.platform.os === "android" ? Text.RichText : Text.PlainText
                                font.pixelSize: 16
                                color: "white"
                                anchors.centerIn: parent
                            }
                            
                            onClicked: {
                                workoutModel.openPelotonUrl(model.id)
                            }
                        }
                        
                        // Training Program button
                        Button {
                            width: 40
                            height: 45
                            visible: workoutModel && workoutModel.hasTrainingProgram(model.id)
                            
                            background: Rectangle {
                                color: workoutHistoryPage.modern ? (parent.pressed ? window.ui.surfaceHigh : window.ui.surfaceHighest)
                                             : (parent.pressed ? "#1976d2" : "#2196f3")
                                radius: workoutHistoryPage.modern ? 20 : 6
                                border.color: "#1565c0"
                                border.width: workoutHistoryPage.modern ? 0 : 1
                            }
                            
                            contentItem: Text {
                                text: Qt.platform.os === "android" ? 
                                      wrapEmoji("📋") : 
                                      "📋"
                                textFormat: Qt.platform.os === "android" ? Text.RichText : Text.PlainText
                                font.pixelSize: 16
                                color: "white"
                                anchors.centerIn: parent
                            }
                            
                            onClicked: {
                                var success = workoutModel.loadTrainingProgram(model.id)
                                if (success) {
                                    trainingProgramDialog.title = qsTr("Success")
                                    trainingProgramDialog.message = qsTr("Training program loaded successfully!")
                                    trainingProgramDialog.isSuccess = true
                                } else {
                                    trainingProgramDialog.title = qsTr("Error")
                                    trainingProgramDialog.message = qsTr("Failed to load training program. Please check if the file exists.")
                                    trainingProgramDialog.isSuccess = false
                                }
                                if (workoutHistoryPage.modern)
                                    modernInfoDialog.open()
                                else
                                    trainingProgramDialog.open()
                            }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 16

                        // Sport icon
                        Column {
                            Layout.alignment: Qt.AlignVCenter
                            Rectangle {
                                visible: workoutHistoryPage.modern
                                width: 44
                                height: 44
                                radius: 22
                                color: window.ui.surfaceHighest
                                UiIcon {
                                    anchors.centerIn: parent
                                    width: 24
                                    height: 24
                                    name: workoutHistoryPage.sportIconName(sport)
                                    color: window.ui.accent
                                }
                            }
                            Text {
                                visible: !workoutHistoryPage.modern
                                text: Qt.platform.os === "android" ?
                                      wrapEmoji(getSportIcon(sport)) :
                                      getSportIcon(sport)
                                textFormat: Qt.platform.os === "android" ? Text.RichText : Text.PlainText
                                font.pixelSize: 32
                            }
                        }

                        // Workout info
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            // Title row (without tag) with auto-scrolling
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.rightMargin: 80 // Reserve space for tag
                                Layout.preferredHeight: 24
                                clip: true
                                color: "transparent"
                                
                                Text {
                                    id: titleText
                                    text: title
                                    font.bold: true
                                    font.pixelSize: 18
                                    color: window.ui.ink("black")
                                    anchors.verticalCenter: parent.verticalCenter
                                    
                                    // Auto-scroll animation for long titles.
                                    // The row width settles only after the layout runs (the first
                                    // delegate passes through narrower widths), and an animation started
                                    // on one of them kept running: decide after the layout, again on every
                                    // width change, and put the title back when it stops mid-scroll.
                                    readonly property bool overflows: parent.width > 0 && contentWidth > parent.width
                                    function updateScroll() {
                                        if (overflows) {
                                            titleScroll.restart()
                                        } else {
                                            titleScroll.stop()
                                            x = 0
                                        }
                                    }
                                    onOverflowsChanged: Qt.callLater(updateScroll)
                                    onContentWidthChanged: if (overflows) Qt.callLater(updateScroll)
                                    Connections {
                                        target: titleText.parent
                                        function onWidthChanged() { if (titleText.overflows) Qt.callLater(titleText.updateScroll) }
                                    }

                                    SequentialAnimation {
                                        id: titleScroll
                                        loops: Animation.Infinite
                                        NumberAnimation {
                                            target: titleText
                                            property: "x"
                                            from: 0
                                            to: -(titleText.contentWidth - titleText.parent.width + 20)
                                            duration: Math.max(3000, titleText.contentWidth * 30)
                                        }
                                        PauseAnimation { duration: 1500 }
                                        NumberAnimation {
                                            target: titleText
                                            property: "x"
                                            from: -(titleText.contentWidth - titleText.parent.width + 20)
                                            to: 0
                                            duration: Math.max(3000, titleText.contentWidth * 30)
                                        }
                                        PauseAnimation { duration: 2000 }
                                    }
                                }
                            }

                            Text {
                                text: date
                                color: window.ui.inkMuted("#666666")
                            }

                            // Stats row
                            RowLayout {
                                spacing: 16

                                Text {
                                    text: (workoutHistoryPage.modern ? "" : "⏱ ") + duration
                                    color: window.ui.ink("black")
                                }

                                Text {
                                    text: {
                                        var useMiles = settings && settings.miles_unit
                                        var displayDistance = useMiles ? (distance / 1.60934) : distance
                                        return (workoutHistoryPage.modern ? "" : "📏 ") + displayDistance.toFixed(2) + " " + (useMiles ? qsTr("mi") : qsTr("km"))
                                    }
                                    color: window.ui.ink("black")
                                }
                            }

                            RowLayout {
                                spacing: 16

                                Text {
                                    text: workoutHistoryPage.modern ? Math.round(calories) + " " + qsTr("kcal") :
                                          Qt.platform.os === "android" ?
                                          wrapEmoji("🔥") + " " + Math.round(calories) + " " + qsTr("kcal") :
                                          "🔥 " + Math.round(calories) + " " + qsTr("kcal")
                                    textFormat: Qt.platform.os === "android" && !workoutHistoryPage.modern ? Text.RichText : Text.PlainText
                                    color: window.ui.inkMuted("black")
                                }
                            }
                        }
                        
                    }
                }

                onClicked: {
                    console.log("Workout clicked, ID:", model.id)
                    
                    // Get workout details from the model
                    var details = workoutModel.getWorkoutDetails(model.id)
                    console.log("Workout details:", JSON.stringify(details))

                    // Emit signal with file URL for chart preview - same pattern as profiles.qml
                    console.log("Emitting fitfile_preview_clicked with path:", details.filePath)
                    // Convert to URL like profiles.qml does with FolderListModel
                    var fileUrl = "file://" + details.filePath
                    console.log("Converted to URL:", fileUrl)
                    workoutHistoryPage.fitfile_preview_clicked(fileUrl)

                    // Push the ChartJsTest view
                    stackView.push("PreviewChart.qml")
                }

                onPressAndHold: {
                    workoutHistoryPage.openUploadMenu(swipeDelegate, model.id, model.title)
                }
            }
        }
    }

    Menu {
        id: importMenu

        MenuItem {
            text: qsTr("Import FIT File...")
            onTriggered: {
                if (Qt.platform.os === "android") {
                    rootItem.openAndroidDocumentPicker("fit")
                } else {
                    fitFileDialogLoader.active = true
                }
            }
        }

        MenuItem {
            // after a reinstall the workouts of the previous install stay in this folder,
            // but Android hides them from the app until the folder is picked once
            text: qsTr("Import from QZ Folder...")
            onTriggered: rootItem.importFitFolder()
        }
    }

    // Modern look: the same two items on a UiPopup card under the button, the pressed item
    // a rounded block inset from the edges (as the UiComboBox list)
    UiPopup {
        id: modernImportMenu
        padding: 8
        modal: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        function openUnder(item) {
            var p = item.mapToItem(workoutHistoryPage, 0, item.height)
            x = Math.max(8, Math.min(p.x + item.width - width, workoutHistoryPage.width - width - 8))
            y = p.y + 4
            open()
        }

        contentItem: Column {
            width: 240
            Repeater {
                model: [
                    { label: qsTr("Import FIT File..."), folder: false },
                    { label: qsTr("Import from QZ Folder..."), folder: true }
                ]
                delegate: AbstractButton {
                    id: modernImportItem
                    width: 240
                    height: 48
                    background: Rectangle {
                        radius: 10
                        color: modernImportItem.down ? window.ui.surfaceHighest : "transparent"
                    }
                    contentItem: Text {
                        leftPadding: 12
                        rightPadding: 12
                        text: modelData.label
                        font.pixelSize: 16
                        color: window.ui.textMain
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    onClicked: {
                        modernImportMenu.close()
                        if (modelData.folder)
                            rootItem.importFitFolder()
                        else if (Qt.platform.os === "android")
                            rootItem.openAndroidDocumentPicker("fit")
                        else
                            fitFileDialogLoader.active = true
                    }
                }
            }
        }
    }

    Loader {
        id: fitFileDialogLoader
        active: false
        sourceComponent: Component {
            Dialogs.FileDialog {
                title: qsTr("Please choose a file")
                folder: shortcuts.home
                nameFilters: [qsTr("FIT files (*.fit *.FIT)"), qsTr("All files (*)")]
                visible: true
                onAccepted: {
                    rootItem.importFitFile(fileUrl)
                    fitFileDialogLoader.active = false
                }
                onRejected: fitFileDialogLoader.active = false
            }
        }
    }

    Menu {
        id: uploadMenu

        property int workoutId: -1
        property string workoutTitle: ""
        property string filePath: ""

        title: workoutTitle

        MenuItem {
            text: qsTr("Upload to Strava")
            visible: rootItem && rootItem.isStravaLoggedIn()
            onTriggered: rootItem.uploadHistoricalWorkoutToStrava(uploadMenu.filePath)
        }

        MenuItem {
            text: qsTr("Upload to Garmin")
            visible: rootItem && rootItem.isGarminUploadConfigured()
            onTriggered: rootItem.uploadHistoricalWorkoutToGarmin(uploadMenu.filePath)
        }

        MenuItem {
            text: qsTr("Upload to Intervals.icu")
            visible: rootItem && rootItem.isIntervalsICUUploadConfigured()
            onTriggered: rootItem.uploadHistoricalWorkoutToIntervalsICU(uploadMenu.filePath)
        }

        MenuItem {
            text: qsTr("Upload to Apple Health")
            visible: Qt.platform.os === "ios" &&
                     workoutModel &&
                     workoutModel.canWriteAppleHealth(uploadMenu.workoutId)
            onTriggered: workoutModel.uploadWorkoutToAppleHealth(uploadMenu.workoutId)
        }
    }

    // Confirmation Dialog
    Dialog {
        id: confirmDialog

        property int workoutId
        property string workoutTitle

        title: qsTr("Delete Workout")
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel

        x: (parent.width - width) / 2
        y: (parent.height - height) / 2

        Text {
            text: qsTr("Are you sure you want to delete '%1'?").arg(confirmDialog.workoutTitle)
        }

        onAccepted: {
            workoutModel.deleteWorkout(confirmDialog.workoutId)
            swipeDelegate.swipe.close()
        }
        onRejected: {
            swipeDelegate.swipe.close()
        }
    }

    // Modern look: the same questions in the card dialog of the other screens
    UiMessageDialog {
        id: modernDeleteDialog
        property int workoutId
        property string workoutTitle
        property var swipeItem: null
        title: qsTr("Delete Workout")
        text: qsTr("Are you sure you want to delete '%1'?").arg(workoutTitle)
        // the positive button named after the action and in the danger colour, as in the
        // other questions that cannot be undone (Stop on Home, Reset in the settings)
        buttons: P.MessageDialog.Yes | P.MessageDialog.Cancel
        yesText: qsTr("Delete")
        destructive: true
        onAccepted: workoutModel.deleteWorkout(workoutId)
        // any way out (Cancel, the back key, a deleted row) closes the swiped row again
        onClosed: {
            if (swipeItem)
                swipeItem.swipe.close()
            swipeItem = null
        }
    }

    UiMessageDialog {
        id: modernInfoDialog
        title: trainingProgramDialog.title
        text: trainingProgramDialog.message
        buttons: P.MessageDialog.Ok
    }

    // Training Program Loading Dialog
    Dialog {
        id: trainingProgramDialog

        property string message: ""
        property bool isSuccess: true

        modal: true
        standardButtons: Dialog.Ok

        x: (parent.width - width) / 2
        y: (parent.height - height) / 2

        background: Rectangle {
            color: "white"
            radius: 8
            border.color: trainingProgramDialog.isSuccess ? "#4caf50" : "#f44336"
            border.width: 2
        }

        header: Rectangle {
            height: 50
            color: trainingProgramDialog.isSuccess ? "#4caf50" : "#f44336"
            radius: 8

            Text {
                anchors.centerIn: parent
                text: trainingProgramDialog.title
                color: "white"
                font.pixelSize: 18
                font.bold: true
            }
        }

        contentItem: ColumnLayout {
            spacing: 16

            Text {
                Layout.margins: 20
                Layout.preferredWidth: 300
                Layout.preferredHeight: 120
                text: Qt.platform.os === "android" ? 
                      wrapEmoji("🔥") + " " + 
                      wrapEmoji(trainingProgramDialog.isSuccess ? '✅' : '❌') + 
                      " " + trainingProgramDialog.message : 
                      "🔥 " + (trainingProgramDialog.isSuccess ? '✅ ' : '❌ ') + trainingProgramDialog.message
                textFormat: Qt.platform.os === "android" ? Text.RichText : Text.PlainText
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 14
            }
        }
    }

    // Streak Banner at the bottom
    Rectangle {
        id: streakBanner
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        // Modern look: a rounded card like the rest of the page instead of a full-width strip
        anchors.leftMargin: workoutHistoryPage.modern ? Math.max(16, window.contentSideMargin) : 0
        anchors.rightMargin: workoutHistoryPage.modern ? Math.max(16, window.contentSideMargin) : 0
        anchors.bottomMargin: workoutHistoryPage.modern ? 8 : 0
        radius: workoutHistoryPage.modern ? 20 : 0
        height: 80
        visible: workoutModel && !workoutHistoryPage.modern
        
        Behavior on visible {
            NumberAnimation {
                properties: "opacity"
                duration: 300
                easing.type: Easing.InOutQuad
            }
        }
        
        // Special pulsing effect for major milestones
        SequentialAnimation on opacity {
            running: workoutModel && workoutModel.currentStreak >= 30
            loops: Animation.Infinite
            NumberAnimation { from: 0.9; to: 1.0; duration: 1500; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.0; to: 0.9; duration: 1500; easing.type: Easing.InOutSine }
        }
        
        gradient: Gradient {
            GradientStop { 
                position: 0.0; 
                color: workoutModel && (workoutModel.currentStreak >= 365) ? "#FFD700" : 
                       workoutModel && (workoutModel.currentStreak >= 180) ? "#9932CC" : 
                       workoutModel && (workoutModel.currentStreak >= 90) ? "#FF1493" : 
                       workoutModel && (workoutModel.currentStreak >= 30) ? "#FF4500" : 
                       workoutModel && (workoutModel.currentStreak >= 7) ? "#FF6347" : "#FF6B35"
            }
            GradientStop { 
                position: 1.0; 
                color: workoutModel && (workoutModel.currentStreak >= 365) ? "#FFA500" : 
                       workoutModel && (workoutModel.currentStreak >= 180) ? "#8A2BE2" : 
                       workoutModel && (workoutModel.currentStreak >= 90) ? "#DC143C" : 
                       workoutModel && (workoutModel.currentStreak >= 30) ? "#FF6B35" : 
                       workoutModel && (workoutModel.currentStreak >= 7) ? "#FF4500" : "#F7931E"
            }
        }
        
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#40FFFFFF" }
                GradientStop { position: 1.0; color: "#00FFFFFF" }
            }
        }
        
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4

            // Current streak with count
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 15

                // Fire emoji with animation
                Text {
                    text: Qt.platform.os === "android" ? (
                          workoutModel && workoutModel.currentStreak >= 365 ? wrapEmoji("👑🔥") :
                          workoutModel && workoutModel.currentStreak >= 180 ? wrapEmoji("🎖️🔥") :
                          workoutModel && workoutModel.currentStreak >= 90 ? wrapEmoji("🦁🔥") :
                          workoutModel && workoutModel.currentStreak >= 30 ? wrapEmoji("🎊🔥") :
                          workoutModel && workoutModel.currentStreak >= 7 ? wrapEmoji("🏆🔥") : wrapEmoji("🔥")
                          ) : (
                          workoutModel && workoutModel.currentStreak >= 365 ? "👑🔥" :
                          workoutModel && workoutModel.currentStreak >= 180 ? "🎖️🔥" :
                          workoutModel && workoutModel.currentStreak >= 90 ? "🦁🔥" :
                          workoutModel && workoutModel.currentStreak >= 30 ? "🎊🔥" :
                          workoutModel && workoutModel.currentStreak >= 7 ? "🏆🔥" : "🔥"
                          )
                    textFormat: Qt.platform.os === "android" ? Text.RichText : Text.PlainText
                    font.pixelSize: workoutModel && workoutModel.currentStreak >= 7 ? 28 : 24

                    SequentialAnimation on scale {
                        running: workoutModel && workoutModel.currentStreak > 0
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 1.0;
                            to: workoutModel && workoutModel.currentStreak >= 7 ? 1.4 : 1.2;
                            duration: workoutModel && workoutModel.currentStreak >= 365 ? 600 : 800;
                            easing.type: Easing.InOutSine
                        }
                        NumberAnimation {
                            from: workoutModel && workoutModel.currentStreak >= 7 ? 1.4 : 1.2;
                            to: 1.0;
                            duration: workoutModel && workoutModel.currentStreak >= 7 ? 600 : 800;
                            easing.type: Easing.InOutSine
                        }
                    }

                    // Special sparkle effect for year achievement
                    SequentialAnimation on rotation {
                        running: workoutModel && workoutModel.currentStreak >= 7
                        loops: Animation.Infinite
                        NumberAnimation { from: 0; to: 360; duration: 3000; easing.type: Easing.Linear }
                    }
                }

                // Current streak count
                Text {
                    text: workoutModel ? (workoutModel.currentStreak !== 1 ? qsTr("%1 days streak") : qsTr("%1 day streak")).arg(workoutModel.currentStreak) : ""
                    font.pixelSize: 18
                    font.bold: true
                    color: "white"
                    visible: workoutModel
                }

                // Another fire emoji
                Text {
                    text: Qt.platform.os === "android" ? (
                          workoutModel && workoutModel.currentStreak >= 365 ? wrapEmoji("🔥👑") :
                          workoutModel && workoutModel.currentStreak >= 180 ? wrapEmoji("🔥🎖️") :
                          workoutModel && workoutModel.currentStreak >= 90 ? wrapEmoji("🔥🦁") :
                          workoutModel && workoutModel.currentStreak >= 30 ? wrapEmoji("🔥🎊") :
                          workoutModel && workoutModel.currentStreak >= 7 ? wrapEmoji("🔥🏆") : wrapEmoji("🔥")
                          ) : (
                          workoutModel && workoutModel.currentStreak >= 365 ? "🔥👑" :
                          workoutModel && workoutModel.currentStreak >= 180 ? "🔥🎖️" :
                          workoutModel && workoutModel.currentStreak >= 90 ? "🔥🦁" :
                          workoutModel && workoutModel.currentStreak >= 30 ? "🔥🎊" :
                          workoutModel && workoutModel.currentStreak >= 7 ? "🔥🏆" : "🔥"
                          )
                    textFormat: Qt.platform.os === "android" ? Text.RichText : Text.PlainText
                    font.pixelSize: workoutModel && workoutModel.currentStreak >= 365 ? 28 : 24

                    SequentialAnimation on scale {
                        running: workoutModel && workoutModel.currentStreak > 0
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 1.0;
                            to: workoutModel && workoutModel.currentStreak >= 7 ? 1.4 : 1.2;
                            duration: workoutModel && workoutModel.currentStreak >= 7 ? 700 : 1000;
                            easing.type: Easing.InOutSine
                        }
                        NumberAnimation {
                            from: workoutModel && workoutModel.currentStreak >= 7 ? 1.4 : 1.2;
                            to: 1.0;
                            duration: workoutModel && workoutModel.currentStreak >= 7 ? 700 : 1000;
                            easing.type: Easing.InOutSine
                        }
                    }

                    // Counter-rotation for variety
                    SequentialAnimation on rotation {
                        running: workoutModel && workoutModel.currentStreak >= 7
                        loops: Animation.Infinite
                        NumberAnimation { from: 0; to: -360; duration: 3500; easing.type: Easing.Linear }
                    }
                }
            }
            
            // Motivational message
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: workoutModel ? workoutModel.streakMessage : ""
                font.pixelSize: 14
                font.italic: true
                color: "white"
                visible: workoutModel && workoutModel.streakMessage !== ""
                opacity: 0.9
            }
            
            // Best streak (smaller text)
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: workoutModel ? (workoutModel.longestStreak !== 1 ? qsTr("Personal best: %1 days") : qsTr("Personal best: %1 day")).arg(workoutModel.longestStreak) : ""
                font.pixelSize: 12
                color: "white"
                visible: workoutModel && workoutModel.longestStreak > workoutModel.currentStreak && workoutModel.longestStreak > 0
                opacity: 0.7
            }
        }
        
        // Subtle shadow effect at the top
        Rectangle {
            visible: !workoutHistoryPage.modern
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#40000000" }
                GradientStop { position: 1.0; color: "#00000000" }
            }
        }
    }

    // Calendar Popup
    UiPopup {
        id: calendarPopup
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: Math.min(parent.width * 0.9, 400)
        height: Math.min(parent.height * 0.8, 500)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        
        onOpened: {
            // Refresh workout dates when calendar opens
            if (workoutModel) {
                calendar.workoutDates = workoutModel.getWorkoutDates()
                console.log("Calendar opened, refreshed workout dates:", JSON.stringify(calendar.workoutDates))
            }
        }

        background: Rectangle {
            color: workoutHistoryPage.modern ? window.ui.surfaceHigh : "white"
            radius: workoutHistoryPage.modern ? 28 : 12
            border.color: "#d0d0d0"
            border.width: workoutHistoryPage.modern ? 0 : 1

            // Shadow effect
            Rectangle {
                visible: !workoutHistoryPage.modern
                anchors.fill: parent
                anchors.topMargin: 2
                anchors.leftMargin: 2
                radius: parent.radius
                color: "#40000000"
                z: -1
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // Calendar Header
            RowLayout {
                Layout.fillWidth: true
                
                UiButton {
                    text: workoutHistoryPage.modern ? "" : "<"
                    flat: workoutHistoryPage.modern
                    implicitWidth: workoutHistoryPage.modern ? 48 : Math.max(implicitBackgroundWidth + leftInset + rightInset, implicitContentWidth + leftPadding + rightPadding)
                    Accessible.name: qsTr("Previous month")
                    onClicked: calendar.selectedDate = new Date(calendar.selectedDate.getFullYear(), calendar.selectedDate.getMonth() - 1, 1)
                    // Modern: an accent chevron on a tonal circle, like the move buttons of the
                    // workout editor; the bare thin chevron was hard to see
                    Rectangle {
                        anchors.centerIn: parent
                        visible: workoutHistoryPage.modern
                        width: 44
                        height: 44
                        radius: 22
                        color: window.ui.alpha(window.ui.accent, parent.pressed ? 0.28 : 0.16)
                    }
                    UiIcon {
                        anchors.centerIn: parent
                        visible: workoutHistoryPage.modern
                        width: 30
                        height: 30
                        name: "chevron_left"
                        color: window.ui.accent
                    }
                }
                
                Text {
                    Layout.fillWidth: true
                    // Modern: the standalone month name of the locale (nominative, capitalised)
                    text: workoutHistoryPage.modern
                          ? workoutHistoryPage.monthTitle(calendar.selectedDate)
                          : calendar.selectedDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                    font.pixelSize: 18
                    font.bold: true
                    color: window.ui.ink("black")
                    horizontalAlignment: Text.AlignHCenter
                }
                
                UiButton {
                    text: workoutHistoryPage.modern ? "" : ">"
                    flat: workoutHistoryPage.modern
                    implicitWidth: workoutHistoryPage.modern ? 48 : Math.max(implicitBackgroundWidth + leftInset + rightInset, implicitContentWidth + leftPadding + rightPadding)
                    Accessible.name: qsTr("Next month")
                    onClicked: calendar.selectedDate = new Date(calendar.selectedDate.getFullYear(), calendar.selectedDate.getMonth() + 1, 1)
                    // Modern: an accent chevron on a tonal circle, like the move buttons of the
                    // workout editor; the bare thin chevron was hard to see
                    Rectangle {
                        anchors.centerIn: parent
                        visible: workoutHistoryPage.modern
                        width: 44
                        height: 44
                        radius: 22
                        color: window.ui.alpha(window.ui.accent, parent.pressed ? 0.28 : 0.16)
                    }
                    UiIcon {
                        anchors.centerIn: parent
                        visible: workoutHistoryPage.modern
                        width: 30
                        height: 30
                        name: "chevron_right"
                        color: window.ui.accent
                    }
                }
            }

            // Calendar Grid
            GridLayout {
                id: calendar
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 7
                
                property date selectedDate: new Date()
                property var workoutDates: workoutModel ? workoutModel.getWorkoutDates() : []
                
                // Debug: print workout dates when they change
                onWorkoutDatesChanged: {
                    console.log("Calendar workout dates updated:", JSON.stringify(workoutDates))
                }
                
                // Day headers
                Repeater {
                    // Modern: the short day names of the locale, from its first day of the week
                    model: workoutHistoryPage.modern ? workoutHistoryPage.weekDayNames()
                         : [qsTr("Sun"), qsTr("Mon"), qsTr("Tue"), qsTr("Wed"), qsTr("Thu"), qsTr("Fri"), qsTr("Sat")]
                    Text {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        text: modelData
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: window.ui.inkMuted("#666666")
                    }
                }
                
                // Calendar days
                Repeater {
                    model: getCalendarDays()
                    
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 40
                        
                        property date dayDate: modelData.date
                        property bool isCurrentMonth: modelData.currentMonth
                        property bool hasWorkout: modelData.hasWorkout
                        property bool isToday: dayDate.toDateString() === new Date().toDateString()
                        
                        // Modern: the cell itself is bare; the round day on top of it is filled
                        // only when there was a workout, and today gets a ring
                        color: {
                            if (workoutHistoryPage.modern)
                                return "transparent"
                            if (mouseArea.pressed) return "#e3f2fd"
                            if (isToday) return "#bbdefb"
                            if (!isCurrentMonth) return "#f5f5f5"
                            return "white"
                        }

                        border.color: isToday ? "#2196f3" : "#e0e0e0"
                        border.width: workoutHistoryPage.modern ? 0 : (isToday ? 2 : 1)
                        radius: workoutHistoryPage.modern ? 10 : 4

                        UiFrame {
                            visible: workoutHistoryPage.modern
                            anchors.centerIn: parent
                            width: Math.min(40, parent.width - 2, parent.height - 2)
                            height: width
                            radius: width / 2
                            base: window.ui.surfaceHigh
                            fill: mouseArea.pressed ? window.ui.surfaceHighest
                                : hasWorkout ? window.ui.alpha(window.ui.accent, isCurrentMonth ? 0.28 : 0.12)
                                : "transparent"
                            stroke: window.ui.accent
                            strokeWidth: isToday ? 2 : 0
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 2

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: dayDate.getDate()
                                color: workoutHistoryPage.modern ? (isCurrentMonth ? window.ui.textMain : window.ui.textMuted)
                                                                 : (isCurrentMonth ? "black" : "#cccccc")
                                opacity: workoutHistoryPage.modern && !isCurrentMonth ? 0.6 : 1
                                font.pixelSize: 14
                                font.weight: workoutHistoryPage.modern && (hasWorkout || isToday) ? Font.DemiBold : Font.Normal
                            }
                            
                            // Workout indicator dot
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 8
                                height: 8
                                radius: 4
                                color: workoutHistoryPage.modern ? window.ui.accent : "#ff6b35"
                                visible: hasWorkout && !workoutHistoryPage.modern
                                border.width: workoutHistoryPage.modern ? 0 : 1
                                border.color: "#cc5529"
                                
                                // Debug: log when a dot should be visible
                                Component.onCompleted: {
                                    if (hasWorkout) {
                                        console.log("Workout dot visible for date:", dayDate.toDateString())
                                    }
                                }
                            }
                        }
                        
                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            
                            onClicked: {
                                if (isCurrentMonth) {
                                    var year = dayDate.getFullYear();
                                    var month = dayDate.getMonth() + 1; // i mesi JS sono 0-indicizzati
                                    var day = dayDate.getDate();
                                    var dateString = year + "-" + (month < 10 ? '0' + month : month) + "-" + (day < 10 ? '0' + day : day);

                                    workoutModel.setDateFilter(dateString);
                                    calendarPopup.close();
                                }
                            }
                        }
                    }
                }
            }
            
            // Close button
            UiButton {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Close")
                onClicked: calendarPopup.close()
            }
        }
    }

    // JavaScript functions for calendar

    // First day of the week (0 = Sunday, as Date.getDay()): the locale's in the modern look
    function weekStart() {
        return workoutHistoryPage.modern ? Qt.locale().firstDayOfWeek % 7 : 0
    }

    function weekDayNames() {
        var names = []
        for (var i = 0; i < 7; i++)
            names.push(Qt.locale().dayName((weekStart() + i) % 7, Locale.ShortFormat))
        return names
    }

    function monthTitle(date) {
        var name = Qt.locale().standaloneMonthName(date.getMonth(), Locale.LongFormat)
        return name.charAt(0).toUpperCase() + name.slice(1) + " " + date.getFullYear()
    }

    function getCalendarDays() {
        var days = []
        var firstDay = new Date(calendar.selectedDate.getFullYear(), calendar.selectedDate.getMonth(), 1)
        var lastDay = new Date(calendar.selectedDate.getFullYear(), calendar.selectedDate.getMonth() + 1, 0)
        var startDate = new Date(firstDay)
        // Go back to start of week: Sunday in the classic look, the locale's first day in the modern one
        startDate.setDate(startDate.getDate() - (firstDay.getDay() - weekStart() + 7) % 7)
        
        var workoutDates = calendar.workoutDates || []
        console.log("getCalendarDays: workoutDates received:", JSON.stringify(workoutDates))
        
        // workoutDates is now a QStringList (array of strings in format "yyyy-MM-dd")
        var workoutDateStrings = workoutDates || []
        console.log("Final workout date strings:", JSON.stringify(workoutDateStrings))
        
        for (var i = 0; i < 42; i++) { // 6 rows x 7 days
            var currentDate = new Date(startDate)
            currentDate.setDate(startDate.getDate() + i)
            
            // Costruisci la stringa YYYY-MM-DD dai componenti della data locale per evitare problemi di fuso orario
            var year = currentDate.getFullYear();
            var month = currentDate.getMonth() + 1; // i mesi JS sono 0-indicizzati
            var day = currentDate.getDate();
            var localDateString = year + "-" + (month < 10 ? '0' + month : month) + "-" + (day < 10 ? '0' + day : day);

            var hasWorkout = workoutDateStrings.indexOf(localDateString) !== -1;
            if (hasWorkout) {
                // Questo console.log ora utilizza la stringa della data locale corretta per la corrispondenza
                console.log("Found workout match for:", localDateString);
            }
            
            var isCurrentMonth = currentDate.getMonth() === calendar.selectedDate.getMonth()
            
            days.push({
                date: currentDate,
                currentMonth: isCurrentMonth,
                hasWorkout: hasWorkout
            })
        }
        
        console.log("getCalendarDays: returning", days.length, "days")
        return days
    }
}
