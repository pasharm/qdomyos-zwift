import QtQuick 2.7
import QtQuick.Layouts 1.3
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.0
import Qt.labs.settings 1.0

ScrollView {
    contentWidth: -1
    // Modern look: with the column's top and bottom margins, not in its implicit height (the
    // end of the page was cut off). The classic look keeps the plain height
    contentHeight: customGearsColumn.implicitHeight + (window.ui.modern ? 20 : 0)
    focus: true
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.fill: parent
    id: customGearSettingsWindow
    visible: true
    clip: true

    Settings {
        id: settings
        property bool gears_custom_table_enabled: false
        property string gears_custom_table: "1|1\n2|2\n3|3\n4|4\n5|5\n6|6\n7|7\n8|8\n9|9\n10|10\n11|11\n12|12\n13|13\n14|14\n15|15\n16|16\n17|17\n18|18\n19|19\n20|20\n21|21\n22|22\n23|23\n24|24"
    }

    ListModel {
        id: gearListModel
    }

    property var gearRows: []
    property int rowHeight: 55
    property int offsetControlHeight: 43

    Component.onCompleted: {
        loadGearRows()
    }

    function clampOffset(value) {
        if (isNaN(value)) {
            return 0
        }
        return Math.max(-100, Math.min(100, value))
    }

    function parseOffset(value) {
        return parseFloat(String(value).replace(",", "."))
    }

    function defaultGearRows() {
        var rows = []
        for (var i = 1; i <= 24; i++) {
            rows.push({ gear: i, offset: i })
        }
        return rows
    }

    function loadGearRows() {
        var parsed = stringToGearRows(settings.gears_custom_table)
        gearRows = parsed.length === 24 ? parsed : defaultGearRows()
        updateGearListModel()
        saveGearRows()
    }

    function stringToGearRows(gearString) {
        if (!gearString) {
            return []
        }

        var rows = []
        var lines = gearString.split("\n")
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].split("|")
            if (parts.length < 2) {
                continue
            }
            var gear = parseInt(parts[0])
            var offset = clampOffset(parseOffset(parts[1]))
            if (gear >= 1 && gear <= 24) {
                rows[gear - 1] = { gear: gear, offset: offset }
            }
        }

        var compactRows = []
        for (var j = 1; j <= 24; j++) {
            compactRows.push(rows[j - 1] ? rows[j - 1] : { gear: j, offset: j })
        }
        return compactRows
    }

    function gearRowsToString(rows) {
        return rows.map(function(row) {
            return row.gear + "|" + clampOffset(parseOffset(row.offset))
        }).join("\n")
    }

    function saveGearRows() {
        settings.gears_custom_table = gearRowsToString(gearRows)
    }

    function updateGearListModel() {
        if (!gearListModel) {
            return
        }
        gearListModel.clear()
        for (var i = 0; i < gearRows.length; i++) {
            gearListModel.append(gearRows[i])
        }
    }

    ColumnLayout {
        id: customGearsColumn
        anchors.fill: parent
        anchors.margins: 10
        anchors.leftMargin: window.contentSideMargin
        anchors.rightMargin: window.contentSideMargin
        spacing: 10

        IndicatorOnlySwitch {
            text: qsTr("Enable Custom Gear Table")
            spacing: 0
            bottomPadding: 0
            topPadding: 0
            rightPadding: 0
            leftPadding: 0
            clip: false
            checked: settings.gears_custom_table_enabled
            Layout.alignment: Qt.AlignLeft | Qt.AlignTop
            Layout.fillWidth: true
            onClicked: settings.gears_custom_table_enabled = checked
        }

        Label {
            text: qsTr("Each gear uses the offset below instead of the raw gear value. QZ applies it automatically to resistance, inclination, or slope depending on the trainer path. Default is linear.")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            font.pixelSize: Qt.application.font.pixelSize - 2
            color: window.ui.modern ? window.ui.textMuted : Material.accent
        }

        UiButton {
            text: qsTr("Reset to Linear Defaults")
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            onClicked: {
                gearRows = defaultGearRows()
                updateGearListModel()
                saveGearRows()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            color: window.ui.modern ? window.ui.surfaceHigh : "#f0f0f0"
            border.width: window.ui.modern ? 0 : 1
            border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
            radius: window.ui.modern ? 12 : 0

            // Modern look: a narrow gear number, the offset field gets the room (as the Wahoo table)
            Row {
                anchors.fill: parent

                Rectangle {
                    width: parent.width * (window.ui.modern ? 0.24 : 1 / 2)
                    height: parent.height
                    border.width: window.ui.modern ? 0 : 1
                    border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                    color: "transparent"

                    Text {
                        anchors.centerIn: parent
                        // Modern look: one line inside its column, smaller if it does not fit
                        width: window.ui.modern ? parent.width - 8 : implicitWidth
                        horizontalAlignment: Text.AlignHCenter
                        fontSizeMode: window.ui.modern ? Text.HorizontalFit : Text.FixedSize
                        minimumPixelSize: 9
                        text: qsTr("Gear")
                        font.bold: true
                        color: window.ui.modern ? window.ui.textMain : "black"
                    }
                }

                Rectangle {
                    width: parent.width * (window.ui.modern ? 0.76 : 1 / 2)
                    height: parent.height
                    border.width: window.ui.modern ? 0 : 1
                    border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                    color: "transparent"

                    Text {
                        anchors.centerIn: parent
                        width: window.ui.modern ? parent.width - 8 : implicitWidth
                        horizontalAlignment: Text.AlignHCenter
                        fontSizeMode: window.ui.modern ? Text.HorizontalFit : Text.FixedSize
                        minimumPixelSize: 9
                        text: qsTr("Offset")
                        font.bold: true
                        color: window.ui.modern ? window.ui.textMain : "black"
                    }
                }
            }
        }

        ListView {
            id: gearTable
            Layout.fillWidth: true
            // Modern look: all the rows in the page height, the page scrolls them - a list scrolling
            // inside the scrolled page caught the swipe, and the end of the table stayed out of reach
            Layout.preferredHeight: window.ui.modern ? contentHeight : 24 * rowHeight
            Layout.minimumHeight: window.ui.modern ? contentHeight : 0
            interactive: !window.ui.modern
            clip: true
            // Modern look: rounded rows apart from each other
            spacing: window.ui.modern ? 4 : 0
            model: gearListModel

            Component.onCompleted: {
                updateGearListModel()
            }

            ScrollBar.vertical: ScrollBar {
                policy: window.ui.modern ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded
            }

            delegate: Rectangle {
                width: gearTable.width
                height: window.ui.modern ? 48 : rowHeight
                radius: window.ui.modern ? 12 : 0
                color: window.ui.modern ? window.ui.surface : (index % 2 === 0 ? "white" : "#fafafa")

                Row {
                    anchors.fill: parent

                    Rectangle {
                        width: parent.width * (window.ui.modern ? 0.24 : 1 / 2)
                        height: parent.height
                        border.width: window.ui.modern ? 0 : 1
                        border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                        color: "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: gear
                            color: window.ui.modern ? window.ui.textMain : "black"
                        }
                    }

                    Rectangle {
                        id: offsetCell
                        width: parent.width * (window.ui.modern ? 0.76 : 1 / 2)
                        height: parent.height
                        border.width: window.ui.modern ? 0 : 1
                        border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                        color: "transparent"

                        function stepOffset(delta) {
                            gearRows[index].offset = clampOffset(parseOffset(gearRows[index].offset) + delta)
                            offsetTextField.text = gearRows[index].offset
                            saveGearRows()
                        }

                        // Modern look: one rounded field with the -/+ squares inside, as the
                        // Wahoo table; the pill buttons were too narrow for their signs
                        Rectangle {
                            visible: window.ui.modern
                            anchors.fill: offsetRow
                            radius: 8
                            color: window.ui.surfaceHighest
                        }

                        RowLayout {
                            id: offsetRow
                            anchors.centerIn: parent
                            width: parent.width * (window.ui.modern ? 0.88 : 0.92)
                            height: window.ui.modern ? 36 : offsetControlHeight
                            spacing: window.ui.modern ? 0 : 4

                            UiButton {
                                visible: !window.ui.modern
                                text: "-"
                                Layout.preferredWidth: 34
                                Layout.fillHeight: true
                                onClicked: offsetCell.stepOffset(-0.5)
                            }

                            Rectangle {
                                visible: window.ui.modern
                                Layout.preferredWidth: height
                                Layout.fillHeight: true
                                radius: 8
                                color: minusArea.pressed ? window.ui.surfaceHigh : window.ui.surfaceHighest
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 12; height: 2; radius: 1
                                    color: window.ui.textMain
                                }
                                MouseArea {
                                    id: minusArea
                                    anchors.fill: parent
                                    onClicked: offsetCell.stepOffset(-0.5)
                                }
                            }

                            TextField {
                                id: offsetTextField
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: offset
                                color: window.ui.modern ? window.ui.textMain : "black"
                                selectedTextColor: window.ui.modern ? window.ui.accentInk : "white"
                                selectionColor: window.ui.modern ? window.ui.accent : Material.accent
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                // Modern look: no Material paddings and insets, they differ above
                                // and below and the number sat high in the low field
                                topPadding: window.ui.modern ? 0 : undefined
                                bottomPadding: window.ui.modern ? 0 : undefined
                                topInset: window.ui.modern ? 0 : undefined
                                bottomInset: window.ui.modern ? 0 : undefined
                                background: Rectangle {
                                    color: window.ui.modern ? "transparent" : "white"
                                    border.color: "#cccccc"
                                    border.width: window.ui.modern ? 0 : 1
                                    radius: 2
                                }
                                function applyOffset() {
                                    var newOffset = clampOffset(parseOffset(text))
                                    gearRows[index].offset = newOffset
                                    text = newOffset
                                    saveGearRows()
                                }
                                onAccepted: applyOffset()
                                onEditingFinished: applyOffset()
                            }

                            UiButton {
                                visible: !window.ui.modern
                                text: "+"
                                Layout.preferredWidth: 34
                                Layout.fillHeight: true
                                onClicked: offsetCell.stepOffset(0.5)
                            }

                            Rectangle {
                                visible: window.ui.modern
                                Layout.preferredWidth: height
                                Layout.fillHeight: true
                                radius: 8
                                color: plusArea.pressed ? window.ui.surfaceHigh : window.ui.surfaceHighest
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 12; height: 2; radius: 1
                                    color: window.ui.textMain
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 2; height: 12; radius: 1
                                    color: window.ui.textMain
                                }
                                MouseArea {
                                    id: plusArea
                                    anchors.fill: parent
                                    onClicked: offsetCell.stepOffset(0.5)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
