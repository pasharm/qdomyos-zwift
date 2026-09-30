import QtQuick 2.7
import QtQuick.Layouts 1.3
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.0
import Qt.labs.settings 1.0

ScrollView {
    id: customInclinationResistanceWindow
    contentWidth: -1
    focus: true
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.fill: parent
    clip: true

    property string defaultInclinationResistanceTable: "0|4\n1|6\n2|8\n3|10\n4|11\n5|11.5\n6|12\n8|13\n10|14\n12|15\n15|16"
    property int rowHeight: 55
    property int controlHeight: 43

    // Modern look: a +/- field of the table, as on the Wahoo Options page. The classic one is a
    // text field between two buttons; its "-" and "+" did not fit the modern button and showed
    // as empty circles
    component Stepper: Rectangle {
        id: stepper
        property alias text: stepperInput.text
        signal step(real delta)
        signal edited(string value)
        radius: 12
        color: window.ui.surfaceHighest

        MouseArea {
            id: stepperMinus
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: height
            onClicked: stepper.step(-0.5)
            Accessible.role: Accessible.Button
            Accessible.name: "-"
            Rectangle { anchors.fill: parent; radius: 12; color: window.ui.surfaceHigh; visible: stepperMinus.pressed }
            Rectangle { anchors.centerIn: parent; width: 12; height: 2; radius: 1; color: window.ui.textMain }
        }
        MouseArea {
            id: stepperPlus
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: height
            onClicked: stepper.step(0.5)
            Accessible.role: Accessible.Button
            Accessible.name: "+"
            Rectangle { anchors.fill: parent; radius: 12; color: window.ui.surfaceHigh; visible: stepperPlus.pressed }
            Rectangle { anchors.centerIn: parent; width: 12; height: 2; radius: 1; color: window.ui.textMain }
            Rectangle { anchors.centerIn: parent; width: 2; height: 12; radius: 1; color: window.ui.textMain }
        }
        UiSpinInput {
            id: stepperInput
            anchors.left: stepperMinus.right
            anchors.right: stepperPlus.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            font.pixelSize: 16
            color: window.ui.textMain
            selectionColor: window.ui.accent
            selectedTextColor: window.ui.accentInk
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            onAccepted: stepper.edited(text)
            onEditingFinished: stepper.edited(text)
        }
    }

    Settings {
        id: settings
        property bool custom_inclination_resistance_table_enabled: false
        property string custom_inclination_resistance_table: defaultInclinationResistanceTable
    }

    ListModel {
        id: pointListModel
    }

    Component.onCompleted: loadPoints()

    function parseNumber(value) {
        return parseFloat(String(value).replace(",", "."))
    }

    function formatNumber(value) {
        var number = parseNumber(value)
        if (isNaN(number)) {
            return "0"
        }
        return Number(number.toFixed(2)).toString()
    }

    function normalizeResistance(value) {
        var number = parseNumber(value)
        if (isNaN(number)) {
            return 0
        }
        return Math.max(0, number)
    }

    function defaultPoints() {
        return [
            { inclination: 0, resistance: 4 },
            { inclination: 1, resistance: 6 },
            { inclination: 2, resistance: 8 },
            { inclination: 3, resistance: 10 },
            { inclination: 4, resistance: 11 },
            { inclination: 5, resistance: 11.5 },
            { inclination: 6, resistance: 12 },
            { inclination: 8, resistance: 13 },
            { inclination: 10, resistance: 14 },
            { inclination: 12, resistance: 15 },
            { inclination: 15, resistance: 16 }
        ]
    }

    function stringToPoints(tableString) {
        if (!tableString) {
            return []
        }

        var points = []
        var lines = tableString.replace(/;/g, "\n").split("\n")
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].split("|")
            if (parts.length < 2) {
                continue
            }

            var inclination = parseNumber(parts[0])
            var resistance = parseNumber(parts[1])
            if (isNaN(inclination) || isNaN(resistance)) {
                continue
            }

            points.push({
                inclination: inclination,
                resistance: normalizeResistance(resistance)
            })
        }

        points.sort(function(a, b) {
            return a.inclination - b.inclination
        })
        return points
    }

    function setPoints(points) {
        pointListModel.clear()
        for (var i = 0; i < points.length; i++) {
            pointListModel.append({
                inclination: points[i].inclination,
                resistance: points[i].resistance
            })
        }
    }

    function loadPoints() {
        var points = stringToPoints(settings.custom_inclination_resistance_table)
        if (points.length === 0) {
            points = defaultPoints()
        }
        setPoints(points)
        savePoints()
    }

    function pointsToString() {
        var rows = []
        for (var i = 0; i < pointListModel.count; i++) {
            var point = pointListModel.get(i)
            rows.push(formatNumber(point.inclination) + "|" + formatNumber(point.resistance))
        }
        return rows.join("\n")
    }

    function savePoints() {
        settings.custom_inclination_resistance_table = pointsToString()
    }

    function sortPointsAndSave() {
        var points = []
        for (var i = 0; i < pointListModel.count; i++) {
            var point = pointListModel.get(i)
            points.push({
                inclination: parseNumber(point.inclination),
                resistance: normalizeResistance(point.resistance)
            })
        }

        points.sort(function(a, b) {
            return a.inclination - b.inclination
        })
        setPoints(points)
        savePoints()
    }

    function updatePoint(index, role, value) {
        var currentPoint = pointListModel.get(index)
        var parsed = parseNumber(value)
        if (isNaN(parsed)) {
            parsed = role === "inclination" ? currentPoint.inclination : currentPoint.resistance
        }
        if (role === "resistance") {
            parsed = normalizeResistance(parsed)
        }
        pointListModel.setProperty(index, role, parsed)
        savePoints()
        return formatNumber(parsed)
    }

    function adjustPoint(index, role, delta) {
        var point = pointListModel.get(index)
        var current = role === "inclination" ? point.inclination : point.resistance
        var updated = parseNumber(current) + delta
        if (role === "resistance") {
            updated = normalizeResistance(updated)
        }
        pointListModel.setProperty(index, role, updated)
        savePoints()
        return formatNumber(updated)
    }

    function addPoint() {
        var inclination = 0
        var resistance = 1
        if (pointListModel.count > 0) {
            var lastPoint = pointListModel.get(pointListModel.count - 1)
            inclination = parseNumber(lastPoint.inclination) + 1
            resistance = normalizeResistance(lastPoint.resistance)
        }

        pointListModel.append({
            inclination: inclination,
            resistance: resistance
        })
        savePoints()
    }

    function removePoint(index) {
        if (pointListModel.count <= 1) {
            return
        }
        pointListModel.remove(index)
        savePoints()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        anchors.leftMargin: window.contentSideMargin
        anchors.rightMargin: window.contentSideMargin
        spacing: 10

        IndicatorOnlySwitch {
            text: qsTr("Enable Custom Inclination to Resistance Table")
            spacing: 0
            bottomPadding: 0
            topPadding: 0
            rightPadding: 0
            leftPadding: 0
            clip: false
            checked: settings.custom_inclination_resistance_table_enabled
            Layout.alignment: Qt.AlignLeft | Qt.AlignTop
            Layout.fillWidth: true
            onClicked: settings.custom_inclination_resistance_table_enabled = checked
        }

        Label {
            text: qsTr("Set the resistance QZ should target at each incline. QZ interpolates automatically between points and uses the nearest endpoint outside the configured range. Changes are saved automatically.")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            font.pixelSize: Qt.application.font.pixelSize - 2
            color: window.ui.modern ? window.ui.textMuted : Material.accent
        }

        // Modern look: the column titles over the fields, no grid
        RowLayout {
            visible: window.ui.modern
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8
            Label {
                text: qsTr("Inclination (%)")
                color: window.ui.textMuted
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
                Layout.preferredWidth: 1
            }
            Label {
                text: qsTr("Resistance")
                color: window.ui.textMuted
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
                Layout.preferredWidth: 1
            }
            Item { Layout.preferredWidth: 44 }
        }

        Rectangle {
            visible: !window.ui.modern
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            color: window.ui.modern ? window.ui.surfaceHigh : "#f0f0f0"
            border.width: 1
            border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"

            Row {
                anchors.fill: parent

                Rectangle {
                    width: parent.width * 0.43
                    height: parent.height
                    border.width: 1
                    border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                    color: "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Inclination (%)")
                        font.bold: true
                        color: window.ui.modern ? window.ui.textMain : "black"
                    }
                }

                Rectangle {
                    width: parent.width * 0.43
                    height: parent.height
                    border.width: 1
                    border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                    color: "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Resistance")
                        font.bold: true
                        color: window.ui.modern ? window.ui.textMain : "black"
                    }
                }

                Rectangle {
                    width: parent.width * 0.14
                    height: parent.height
                    border.width: 1
                    border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                    color: "transparent"
                }
            }
        }

        ListView {
            id: pointTable
            Layout.fillWidth: true
            Layout.preferredHeight: pointListModel.count * rowHeight
            clip: true
            model: pointListModel
            interactive: false

            delegate: Rectangle {
                width: pointTable.width
                height: rowHeight
                color: window.ui.modern ? "transparent" : (index % 2 === 0 ? "white" : "#fafafa")

                RowLayout {
                    visible: window.ui.modern
                    anchors.fill: parent
                    anchors.topMargin: 5
                    anchors.bottomMargin: 6
                    spacing: 8

                    Stepper {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        text: formatNumber(inclination)
                        onStep: {
                            text = adjustPoint(index, "inclination", delta)
                            Qt.callLater(sortPointsAndSave)
                        }
                        onEdited: {
                            text = updatePoint(index, "inclination", value)
                            Qt.callLater(sortPointsAndSave)
                        }
                    }

                    Stepper {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        text: formatNumber(resistance)
                        onStep: text = adjustPoint(index, "resistance", delta)
                        onEdited: text = updatePoint(index, "resistance", value)
                    }

                    MouseArea {
                        id: removeButton
                        Layout.preferredWidth: 44
                        Layout.fillHeight: true
                        enabled: pointListModel.count > 1
                        onClicked: removePoint(index)
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Remove")
                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: removeButton.pressed ? window.ui.surfaceHigh : "transparent"
                        }
                        UiIcon {
                            anchors.centerIn: parent
                            width: 20
                            height: 20
                            name: "close"
                            color: window.ui.textMuted
                            opacity: removeButton.enabled ? 1 : 0.35
                        }
                    }
                }

                Row {
                    visible: !window.ui.modern
                    anchors.fill: parent

                    Rectangle {
                        width: parent.width * 0.43
                        height: parent.height
                        border.width: 1
                        border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                        color: "transparent"

                        RowLayout {
                            anchors.centerIn: parent
                            width: parent.width * 0.94
                            height: controlHeight
                            spacing: 4

                            UiButton {
                                text: "-"
                                Layout.preferredWidth: 34
                                Layout.fillHeight: true
                                onClicked: {
                                    inclinationField.text = adjustPoint(index, "inclination", -0.5)
                                    Qt.callLater(sortPointsAndSave)
                                }
                            }

                            TextField {
                                id: inclinationField
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: formatNumber(inclination)
                                color: window.ui.modern ? window.ui.textMain : "black"
                                selectedTextColor: window.ui.modern ? window.ui.accentInk : "white"
                                selectionColor: Material.accent
                                horizontalAlignment: Text.AlignHCenter
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                background: Rectangle {
                                    color: window.ui.modern ? window.ui.surfaceHighest : "white"
                                    border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                                    radius: 2
                                }
                                function applyValue() {
                                    text = updatePoint(index, "inclination", text)
                                    Qt.callLater(sortPointsAndSave)
                                }
                                onAccepted: applyValue()
                                onEditingFinished: applyValue()
                            }

                            UiButton {
                                text: "+"
                                Layout.preferredWidth: 34
                                Layout.fillHeight: true
                                onClicked: {
                                    inclinationField.text = adjustPoint(index, "inclination", 0.5)
                                    Qt.callLater(sortPointsAndSave)
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width * 0.43
                        height: parent.height
                        border.width: 1
                        border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                        color: "transparent"

                        RowLayout {
                            anchors.centerIn: parent
                            width: parent.width * 0.94
                            height: controlHeight
                            spacing: 4

                            UiButton {
                                text: "-"
                                Layout.preferredWidth: 34
                                Layout.fillHeight: true
                                onClicked: resistanceField.text = adjustPoint(index, "resistance", -0.5)
                            }

                            TextField {
                                id: resistanceField
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: formatNumber(resistance)
                                color: window.ui.modern ? window.ui.textMain : "black"
                                selectedTextColor: window.ui.modern ? window.ui.accentInk : "white"
                                selectionColor: Material.accent
                                horizontalAlignment: Text.AlignHCenter
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                background: Rectangle {
                                    color: window.ui.modern ? window.ui.surfaceHighest : "white"
                                    border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                                    radius: 2
                                }
                                function applyValue() {
                                    text = updatePoint(index, "resistance", text)
                                }
                                onAccepted: applyValue()
                                onEditingFinished: applyValue()
                            }

                            UiButton {
                                text: "+"
                                Layout.preferredWidth: 34
                                Layout.fillHeight: true
                                onClicked: resistanceField.text = adjustPoint(index, "resistance", 0.5)
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width * 0.14
                        height: parent.height
                        border.width: 1
                        border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                        color: "transparent"

                        UiButton {
                            anchors.centerIn: parent
                            width: Math.min(parent.width * 0.78, 44)
                            height: controlHeight
                            text: "×"
                            enabled: pointListModel.count > 1
                            onClicked: removePoint(index)
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            UiButton {
                text: qsTr("Add Point")
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                onClicked: addPoint()
            }

            UiButton {
                text: qsTr("Reset Example")
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                onClicked: {
                    setPoints(defaultPoints())
                    savePoints()
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
