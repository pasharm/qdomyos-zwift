import QtQuick 2.7
import QtQuick.Layouts 1.3
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.0
import Qt.labs.settings 1.0

ScrollView {
    contentWidth: -1
    focus: true
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.fill: parent
    id: gearSettingsWindow

    // The +/- field of the modern look: rounded, drawn signs, no hover or ripple
    component ModernSpin: SpinBox {
        id: spin
        from: 1
        to: 999
        hoverEnabled: false
        implicitWidth: 160
        implicitHeight: 44
        padding: 0
        leftPadding: 44
        rightPadding: 44
        topInset: 0
        bottomInset: 0
        contentItem: TextInput {
            text: spin.textFromValue(spin.value, spin.locale)
            font.pixelSize: 16
            color: window.ui.textMain
            selectionColor: window.ui.accent
            selectedTextColor: window.ui.accentInk
            horizontalAlignment: Qt.AlignHCenter
            verticalAlignment: Qt.AlignVCenter
            readOnly: !spin.editable
            validator: spin.validator
            inputMethodHints: Qt.ImhDigitsOnly
        }
        up.indicator: Rectangle {
            x: spin.width - width
            height: spin.height
            width: height
            radius: 12
            color: spin.up.pressed ? window.ui.surfaceHigh : window.ui.surfaceHighest
            Rectangle { anchors.centerIn: parent; width: 14; height: 2; radius: 1; color: window.ui.textMain }
            Rectangle { anchors.centerIn: parent; width: 2; height: 14; radius: 1; color: window.ui.textMain }
        }
        down.indicator: Rectangle {
            x: 0
            height: spin.height
            width: height
            radius: 12
            color: spin.down.pressed ? window.ui.surfaceHigh : window.ui.surfaceHighest
            Rectangle { anchors.centerIn: parent; width: 14; height: 2; radius: 1; color: window.ui.textMain }
        }
        background: Rectangle {
            radius: 12
            color: window.ui.surfaceHighest
        }
    }

    visible: true
    clip: true

    // Properties
    Settings {
        id: settings
        property string gear_configuration: "1|38|44|true\n2|38|38|true\n3|38|32|true\n4|38|28|true\n5|38|24|true\n6|38|21|true\n7|38|19|true\n8|38|17|true\n9|38|15|true\n10|38|13|true\n11|38|11|true\n12|38|10|true"
        property int gear_crankset_size: 42
        property int gear_cog_size: 14
        property string gear_wheel_size: "700 x 18C"
        property real gear_circumference: 2070
        property bool wahoo_without_wheel_diameter: false
    }

    property int selectedCranksetSize: settings.gear_crankset_size
    property int selectedCogSize: settings.gear_cog_size
    property string selectedWheelSize: settings.gear_wheel_size
    property real selectedCircumference: settings.gear_circumference
    property bool inited: false

    property int initialWheelSizeIndex: {
          // Trova l'indice corretto basato sul valore salvato
          for (let i = 0; i < wheelSizes.count; i++) {
              if (wheelSizes.get(i).text === settings.gear_wheel_size) {
                  return i;
              }
          }
          return 0; // default se non trovato
      }

    Component.onCompleted: {
        if (settings.gear_configuration) {
            gearRows = stringToGearRows(settings.gear_configuration)
        }
        restoreDefaultWheelDiameter.connect(rootItem.restoreDefaultWheelDiameter)
        console.log("Component.onCompleted " + settings.gear_crankset_size + " " + settings.gear_cog_size + " " + settings.gear_wheel_size + " " + settings.gear_circumference)
        wheelSizeCombo.currentIndex = initialWheelSizeIndex
        selectedCranksetSize = settings.gear_crankset_size
        selectedCogSize = settings.gear_cog_size
        inited = true
    }

    function updateSettings() {
        if(!inited)
            return;
        settings.gear_crankset_size = selectedCranksetSize
        settings.gear_cog_size = selectedCogSize
        settings.gear_wheel_size = selectedWheelSize
        settings.gear_circumference = selectedCircumference
    }

    function stringToGearRows(gearString) {
        if (!gearString) return []

        return gearString.split("\n").map(function(row) {
            const parts = row.split("|")
            return {
                gear: parseInt(parts[0]),
                crankset: parseInt(parts[1]),
                cog: parseInt(parts[2]),
                active: parts[3] === "true"
            }
        })
    }

    function gearRowsToString(gearRows) {
        return gearRows.map(function(row) {
            return row.gear + "|" + row.crankset + "|" + row.cog + "|" + row.active
        }).join("\n")
    }

    // Monitora i cambiamenti nelle gear e salva automaticamente
    onGearConfigurationChanged: {
        settings.gear_configuration = gearRowsToString(gearRows)
    }

    onSettingsChanged: {
        console.log("onSettingsChanged")
        updateSettings()
    }

    Connections {
        target: gearSettingsWindow
        function onGearConfigurationChanged() {
            gearTable.updateGearListModel()
        }
    }

    function loadGearProfile(profileName) {
        if (profileName in gearProfiles) {
            const profile = gearProfiles[profileName]

            // Create new array with copied objects
            var newGears = []
            for (var i = 0; i < profile.gears.length; i++) {
                newGears.push({
                    gear: profile.gears[i].gear,
                    crankset: profile.gears[i].crankset,
                    cog: profile.gears[i].cog,
                    active: profile.gears[i].active
                })
            }

            gearRows = newGears

            // Force update
            var temp = gearRows
            gearRows = []
            gearRows = temp
            gearConfigurationChanged(gearRows)
        }
    }

    property var gearProfiles: {
        "Time Trial": {
            name: "Time Trial (52/36, 10 - 28)",
            gears: [
                { gear: 1, crankset: 36, cog: 28, active: true },
                { gear: 2, crankset: 36, cog: 24, active: true },
                { gear: 3, crankset: 36, cog: 21, active: true },
                { gear: 4, crankset: 36, cog: 19, active: true },
                { gear: 5, crankset: 36, cog: 18, active: true },
                { gear: 6, crankset: 36, cog: 17, active: true },
                { gear: 7, crankset: 36, cog: 16, active: true },
                { gear: 8, crankset: 36, cog: 15, active: true },
                { gear: 9, crankset: 36, cog: 14, active: true },
                { gear: 10, crankset: 52, cog: 19, active: true },
                { gear: 11, crankset: 52, cog: 18, active: true },
                { gear: 12, crankset: 52, cog: 17, active: true },
                { gear: 13, crankset: 52, cog: 16, active: true },
                { gear: 14, crankset: 52, cog: 15, active: true },
                { gear: 15, crankset: 52, cog: 14, active: true },
                { gear: 16, crankset: 52, cog: 13, active: true },
                { gear: 17, crankset: 52, cog: 12, active: true },
                { gear: 18, crankset: 52, cog: 11, active: true },
                { gear: 19, crankset: 52, cog: 10, active: true }
            ]
        },
        "Rolling Hills": {
            name: "Rolling Hills (46/33, 10 - 33)",
            gears: [
                { gear: 1, crankset: 33, cog: 33, active: true },
                { gear: 2, crankset: 33, cog: 28, active: true },
                { gear: 3, crankset: 33, cog: 24, active: true },
                { gear: 4, crankset: 33, cog: 21, active: true },
                { gear: 5, crankset: 33, cog: 19, active: true },
                { gear: 6, crankset: 33, cog: 17, active: true },
                { gear: 7, crankset: 33, cog: 15, active: true },
                { gear: 8, crankset: 46, cog: 19, active: true },
                { gear: 9, crankset: 46, cog: 17, active: true },
                { gear: 10, crankset: 46, cog: 15, active: true },
                { gear: 11, crankset: 46, cog: 14, active: true },
                { gear: 12, crankset: 46, cog: 13, active: true },
                { gear: 13, crankset: 46, cog: 12, active: true },
                { gear: 14, crankset: 46, cog: 11, active: true },
                { gear: 15, crankset: 46, cog: 10, active: true }
            ]
        },
        "Alpine": {
            name: "Alpine (43/30, 10 - 36)",
            gears: [
                { gear: 1, crankset: 30, cog: 36, active: true },
                { gear: 2, crankset: 30, cog: 32, active: true },
                { gear: 3, crankset: 30, cog: 28, active: true },
                { gear: 4, crankset: 30, cog: 24, active: true },
                { gear: 5, crankset: 30, cog: 21, active: true },
                { gear: 6, crankset: 30, cog: 19, active: true },
                { gear: 7, crankset: 30, cog: 17, active: true },
                { gear: 8, crankset: 30, cog: 15, active: true },
                { gear: 9, crankset: 43, cog: 19, active: true },
                { gear: 10, crankset: 43, cog: 17, active: true },
                { gear: 11, crankset: 43, cog: 15, active: true },
                { gear: 12, crankset: 43, cog: 13, active: true },
                { gear: 13, crankset: 43, cog: 12, active: true },
                { gear: 14, crankset: 43, cog: 11, active: true },
                { gear: 15, crankset: 43, cog: 10, active: true }
            ]
        },
        "Reality Bender": {
            name: "Reality Bender (24 even spaced)",
            gears: [
                { gear: 1, crankset: 75, cog: 100, active: true },
                { gear: 2, crankset: 87, cog: 100, active: true },
                { gear: 3, crankset: 99, cog: 100, active: true },
                { gear: 4, crankset: 111, cog: 100, active: true },
                { gear: 5, crankset: 123, cog: 100, active: true },
                { gear: 6, crankset: 138, cog: 100, active: true },
                { gear: 7, crankset: 153, cog: 100, active: true },
                { gear: 8, crankset: 168, cog: 100, active: true },
                { gear: 9, crankset: 186, cog: 100, active: true },
                { gear: 10, crankset: 204, cog: 100, active: true },
                { gear: 11, crankset: 222, cog: 100, active: true },
                { gear: 12, crankset: 240, cog: 100, active: true },
                { gear: 13, crankset: 261, cog: 100, active: true },
                { gear: 14, crankset: 282, cog: 100, active: true },
                { gear: 15, crankset: 303, cog: 100, active: true },
                { gear: 16, crankset: 324, cog: 100, active: true },
                { gear: 17, crankset: 349, cog: 100, active: true },
                { gear: 18, crankset: 374, cog: 100, active: true },
                { gear: 19, crankset: 399, cog: 100, active: true },
                { gear: 20, crankset: 424, cog: 100, active: true },
                { gear: 21, crankset: 454, cog: 100, active: true },
                { gear: 22, crankset: 484, cog: 100, active: true },
                { gear: 23, crankset: 514, cog: 100, active: true },
                { gear: 24, crankset: 549, cog: 100, active: true }
            ]
        },
        "Explorer": {
            name: "Explorer (40, 10 - 46)",
            gears: [
                { gear: 1, crankset: 40, cog: 46, active: true },
                { gear: 2, crankset: 40, cog: 38, active: true },
                { gear: 3, crankset: 40, cog: 32, active: true },
                { gear: 4, crankset: 40, cog: 28, active: true },
                { gear: 5, crankset: 40, cog: 24, active: true },
                { gear: 6, crankset: 40, cog: 21, active: true },
                { gear: 7, crankset: 40, cog: 19, active: true },
                { gear: 8, crankset: 40, cog: 17, active: true },
                { gear: 9, crankset: 40, cog: 15, active: true },
                { gear: 10, crankset: 40, cog: 13, active: true },
                { gear: 11, crankset: 40, cog: 12, active: true },
                { gear: 12, crankset: 40, cog: 11, active: true },
                { gear: 13, crankset: 40, cog: 10, active: true }
            ]
        }
    }

    // Initial gear data
    property var gearRows: [
        { gear: 1, crankset: 38, cog: 44, active: true },
        { gear: 2, crankset: 38, cog: 38, active: true },
        { gear: 3, crankset: 38, cog: 32, active: true },
        { gear: 4, crankset: 38, cog: 28, active: true },
        { gear: 5, crankset: 38, cog: 24, active: true },
        { gear: 6, crankset: 38, cog: 21, active: true },
        { gear: 7, crankset: 38, cog: 19, active: true },
        { gear: 8, crankset: 38, cog: 17, active: true },
        { gear: 9, crankset: 38, cog: 15, active: true },
        { gear: 10, crankset: 38, cog: 13, active: true },
        { gear: 11, crankset: 38, cog: 11, active: true },
        { gear: 12, crankset: 38, cog: 10, active: true }
    ]

    function addNewGear() {
        // Find the first inactive gear or add at the end
        let newGearIndex = gearRows.findIndex(row => !row.active);
        if (newGearIndex === -1) {
            newGearIndex = gearRows.length;
        }

        // Create new gear with default values
        const newGear = {
            gear: newGearIndex + 1,
            crankset: selectedCranksetSize,
            cog: selectedCogSize,
            active: true
        };

        if (newGearIndex < gearRows.length) {
            gearRows[newGearIndex] = newGear;
        } else {
            gearRows.push(newGear);
        }

        // Force update
        var temp = gearRows;
        gearRows = [];
        gearRows = temp;
        gearConfigurationChanged(gearRows);
    }

    function clearGearsFromIndex(startIndex) {
            for (let i = startIndex; i < gearRows.length; i++) {
                gearRows[i].active = false
            }
            // Force update
            var temp = gearRows
            gearRows = []
            gearRows = temp
            gearConfigurationChanged(gearRows)
    }

    function initializeGearRows() {
        gearRows = [
            { gear: 1, crankset: 38, cog: 44, active: true },
            { gear: 2, crankset: 38, cog: 38, active: true },
            { gear: 3, crankset: 38, cog: 32, active: true },
            { gear: 4, crankset: 38, cog: 28, active: true },
            { gear: 5, crankset: 38, cog: 24, active: true },
            { gear: 6, crankset: 38, cog: 21, active: true },
            { gear: 7, crankset: 38, cog: 19, active: true },
            { gear: 8, crankset: 38, cog: 17, active: true },
            { gear: 9, crankset: 38, cog: 15, active: true },
            { gear: 10, crankset: 38, cog: 13, active: true },
            { gear: 11, crankset: 38, cog: 11, active: true },
            { gear: 12, crankset: 38, cog: 10, active: true }
        ]
        // Force update
        var temp = gearRows
        gearRows = []
        gearRows = temp
        // Without it the table kept the removed gears and the reset was not saved
        gearConfigurationChanged(gearRows)
    }

    // Signals to notify when values change
    signal settingsChanged()
    signal gearConfigurationChanged(var gearRows)
    signal restoreDefaultWheelDiameter()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: window.ui.modern ? window.contentSideMargin : 20
        spacing: window.ui.modern ? 12 : 20
        id: chainringColumn

        // Wahoo Options
        UiGroupBox {
            title: qsTr("Wahoo Options")
            Layout.fillWidth: true

            ColumnLayout {
                IndicatorOnlySwitch {
                    id: wahooWithoutWheelDiameterDelegate
                    text: qsTr("Without Wheel Diameter Protocol")
                    spacing: 0
                    bottomPadding: 0
                    topPadding: 0
                    rightPadding: 0
                    leftPadding: 0
                    clip: false
                    checked: settings.wahoo_without_wheel_diameter
                    Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                    Layout.fillWidth: true
                    onClicked: settings.wahoo_without_wheel_diameter = checked
                }

                Label {
                    text: qsTr("Enable this for simplified Wahoo protocol that adds gears directly to grade instead of using wheel diameter changes. Default is false.")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.maximumWidth: chainringColumn.width - 20
                    font.pixelSize: Qt.application.font.pixelSize - 2
                    color: window.ui.modern ? window.ui.textMuted : Material.accent
                }
            }
        }

        // Crankset Size
        UiGroupBox {
            title: qsTr("Chainring Size")
            Layout.fillWidth: true

            ColumnLayout {
                Label {
                    text: qsTr("Tooth count of your chainring on the bike you are currently riding on your trainer - enter 42 for Zwift Ride")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.maximumWidth: chainringColumn.width - 20
                    color: window.ui.modern ? window.ui.textMuted : Material.foreground
                }

                SpinBox {
                    visible: !window.ui.modern
                    from: 1
                    to: 999
                    value: selectedCranksetSize
                    onValueChanged: {
                        selectedCranksetSize = value
                        console.log("Crankset Size changed");
                        settingsChanged()
                    }
                }
                // Modern look: the buttons of the table below. The Material one kept its +/- lit
                // after a tap and did not match the rest of the page
                ModernSpin {
                    visible: window.ui.modern
                    value: selectedCranksetSize
                    onValueModified: {
                        selectedCranksetSize = value
                        console.log("Crankset Size changed");
                        settingsChanged()
                    }
                }
            }
        }

        // Cog Size
        UiGroupBox {
            title: qsTr("Cog Size")
            Layout.fillWidth: true

            ColumnLayout {
                Label {
                    text: qsTr("Tooth count of your rear cog on your trainer - enter 14 if you have the Zwift Cog")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.maximumWidth: chainringColumn.width - 20
                    color: window.ui.modern ? window.ui.textMuted : Material.foreground
                }
                SpinBox {
                    visible: !window.ui.modern
                    from: 1
                    to: 999
                    value: selectedCogSize
                    onValueChanged: {
                        selectedCogSize = value
                        console.log("Cog Size changed");
                        settingsChanged()
                    }
                }
                // Modern look: the buttons of the table below. The Material one kept its +/- lit
                // after a tap and did not match the rest of the page
                ModernSpin {
                    visible: window.ui.modern
                    value: selectedCogSize
                    onValueModified: {
                        selectedCogSize = value
                        console.log("Cog Size changed");
                        settingsChanged()
                    }
                }
            }
        }

        // Wheel Size
        UiGroupBox {
            title: qsTr("Virtual Wheel Size")
            Layout.fillWidth: true

            ColumnLayout {
                UiComboBox {
                       id: wheelSizeCombo
                       width: parent.width
                       currentIndex: initialWheelSizeIndex
                       textRole: "text"
                       model: ListModel {
                       id: wheelSizes
                        ListElement { text: "700 x 18C"; circumference: 2070 }
                        ListElement { text: "700 x 19C"; circumference: 2080 }
                        ListElement { text: "700 x 20C"; circumference: 2086 }
                        ListElement { text: "700 x 23C"; circumference: 2096 }
                        ListElement { text: "700 x 25C"; circumference: 2109 }
                        ListElement { text: "700 x 28C"; circumference: 2127 }
                        ListElement { text: "700 x 30C"; circumference: 2140 }
                        ListElement { text: "700 x 32C"; circumference: 2152 }
                        ListElement { text: "700 x 35C"; circumference: 2171 }
                        ListElement { text: "700 x 38C"; circumference: 2190 }
                        ListElement { text: "700 x 40C"; circumference: 2203 }
                        ListElement { text: "700 x 44C"; circumference: 2230 }
                        ListElement { text: "700 x 45C"; circumference: 2234 }
                        ListElement { text: "700 x 47C"; circumference: 2247 }
                        ListElement { text: "700 x 50C"; circumference: 2265 }
                        ListElement { text: "650 x 20C"; circumference: 1938 }
                        ListElement { text: "650 x 23C"; circumference: 1944 }
                        ListElement { text: "650 x 35A"; circumference: 2090 }
                        ListElement { text: "650 x 38B"; circumference: 2105 }
                        ListElement { text: "650 x 38A"; circumference: 2125 }
                        ListElement { text: "12\" x 1.75\""; circumference: 935 }
                        ListElement { text: "12\" x 1.95\""; circumference: 940 }
                        ListElement { text: "14\" x 1.50\""; circumference: 1020 }
                        ListElement { text: "14\" x 1.75\""; circumference: 1055 }
                        ListElement { text: "16\" x 1.50\""; circumference: 1185 }
                        ListElement { text: "16\" x 1.75\""; circumference: 1195 }
                        ListElement { text: "16\" x 2.00\""; circumference: 1245 }
                        ListElement { text: "16\" x 1-1/8\""; circumference: 1290 }
                        ListElement { text: "16\" x 1-3/8\""; circumference: 1300 }
                        ListElement { text: "18\" x 1.50\""; circumference: 1340 }
                        ListElement { text: "18\" x 1.75\""; circumference: 1350 }
                        ListElement { text: "20\" x 1.25\""; circumference: 1450 }
                        ListElement { text: "20\" x 1.35\""; circumference: 1460 }
                        ListElement { text: "20\" x 1.50\""; circumference: 1490 }
                        ListElement { text: "20\" x 1.75\""; circumference: 1515 }
                        ListElement { text: "20\" x 1.95\""; circumference: 1565 }
                        ListElement { text: "20\" x 1-1/8\""; circumference: 1545 }
                        ListElement { text: "20\" x 1-3/8\""; circumference: 1615 }
                        ListElement { text: "22\" x 1-3/8\""; circumference: 1770 }
                        ListElement { text: "22\" x 1-1/2\""; circumference: 1785 }
                        ListElement { text: "24\" x 3/4\" Tubular"; circumference: 1785 }
                        ListElement { text: "24\" x 1\""; circumference: 1753 }
                        ListElement { text: "24\" x 1-1/8\""; circumference: 1795 }
                        ListElement { text: "24\" x 1-1/4\""; circumference: 1905 }
                        ListElement { text: "24\" x 1.75\""; circumference: 1890 }
                        ListElement { text: "24\" x 2.00\""; circumference: 1925 }
                        ListElement { text: "24\" x 2.125\""; circumference: 1965 }
                        ListElement { text: "26\" x 7/8\" Tubular"; circumference: 1920 }
                        ListElement { text: "26\" x 1.25\""; circumference: 1950 }
                        ListElement { text: "26\" x 1.40\""; circumference: 2005 }
                        ListElement { text: "26\" x 1.50\""; circumference: 2010 }
                        ListElement { text: "26\" x 1.75\""; circumference: 2023 }
                        ListElement { text: "26\" x 1.95\""; circumference: 2050 }
                        ListElement { text: "26\" x 2.00\""; circumference: 2055 }
                        ListElement { text: "26\" x 2.10\""; circumference: 2068 }
                        ListElement { text: "26\" x 2.125\""; circumference: 2070 }
                        ListElement { text: "26\" x 2.35\""; circumference: 2083 }
                        ListElement { text: "26\" x 3.00\""; circumference: 2170 }
                        ListElement { text: "26\" x 1-1.0\""; circumference: 1913 }
                        ListElement { text: "26\" x 1\""; circumference: 1952 }
                        ListElement { text: "26\" x 1-1/8\""; circumference: 1970 }
                        ListElement { text: "26\" x 1-3/8\""; circumference: 2068 }
                        ListElement { text: "26\" x 1-1/2\""; circumference: 2100 }
                        ListElement { text: "27\" x 1\""; circumference: 2145 }
                        ListElement { text: "27\" x 1-1/8\""; circumference: 2155 }
                        ListElement { text: "27\" x 1-1/4\""; circumference: 2161 }
                        ListElement { text: "27\" x 1-3/8\""; circumference: 2169 }
                        ListElement { text: "27.5\" / 650B x 1.50\""; circumference: 2079 }
                        ListElement { text: "27.5\" / 650B x 1.95\""; circumference: 2090 }
                        ListElement { text: "27.5\" / 650B x 2.10\""; circumference: 2148 }
                        ListElement { text: "27.5\" / 650B x 2.25\""; circumference: 2182 }
                        ListElement { text: "27.5\" / 650B x 2.3\""; circumference: 2199 }
                        ListElement { text: "27.5\" / 650B x 2.35\""; circumference: 2207 }
                        ListElement { text: "27.5\" / 650B x 2.4\""; circumference: 2213 }
                        ListElement { text: "27.5\" / 650B x 2.5\""; circumference: 2231 }
                        ListElement { text: "27.5\" / 650B x 2.6\""; circumference: 2247 }
                        ListElement { text: "27.5\" / 650B x 2.8\""; circumference: 2279 }
                        ListElement { text: "29\" x 2.1\""; circumference: 2286 }
                        ListElement { text: "29\" x 2.2\""; circumference: 2302 }
                        ListElement { text: "29\" x 2.25\""; circumference: 2310 }
                        ListElement { text: "29\" x 2.3\""; circumference: 2326 }
                        ListElement { text: "29\" x 2.35\""; circumference: 2326 }
                        ListElement { text: "29\" x 2.4\""; circumference: 2333 }
                        ListElement { text: "29\" x 2.5\""; circumference: 2350 }
                        ListElement { text: "29\" x 2.6\""; circumference: 2366 }
                    }
                    onCurrentIndexChanged: {
                        if (currentIndex >= 0) {
                          selectedWheelSize = model.get(currentIndex).text
                          selectedCircumference = model.get(currentIndex).circumference
                          console.log("wheelSizeCombo changed");
                          settingsChanged()
                      }
                  }
                }

                // Restore Default Wheel Diameter Button
                UiButton {
                    text: qsTr("Restore Default Setting to the Trainer")
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    font.bold: true
                    background: Rectangle {
                        color: "#9C27B0"
                        // Modern look: the pill of the other buttons, the colour stays (a trainer action)
                        radius: window.ui.modern ? height / 2 : 4
                    }
                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: "white"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        // Emit signal to restore default wheel diameter in the trainer
                        restoreDefaultWheelDiameter()
                    }
                }
            }
        }

        UiGroupBox {
        title: qsTr("Preset Gear Profiles")
        Layout.fillWidth: true

            UiComboBox {
                id: profileCombo
                width: parent.width
                textRole: "text"
                displayText: currentIndex < 0 ? qsTr("Select a profile...") : model.get(currentIndex).text
                model: ListModel {
                 id: profileModel
                }

                Component.onCompleted: {
                 for (var key in gearProfiles) {
                     profileModel.append({
                         text: gearProfiles[key].name,
                         value: key
                     })
                 }
                }

                onCurrentIndexChanged: {
                 if (currentIndex >= 0) {
                     loadGearProfile(profileModel.get(currentIndex).value)
                 }
                }
                }
        }


        // Gear Table GroupBox
        UiGroupBox {
            title: qsTr("Virtual Gear Table")
            Layout.fillWidth: true
            // Modern look: the table is as tall as its rows and the page scrolls as one; a list
            // scrolling inside the scrolling page caught the finger half way down
            Layout.fillHeight: !window.ui.modern
            Layout.preferredHeight: window.ui.modern ? -1 : parent.height

            ColumnLayout {
                anchors.fill: window.ui.modern ? undefined : parent
                width: parent.width
                spacing: 10

                // Updated Buttons Row. Modern look: one button per line, three long labels
                // side by side were cut on a phone
                GridLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: window.ui.modern ? -1 : 40
                    columns: window.ui.modern ? 1 : 3
                    columnSpacing: 10
                    rowSpacing: window.ui.modern ? 8 : 10

                    UiButton {
                        text: qsTr("Add Gear")
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        onClicked: addNewGear()
                    }

                    UiButton {
                        text: qsTr("Clear Selected Gear and Following")
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        onClicked: {
                            if (gearTable.currentRow >= 0) {
                                clearGearsFromIndex(gearTable.currentRow)
                            }
                        }
                    }

                    UiButton {
                        text: qsTr("Reset All Gears")
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        onClicked: initializeGearRows()
                    }
                }

                // Table Header (same as before)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    color: window.ui.modern ? window.ui.surfaceHigh : "#f0f0f0"
                    border.width: window.ui.modern ? 0 : 1
                    border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                    radius: window.ui.modern ? 12 : 0

                    Row {
                        anchors.fill: parent

                        Rectangle {
                            width: parent.width / 3
                            height: parent.height
                            border.width: window.ui.modern ? 0 : 1
                            border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                            color: "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: qsTr("Gear")
                                font.bold: true
                                color: window.ui.modern ? window.ui.textMain : "black"
                            }
                        }

                        Rectangle {
                            width: parent.width / 3
                            height: parent.height
                            border.width: window.ui.modern ? 0 : 1
                            border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                            color: "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: qsTr("Chainring")
                                font.bold: true
                                color: window.ui.modern ? window.ui.textMain : "black"
                            }
                        }

                        Rectangle {
                            width: parent.width / 3
                            height: parent.height
                            border.width: window.ui.modern ? 0 : 1
                            border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                            color: "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: qsTr("Rear Cog")
                                font.bold: true
                                color: window.ui.modern ? window.ui.textMain : "black"
                            }
                        }
                    }
                }

                // Table Content
                ListView {
                    id: gearTable
                    Layout.fillWidth: true
                    Layout.fillHeight: !window.ui.modern
                    Layout.preferredHeight: window.ui.modern ? contentHeight : -1
                    // The page margins are not in the implicit height: never squeeze the rows
                    Layout.minimumHeight: window.ui.modern ? contentHeight : 0
                    interactive: !window.ui.modern
                    clip: true
                    // Modern look: rounded rows apart from each other
                    spacing: window.ui.modern ? 4 : 0
                    property int currentRow: -1
                    model: ListModel {
                        id: gearListModel
                    }

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AlwaysOff
                    }


                    Component.onCompleted: {
                        updateGearListModel()
                    }

                    function updateGearListModel() {
                        gearListModel.clear()
                        for (var i = 0; i < gearRows.length; i++) {
                            if (gearRows[i].active) {
                                gearListModel.append(gearRows[i])
                            }
                        }
                    }

                    delegate: Rectangle {
                        width: gearTable.width
                        height: window.ui.modern ? 48 : 40
                        radius: window.ui.modern ? 12 : 0
                        color: window.ui.modern ? (gearTable.currentRow === index ? window.ui.alpha(window.ui.accent, 0.14) : window.ui.surface) : (gearTable.currentRow === index ? "#e0e0e0" : "white")

                        MouseArea {
                            anchors.fill: parent
                            onClicked: gearTable.currentRow = index
                        }

                        Row {
                            anchors.fill: parent

                            // Gear Number (non-editable)
                            Rectangle {
                                width: parent.width / 3
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

                            // Crankset (editable)
                            Rectangle {
                                width: parent.width / 3
                                height: parent.height
                                border.width: window.ui.modern ? 0 : 1
                                border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                                color: "transparent"

                                SpinBox {
                                    id: cranksetSpinBox
                                    anchors.centerIn: parent
                                    width: parent.width * 0.8
                                    height: window.ui.modern ? 36 : 30
                                    // Modern look: no Material paddings and insets, they differ above and below
                                    // and the number sat high in the low field
                                    topPadding: window.ui.modern ? 0 : undefined
                                    bottomPadding: window.ui.modern ? 0 : undefined
                                    topInset: window.ui.modern ? 0 : undefined
                                    bottomInset: window.ui.modern ? 0 : undefined
                                    from: 1
                                    to: 999
                                    value: crankset
                                    onValueModified: {
                                        gearRows[index].crankset = value
                                        gearConfigurationChanged(gearRows)
                                    }

                                    // Style the SpinBox
                                    contentItem: TextInput {
                                        z: 2
                                        text: cranksetSpinBox.textFromValue(cranksetSpinBox.value, cranksetSpinBox.locale)
                                        font: cranksetSpinBox.font
                                        color: window.ui.modern ? window.ui.textMain : "black"
                                        selectionColor: window.ui.modern ? window.ui.accent : "#21be2b"
                                        selectedTextColor: window.ui.modern ? window.ui.accentInk : "#ffffff"
                                        horizontalAlignment: Qt.AlignHCenter
                                        verticalAlignment: Qt.AlignVCenter
                                    }

                                    up.indicator: Rectangle {
                                        x: parent.width - width
                                        height: parent.height
                                        width: height
                                        color: window.ui.modern ? (parent.up.pressed ? window.ui.surfaceHigh : window.ui.surfaceHighest) : (parent.up.pressed ? "#e4e4e4" : "#f6f6f6")
                                        border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                                        border.width: window.ui.modern ? 0 : 1
                                        radius: window.ui.modern ? 8 : 0

                                        Text {
                                            visible: !window.ui.modern
                                            text: "+"
                                            color: window.ui.modern ? window.ui.textMain : "black"
                                            anchors.centerIn: parent
                                            font.pixelSize: window.ui.modern ? 18 : 12
                                        }
                                        // Modern look: drawn, the glyph sat off the centre of the button
                                        Rectangle {
                                            visible: window.ui.modern
                                            anchors.centerIn: parent
                                            width: 12; height: 2; radius: 1
                                            color: window.ui.textMain
                                        }
                                        Rectangle {
                                            visible: window.ui.modern
                                            anchors.centerIn: parent
                                            width: 2; height: 12; radius: 1
                                            color: window.ui.textMain
                                        }
                                    }

                                    down.indicator: Rectangle {
                                        x: 0
                                        height: parent.height
                                        width: height
                                        color: window.ui.modern ? (parent.down.pressed ? window.ui.surfaceHigh : window.ui.surfaceHighest) : (parent.down.pressed ? "#e4e4e4" : "#f6f6f6")
                                        border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                                        border.width: window.ui.modern ? 0 : 1
                                        radius: window.ui.modern ? 8 : 0

                                        Text {
                                            visible: !window.ui.modern
                                            text: "-"
                                            color: window.ui.modern ? window.ui.textMain : "black"
                                            anchors.centerIn: parent
                                            font.pixelSize: window.ui.modern ? 18 : 12
                                        }
                                        // Modern look: drawn, the glyph sat off the centre of the button
                                        Rectangle {
                                            visible: window.ui.modern
                                            anchors.centerIn: parent
                                            width: 12; height: 2; radius: 1
                                            color: window.ui.textMain
                                        }
                                    }

                                    background: Rectangle {
                                        color: window.ui.modern ? window.ui.surfaceHighest : "white"
                                        border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                                        border.width: window.ui.modern ? 0 : 1
                                        radius: window.ui.modern ? 8 : 0
                                    }
                                }
                            }

                            // Rear Cog (editable)
                            Rectangle {
                                width: parent.width / 3
                                height: parent.height
                                border.width: window.ui.modern ? 0 : 1
                                border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                                color: "transparent"

                                SpinBox {
                                    id: cogSpinBox
                                    anchors.centerIn: parent
                                    width: parent.width * 0.8
                                    height: window.ui.modern ? 36 : 30
                                    // Modern look: no Material paddings and insets, they differ above and below
                                    // and the number sat high in the low field
                                    topPadding: window.ui.modern ? 0 : undefined
                                    bottomPadding: window.ui.modern ? 0 : undefined
                                    topInset: window.ui.modern ? 0 : undefined
                                    bottomInset: window.ui.modern ? 0 : undefined
                                    from: 1
                                    to: 999
                                    value: cog
                                    onValueModified: {
                                        gearRows[index].cog = value
                                        gearConfigurationChanged(gearRows)
                                    }

                                    // Style the SpinBox (same as cranksetSpinBox)
                                    contentItem: TextInput {
                                        z: 2
                                        text: cogSpinBox.textFromValue(cogSpinBox.value, cogSpinBox.locale)
                                        font: cogSpinBox.font
                                        color: window.ui.modern ? window.ui.textMain : "black"
                                        selectionColor: window.ui.modern ? window.ui.accent : "#21be2b"
                                        selectedTextColor: window.ui.modern ? window.ui.accentInk : "#ffffff"
                                        horizontalAlignment: Qt.AlignHCenter
                                        verticalAlignment: Qt.AlignVCenter
                                    }

                                    up.indicator: Rectangle {
                                        x: parent.width - width
                                        height: parent.height
                                        width: height
                                        color: window.ui.modern ? (parent.up.pressed ? window.ui.surfaceHigh : window.ui.surfaceHighest) : (parent.up.pressed ? "#e4e4e4" : "#f6f6f6")
                                        border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                                        border.width: window.ui.modern ? 0 : 1
                                        radius: window.ui.modern ? 8 : 0

                                        Text {
                                            visible: !window.ui.modern
                                            text: "+"
                                            color: window.ui.modern ? window.ui.textMain : "black"
                                            anchors.centerIn: parent
                                            font.pixelSize: window.ui.modern ? 18 : 12
                                        }
                                        // Modern look: drawn, the glyph sat off the centre of the button
                                        Rectangle {
                                            visible: window.ui.modern
                                            anchors.centerIn: parent
                                            width: 12; height: 2; radius: 1
                                            color: window.ui.textMain
                                        }
                                        Rectangle {
                                            visible: window.ui.modern
                                            anchors.centerIn: parent
                                            width: 2; height: 12; radius: 1
                                            color: window.ui.textMain
                                        }
                                    }

                                    down.indicator: Rectangle {
                                        x: 0
                                        height: parent.height
                                        width: height
                                        color: window.ui.modern ? (parent.down.pressed ? window.ui.surfaceHigh : window.ui.surfaceHighest) : (parent.down.pressed ? "#e4e4e4" : "#f6f6f6")
                                        border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                                        border.width: window.ui.modern ? 0 : 1
                                        radius: window.ui.modern ? 8 : 0

                                        Text {
                                            visible: !window.ui.modern
                                            text: "-"
                                            color: window.ui.modern ? window.ui.textMain : "black"
                                            anchors.centerIn: parent
                                            font.pixelSize: window.ui.modern ? 18 : 12
                                        }
                                        // Modern look: drawn, the glyph sat off the centre of the button
                                        Rectangle {
                                            visible: window.ui.modern
                                            anchors.centerIn: parent
                                            width: 12; height: 2; radius: 1
                                            color: window.ui.textMain
                                        }
                                    }

                                    background: Rectangle {
                                        color: window.ui.modern ? window.ui.surfaceHighest : "white"
                                        border.color: window.ui.modern ? window.ui.alpha(window.ui.outline, 0.4) : "#cccccc"
                                        border.width: window.ui.modern ? 0 : 1
                                        radius: window.ui.modern ? 8 : 0
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
