import QtQuick 2.12
import QtQuick.Controls 2.5
import QtQuick.Controls.Material 2.12
import QtQuick.Dialogs 1.0
import QtGraphicalEffects 1.12
import Qt.labs.settings 1.0
import QtMultimedia 5.15
import org.cagnulein.qdomyoszwift 1.0
import QtQuick.Window 2.12
import Qt.labs.platform 1.1
import AndroidStatusBar 1.0

ApplicationWindow {
    id: window
    width: 640
    height: 480
    visibility: Qt.WindowFullScreen
    visible: true
	 objectName: "stack"
    title: Qt.platform.os === "ios" ? "" : qsTr("qDomyos-Zwift")

    // Force update on orientation change
    property int currentOrientation: Screen.orientation
    onCurrentOrientationChanged: {
        if (Qt.platform.os === "android") {
            console.log("Orientation changed to:", currentOrientation)
            // Force property binding updates by accessing the properties
            var temp = AndroidStatusBar.height + AndroidStatusBar.navigationBarHeight + AndroidStatusBar.leftInset + AndroidStatusBar.rightInset
        }
    }
    
    // Helper functions for cleaner padding calculations
    function getTopPadding() {
        // Add padding for iPadOS multi-window mode (Stage Manager, Split View, Slide Over)
        // to avoid overlap with window control buttons (red/yellow/green)
        // Check both the native detection and window size comparison for reactivity
        if (Qt.platform.os === "ios") {
            var isMultiWindow = (typeof rootItem !== "undefined" && rootItem && rootItem.iPadMultiWindowMode) ||
                                (window.width < Screen.width - 10);  // Window smaller than screen = multi-window
            if (isMultiWindow) {
                return 15;  // Space for window control buttons
            }
        }
        if (Qt.platform.os !== "android" || AndroidStatusBar.apiLevel < 31) return 0;
        // AndroidStatusBar.height is always the top inset in the current orientation
        // (getSystemWindowInsets() returns orientation-aware values)
        return AndroidStatusBar.height;
    }

    function getBottomPadding() {
        if (Qt.platform.os !== "android" || AndroidStatusBar.apiLevel < 31) return 0;
        // navigationBarHeight is always the bottom inset in the current orientation
        return AndroidStatusBar.navigationBarHeight;
    }

    function getLeftPadding() {
        if (Qt.platform.os !== "android" || AndroidStatusBar.apiLevel < 31) return 0;
        return (Screen.orientation === Qt.LandscapeOrientation || Screen.orientation === Qt.InvertedLandscapeOrientation) ?
               (settings.android_landscape_cutout_margin ? AndroidStatusBar.leftInset : AndroidStatusBar.systemBarLeftInset) : 0;
    }

    function getRightPadding() {
        if (Qt.platform.os !== "android" || AndroidStatusBar.apiLevel < 31) return 0;
        return (Screen.orientation === Qt.LandscapeOrientation || Screen.orientation === Qt.InvertedLandscapeOrientation) ?
               (settings.android_landscape_cutout_margin ? AndroidStatusBar.rightInset : AndroidStatusBar.systemBarRightInset) : 0;
    }

    // Side margin for text, after the Material 3 window margins (16 on compact windows
    // under 600 wide, 24 on wider ones) but tighter: 12 and 16. Keeps text clear of
    // rounded screen corners and of the edges covered by protective glass.
    // A property rather than a function, so .ui.qml forms can bind to it.
    readonly property int contentSideMargin: width < 600 ? 12 : 16

    function isConfiguringShortcuts() {
        // Check if a TextField in the shortcuts settings has active focus
        // This prevents global shortcuts from intercepting key presses when configuring them
        var focusItem = window.activeFocusItem;
        if (!focusItem) return false;

        // Walk up the parent hierarchy to check if we're inside settingsShortcutsPane
        var current = focusItem;
        while (current) {
            if (current.objectName === "settingsShortcutsPane") {
                return true;
            }
            current = current.parent;
        }
        return false;
    }

    function shortcutReady(sequence) {
        return Qt.platform.os !== "ios" && settings.shortcuts_enabled && !isConfiguringShortcuts() && String(sequence).length > 0;
    }
    function stripBluetoothDeviceName(deviceName) {
        return deviceName.replace(/ \(\d+%\)$/, "")
    }

    function maybeOpenGymModePopup() {
        if (typeof rootItem === "undefined" || !rootItem) {
            return
        }
        if (settings.gym_mode && !rootItem.hasConnectedDevice() && !gymModePopupDismissed && !popupGymMode.visible) {
            popupGymMode.open()
        }
    }

    signal gpx_open_clicked(url name)
    signal gpxpreview_open_clicked(url name)
    signal profile_open_clicked(url name)
    signal trainprogram_open_clicked(url name)
    signal fitfile_preview_clicked(url name)
    signal trainprogram_open_other_folder(url name)
    signal gpx_open_other_folder(url name)
    signal trainprogram_preview(url name)
    signal trainprogram_zwo_loaded(string s)
    signal trainprogram_autostart_requested()
    signal fitfile_preview(string s)
    signal gpx_save_clicked()
    signal fit_save_clicked()
    signal refresh_bluetooth_devices_clicked()
    signal strava_connect_clicked()
    signal peloton_connect_clicked()
    signal intervalsicu_connect_clicked()
    signal intervalsicu_download_todays_workout_clicked()
    signal loadSettings(url name)
    signal saveSettings(url name)
    signal deleteSettings(url name)
    signal restoreSettings()
    signal saveProfile(string profilename)
    signal restart()
    signal volumeUp()
    signal volumeDown()
    signal keyMediaPrevious()
    signal keyMediaNext()
    signal floatingOpen()
    signal openFloatingWindowBrowser();
    signal strava_upload_file_prepare();

    property bool lockTiles: false
    property bool settings_restart_to_apply: false
    property bool gymModePopupDismissed: false

    Settings {
        id: settings
        property string profile_name: "default"        
        property string theme_status_bar_background_color: "#800080"
        property bool volume_change_gears: false
        property string peloton_username: "username"
        property string peloton_password: "password"

        property bool gym_mode: false

        property bool shortcuts_enabled: false
        property string shortcut_speed_plus: ""
        property string shortcut_speed_minus: ""
        property string shortcut_inclination_plus: ""
        property string shortcut_inclination_minus: ""
        property string shortcut_resistance_plus: ""
        property string shortcut_resistance_minus: ""
        property string shortcut_peloton_resistance_plus: ""
        property string shortcut_peloton_resistance_minus: ""
        property string shortcut_target_resistance_plus: ""
        property string shortcut_target_resistance_minus: ""
        property string shortcut_target_power_plus: ""
        property string shortcut_target_power_minus: ""
        property string shortcut_target_zone_plus: ""
        property string shortcut_target_zone_minus: ""
        property string shortcut_target_speed_plus: ""
        property string shortcut_target_speed_minus: ""
        property string shortcut_target_incline_plus: ""
        property string shortcut_target_incline_minus: ""
        property string shortcut_fan_plus: ""
        property string shortcut_fan_minus: ""
        property string shortcut_peloton_offset_plus: ""
        property string shortcut_peloton_offset_minus: ""
        property string shortcut_peloton_remaining_plus: ""
        property string shortcut_peloton_remaining_minus: ""
        property string shortcut_remaining_time_plus: ""
        property string shortcut_remaining_time_minus: ""
        property string shortcut_gears_plus: ""
        property string shortcut_gears_minus: ""
        property string shortcut_pid_hr_plus: ""
        property string shortcut_pid_hr_minus: ""
        property string shortcut_ext_incline_plus: ""
        property string shortcut_ext_incline_minus: ""
        property string shortcut_biggears_plus: ""
        property string shortcut_biggears_minus: ""
        property string shortcut_avs_cruise: ""
        property string shortcut_avs_climb: ""
        property string shortcut_avs_sprint: ""
        property string shortcut_power_avg: ""
        property string shortcut_erg_mode: ""
        property string shortcut_preset_resistance_1: ""
        property string shortcut_preset_resistance_2: ""
        property string shortcut_preset_resistance_3: ""
        property string shortcut_preset_resistance_4: ""
        property string shortcut_preset_resistance_5: ""
        property string shortcut_preset_speed_1: ""
        property string shortcut_preset_speed_2: ""
        property string shortcut_preset_speed_3: ""
        property string shortcut_preset_speed_4: ""
        property string shortcut_preset_speed_5: ""
        property string shortcut_preset_inclination_1: ""
        property string shortcut_preset_inclination_2: ""
        property string shortcut_preset_inclination_3: ""
        property string shortcut_preset_inclination_4: ""
        property string shortcut_preset_inclination_5: ""
        property string shortcut_preset_powerzone_1: ""
        property string shortcut_preset_powerzone_2: ""
        property string shortcut_preset_powerzone_3: ""
        property string shortcut_preset_powerzone_4: ""
        property string shortcut_preset_powerzone_5: ""
        property string shortcut_preset_powerzone_6: ""
        property string shortcut_preset_powerzone_7: ""
        property string shortcut_auto_resistance: ""
        property string shortcut_lap: ""
        property string shortcut_start_stop: ""
        property string shortcut_stop: ""
        property bool android_landscape_cutout_margin: true
        property bool ui_modern: true
        property string ui_theme: "graphite"
        property string ui_accent: "violet"
        property string ui_theme_mode: "auto"
    }

    // Modern look (fork only), switched in Settings > General Options. Pages read the palette
    // through window.ui; with ui.modern off every page keeps its classic look.
    readonly property QtObject ui: QtObject {
        readonly property bool modern: settings.ui_modern

        // Appearance: "auto" follows the night mode of the phone, "dark" and "light" are fixed.
        // The classic look is always dark.
        readonly property string themeMode: settings.ui_theme_mode
        property bool systemDark: AndroidStatusBar.systemDarkMode()
        readonly property bool dark: !modern || themeMode === "dark" || (themeMode !== "light" && systemDark)
        function refreshSystemDark() { systemDark = AndroidStatusBar.systemDarkMode() }

        readonly property var themes: ({
            "graphite": { bg: "#111318", surface: "#1B1E24", surfaceHigh: "#23272E", surfaceHighest: "#2D323A",
                          outline: "#3B414B", textMain: "#E4E6EB", textMuted: "#A2A8B3" },
            "oled":     { bg: "#000000", surface: "#101215", surfaceHigh: "#181B1F", surfaceHighest: "#22262B",
                          outline: "#30353C", textMain: "#E6E7EA", textMuted: "#9CA2AC" },
            "midnight": { bg: "#0B1220", surface: "#131C2D", surfaceHigh: "#1B2639", surfaceHighest: "#243148",
                          outline: "#35445F", textMain: "#E3E9F4", textMuted: "#99A6BE" }
        })
        readonly property var accents: ({
            "violet": "#B69DF8", "blue": "#7AB8FF", "teal": "#4FD8C4",
            "green": "#7EDC8A", "orange": "#FFB36B", "pink": "#F7A1C4"
        })
        readonly property var lightThemes: ({
            "graphite": { bg: "#F4F5F7", surface: "#FFFFFF", surfaceHigh: "#ECEEF1", surfaceHighest: "#E1E4E8",
                          outline: "#C4C8CF", textMain: "#1A1C20", textMuted: "#5B616B" },
            "oled":     { bg: "#FFFFFF", surface: "#F3F4F6", surfaceHigh: "#E9EBEE", surfaceHighest: "#DDE0E4",
                          outline: "#C8CCD2", textMain: "#111214", textMuted: "#5A5F68" },
            "midnight": { bg: "#EEF2F9", surface: "#FFFFFF", surfaceHigh: "#E3E9F4", surfaceHighest: "#D6DFEE",
                          outline: "#B8C4D9", textMain: "#162033", textMuted: "#55627A" }
        })
        readonly property var lightAccents: ({
            "violet": "#6D4FC2", "blue": "#1E63C6", "teal": "#00796B",
            "green": "#2E7D32", "orange": "#C25400", "pink": "#B8326E"
        })
        readonly property var t: dark ? (themes[settings.ui_theme] || themes["graphite"])
                                      : (lightThemes[settings.ui_theme] || lightThemes["graphite"])
        readonly property var a: dark ? accents : lightAccents

        // Accent "system": the colour Android 12+ takes from the wallpaper (Material You), for
        // the dark and the light page. Empty elsewhere, then the choice is not offered and a
        // saved "system" falls back to violet. Read again on return to the foreground, since
        // the wallpaper is changed outside the app.
        property string systemAccentDark: AndroidStatusBar.systemAccentColor(true)
        property string systemAccentLight: AndroidStatusBar.systemAccentColor(false)
        readonly property bool systemAccentAvailable: systemAccentDark !== "" && systemAccentLight !== ""
        Component.onCompleted: console.log("QZ-THEME system accent dark '" + systemAccentDark
                                           + "' light '" + systemAccentLight + "'")
        function refreshSystemAccent() {
            systemAccentDark = AndroidStatusBar.systemAccentColor(true)
            systemAccentLight = AndroidStatusBar.systemAccentColor(false)
        }
        function accentOf(name) {
            if (name === "system" && systemAccentAvailable)
                return dark ? systemAccentDark : systemAccentLight
            return a[name] || a["violet"]
        }

        readonly property color bg: t.bg
        readonly property color surface: t.surface
        readonly property color surfaceHigh: t.surfaceHigh
        readonly property color surfaceHighest: t.surfaceHighest
        readonly property color outline: t.outline
        readonly property color textMain: t.textMain
        readonly property color textMuted: t.textMuted
        readonly property color accent: accentOf(settings.ui_accent)
        readonly property color accentInk: dark ? "#12101A" : "#FFFFFF"
        readonly property color danger: dark ? "#FF8A80" : "#C62828"
        readonly property color ok: dark ? "#7EDC8A" : "#2E7D32"
        readonly property int radius: 16

        readonly property string themeName: settings.ui_theme
        readonly property string accentName: settings.ui_accent

        function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
        // The settings page has its own Settings object, which the window's does not hear
        // about until a restart: it writes through here, so the look changes at once
        function setOption(key, value) { settings[key] = value }
        // Text that the classic look paints in a fixed colour (mostly white) on the page
        // background: the theme text colour in the modern look, the old colour otherwise
        function ink(classic) { return modern ? textMain : classic }
        // Zone colours of the tiles are made for a dark page: darker ones on a light page
        function zoneInk(c) { return dark ? c : Qt.darker(c, 1.7) }

        // Theme of the web pages in a WebView (workout editor, charts): their inline script
        // qzApplyTheme() maps these onto CSS variables. Null in the classic look, so the pages
        // keep their own palette. All tokens are opaque: toString() gives "#rrggbb", which CSS
        // reads; a translucent one would come out as "#aarrggbb", which CSS misreads.
        readonly property var webTheme: !modern ? null : ({
            modern: "1",
            dark: dark,
            bg: bg.toString(),
            surface: surface.toString(),
            surfaceHigh: surfaceHigh.toString(),
            surfaceHighest: surfaceHighest.toString(),
            outline: outline.toString(),
            text: textMain.toString(),
            muted: textMuted.toString(),
            accent: accent.toString(),
            accentInk: accentInk.toString(),
            danger: danger.toString()
        })
        // The theme as a URL fragment for the first load of such a page ("" in the classic look)
        function webThemeFragment() {
            if (!webTheme)
                return ""
            var parts = []
            for (var key in webTheme) {
                var value = key === "dark" ? (webTheme.dark ? "1" : "0") : webTheme[key]
                parts.push(key + "=" + encodeURIComponent(value))
            }
            return "#" + parts.join("&")
        }
        // Script that applies the current theme to an open page, for WebView.runJavaScript()
        function webThemeScript() {
            return "window.qzApplyTheme && window.qzApplyTheme(" + JSON.stringify(webTheme) + ")"
        }
    }

    Material.theme: ui.dark ? Material.Dark : Material.Light
    Material.accent: ui.modern ? ui.accent : Material.color(Material.Pink, Material.Shade200)
    Material.background: ui.modern ? ui.bg : undefined

    // The phone can switch its night mode while the app runs (by schedule or from the quick
    // settings). Qt 5.15 passes no such event on to QML, so ask again on return to the
    // foreground and every 2 s while the app is on screen (three light JNI calls)
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive) {
                window.ui.refreshSystemDark()
                window.ui.refreshSystemAccent()
            }
        }
    }
    Timer {
        interval: 2000
        repeat: true
        running: window.ui.modern && window.ui.themeMode === "auto"
                 && Qt.application.state === Qt.ApplicationActive
        onTriggered: window.ui.refreshSystemDark()
    }


    Store {
        id: iapStore
    }

    Loader {
      id: googleMapUI
      source:"GoogleMap.qml";
      active: false
      onLoaded: { console.log("googleMapUI loaded"); stackView.push(googleMapUI.item); }
    }

    // here in order to cache everything for the SwagBagView
    Product {
        id: productUnlockVowels
        type: Product.Unlockable
        store: iapStore
        identifier: "org.cagnulein.qdomyoszwift.swagbag"

        onPurchaseSucceeded: {
            console.log(identifier + " purchase successful");
            applicationData.vowelsUnlocked = true;
            transaction.finalize();
            pageStack.pop();
        }

        onPurchaseFailed: {
            console.log(identifier + " purchase failed");
            console.log("reason: "
                        + transaction.failureReason === Transaction.CanceledByUser ? "Canceled" : transaction.errorString);
            transaction.finalize();
        }

        onPurchaseRestored: {
            console.log(identifier + " purchase restored");
            applicationData.vowelsUnlocked = true;
            console.log("timestamp: " + transaction.timestamp);
            transaction.finalize();
            pageStack.pop();
        }
    }

    ToastManager {
        id: toast
    }

    property bool lapPromptVisible: false
    property string lapPromptText: ""

    function isLapPromptMessage(message) {
        var lowerMessage = message.toLowerCase()
        return (lowerMessage.indexOf("press") >= 0 && lowerMessage.indexOf("lap") >= 0) ||
               (lowerMessage.indexOf("lap") >= 0 && lowerMessage.indexOf("continue") >= 0 &&
                lowerMessage.indexOf("received") < 0)
    }

    Rectangle {
        id: lapPromptOverlay
        z: Infinity
        visible: window.lapPromptVisible
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 520)
        height: Math.max(96, lapPromptLabel.implicitHeight + 44)
        radius: 8
        color: "#9C27B0"
        border.color: "white"
        border.width: 3
        opacity: visible ? 1 : 0

        Label {
            id: lapPromptLabel
            anchors.fill: parent
            anchors.margins: 16
            text: window.lapPromptText
            color: "white"
            font.bold: true
            font.pixelSize: 26
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
        }

        SequentialAnimation on scale {
            running: lapPromptOverlay.visible
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 1.05; duration: 450; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 1.05; to: 1.0; duration: 450; easing.type: Easing.InOutQuad }
        }
    }

    Timer {
        id: lapPromptAutoClose
        interval: 15000
        repeat: false
        onTriggered: window.lapPromptVisible = false
    }

    Timer {
        interval: 1
        repeat: false
        running: (rootItem.toastRequested !== "")
        onTriggered: {
            if (window.isLapPromptMessage(rootItem.toastRequested)) {
                window.lapPromptText = rootItem.toastRequested;
                window.lapPromptVisible = true;
                lapPromptAutoClose.restart();
            } else {
                toast.show(rootItem.toastRequested);
            }
            rootItem.toastRequested = "";
        }
    }

    Timer {
       id: gymModeStartupTimer
       interval: 1500
       running: true
       repeat: true
       onTriggered: {
            if (typeof rootItem === "undefined" || !rootItem) {
                return
            }
            maybeOpenGymModePopup()
            if (popupGymMode.visible || rootItem.hasConnectedDevice() || gymModePopupDismissed || !settings.gym_mode) {
                stop()
            }
        }
    }

    /*
    Timer {
        interval: 1000
        repeat: true
        running: true
        property int i: 0
        onTriggered: {
            toast.show("This timer has triggered " + (++i) + " times!");
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: true
        property int i: 0
        onTriggered: {
            toast.show("This important message has been shown " + (++i) + " times.", 5000);
        }
    }*/

    // Shared by the toolbar "◄" button and the Android back button.
    // stepInsidePage: pages with their own inner navigation (Wizard, training programs
    // list) first go back one step there, via their handleBack().
    // Returns false when there is nothing to go back to (home page).
    function navigateBack(stepInsidePage) {
        if (stepInsidePage && stackView.currentItem && typeof stackView.currentItem.handleBack === "function" &&
                stackView.currentItem.handleBack()) {
            return true
        }
        if (stackView.depth <= 1) {
            return false
        }

        var remindToSaveProfile = headerToolbar.settingsPageActive &&
                stackView.currentItem &&
                typeof stackView.currentItem.profileSaveReminderNeeded === "function" &&
                stackView.currentItem.profileSaveReminderNeeded()
        var activeProfileName = settings.profile_name

        if(window.settings_restart_to_apply === true) {
            window.settings_restart_to_apply = false;
            popupRestartApp.visible = true;
        }

        stackView.pop()
        // Modern look: back from a page opened out of the settings (Tiles Options...) the
        // settings keep their load and save buttons; hidden, they left a gap next to search
        var backOnSettings = window.ui.modern && stackView.depth > 1 && headerToolbar.settingsPageActive
        toolButtonLoadSettings.visible = backOnSettings;
        toolButtonSaveSettings.visible = backOnSettings;
        rootItem.sortTiles()
        if (remindToSaveProfile) {
            toast.show(qsTr("Remember to save profile \"%1\" if you want to keep these changes in this profile.").arg(activeProfileName))
        }
        return true
    }

    // On Android an unhandled back key closes the window, which quits the app.
    // (Keys.onBackPressed cannot be attached to ApplicationWindow: it is not an Item.)
    // Popups and the drawer close themselves on back before this is reached.
    // Android 16+ with targetSdk 36 no longer sends the back key to the app unless
    // AndroidManifest.xml sets android:enableOnBackInvokedCallback="false".
    onClosing: {
        if (OS_VERSION !== "Android") {
            return
        }
        if (navigateBack(true)) {
            close.accepted = false
            return
        }
        if (backToExitTimer.running) {
            return  // second press within the interval: let the app close
        }
        close.accepted = false
        backToExitTimer.start()
        toast.show(qsTr("Press back again to exit"), backToExitTimer.interval)
    }

    Timer {
        id: backToExitTimer
        repeat: false
        interval: 2000 // ms
    }

    UiNotice {
        id: popup
        text: qsTr("Program has been loaded correctly. Press start to begin!")
    }

    UiMessageDialog {
           id: popupPelotonAuth
           text: qsTr("Peloton Authentication Change")
           informativeText: qsTr("Peloton has moved to a new authentication system. Username and password are no longer required.\n\nWould you like to switch to the new authentication method now?")
           buttons: (MessageDialog.Yes | MessageDialog.No)
           onYesClicked: {
               settings.peloton_username = "username"
               settings.peloton_password = "password"
               stackView.push("WebPelotonAuth.qml")
               peloton_connect_clicked()
           }
           onNoClicked: this.visible = false
           visible: false
       }

    Timer {
       id: pelotonAuthCheck
       interval: 1000  // 1 second delay after startup
       running: true
       repeat: false
       onTriggered: {
           if (settings.peloton_password !== "password") {
               popupPelotonAuth.visible = true
           }
       }
    }

    UiPopup {
        id: popupClassificaHelper
         parent: Overlay.overlay

       x: Math.round((parent.width - width) / 2)
         y: Math.round((parent.height - height) / 2)
         width: 380
         height: 130
         modal: true
         focus: true
         palette.text: "white"
         onClosed: stackView.push("Classifica.qml");
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
             text: qsTr("QZ Classifica is a realtime viewer about the actual\neffort of every QZ users! If you want to join in,\nchoose a nickname in the general settings\nand enable the QZ Classifica setting in the\nexperimental settings section and\nrestart the app.")
            }
         }
    }

    UiPopup {
        id: popupGymMode
        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Math.min(parent.width - 30, 720)
        height: Math.min(parent.height - 40, 260)
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose
        onOpened: refresh_bluetooth_devices_clicked()

        Column {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            Label {
                width: parent.width
                text: qsTr("Select Your Gym Device")
                font.pixelSize: Qt.application.font.pixelSize + 10
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Label {
                width: parent.width
                text: qsTr("QZ found the nearby Bluetooth trainers. Choose the machine you want to use for this session.")
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            ValueComboBox {
                id: gymModeDeviceComboBox
                width: parent.width
                model: rootItem.bluetoothDevices
                labels: ({ "Disabled": qsTr("Disabled") })
                displayText: currentIndex >= 0 ? labelFor(currentValue) : qsTr("Select a device")
                currentIndex: -1
                font.pixelSize: Qt.application.font.pixelSize + 8

                onActivated: {
                    var selectedDevice = stripBluetoothDeviceName(currentValue)
                    if (selectedDevice === "Disabled" || selectedDevice === "Wifi" || selectedDevice.length === 0) {
                        return
                    }
                    popupGymMode.close()
                    rootItem.selectGymModeDevice(selectedDevice)
                }
            }

            Label {
                width: parent.width
                text: qsTr("The list refreshes automatically every 10 seconds.")
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                color: Material.color(Material.Grey)
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Skip")
                onClicked: {
                    gymModePopupDismissed = true
                    popupGymMode.close()
                }
            }
        }
    }

    Timer {
        id: gymModeRefreshTimer
        interval: 10000
        repeat: true
        running: popupGymMode.visible
        onTriggered: refresh_bluetooth_devices_clicked()
    }

    UiPopup {
        id: popupWhatsOnZwiftHelper
         parent: Overlay.overlay

       x: Math.round((parent.width - width) / 2)
         y: Math.round((parent.height - height) / 2)
         width: 380
         height: 130
         modal: true
         focus: true
         palette.text: "white"
         closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
         onClosed: {
             stackView.push("WebEngineTest.qml")
             drawer.close()
             stackView.currentItem.trainprogram_zwo_loaded.connect(trainprogram_zwo_loaded)
             stackView.currentItem.trainprogram_zwo_loaded.connect(function(s) {
                 stackView.pop();
              });
         }

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
             text: qsTr("Browse the What's on Zwift workout library<br>and choose your workout. It will<br> be automatically loaded on QZ when you will<br>press the load button on the top!<br><br>QZ is not affiliated with Zwift<br>or https://whatsonzwift.com/ website.")
            }
         }
    }

    UiNotice {
        id: popupLoadSettings
        text: qsTr("Settings has been loaded correctly. Restart the app!")
    }

    UiNotice {
        id: popupSaveFile
        text: qsTr("Saved! Check your private folder (Android)<br>or Files App (iOS)")
    }

    UiPopup {
        id: popupStravaConnected
         parent: Overlay.overlay
         enabled: rootItem.generalPopupVisible
         onEnabledChanged: { if(rootItem.generalPopupVisible) popupStravaConnected.open() }
         onClosed: { rootItem.generalPopupVisible = false; }

         x: Math.round((parent.width - width) / 2)
         y: Math.round((parent.height - height) / 2)
         width: 380
         height: 120
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
             width: 370
             height: 120
             text: qsTr("Your Strava account is now connected!<br><br>When you will save a FIT file it will<br>automatically uploaded to Strava!")
            }
         }
    }

    UiPopup {
        id: popupPelotonConnected
         parent: Overlay.overlay
         enabled: rootItem.pelotonPopupVisible
         onEnabledChanged: { if(rootItem.pelotonPopupVisible) popupPelotonConnected.open() }
         onClosed: { rootItem.pelotonPopupVisible = false; }

         x: Math.round((parent.width - width) / 2)
         y: Math.round((parent.height - height) / 2)
         width: 380
         height: 120
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
             width: 370
             height: 120
             text: qsTr("Your Peloton account is now connected!<br><br>Restart the app to apply this change!")
            }
         }
    }

    Timer {
        id: popupLicenseAutoClose
        interval: 120000; running: rootItem.licensePopupVisible; repeat: false
        onTriggered: popupLicense.close();
    }

    UiPopup {
        id: popupLicense
         parent: Overlay.overlay
         enabled: rootItem.licensePopupVisible
         onEnabledChanged: { if(rootItem.licensePopupVisible) popupLicense.open() }
         onClosed: { Qt.openUrlExternally("https://www.patreon.com/bePatron?u=45290147"); Qt.callLater(Qt.quit); }

         x: Math.round((parent.width - width) / 2)
         y: Math.round((parent.height - height) / 2)
         width: 580
         height: 230
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
             width: 570
             height: 220
             text: qsTr("Trial time expired!<br><br>Please join the QZ Patreon Membership to unlock the full license!<br>https://www.patreon.com/bePatron?u=45290147<br><br>Then add your patreon email in the email field in the general settings.<br>The App will now close.")
            }
         }
    }

    UiMessageDialog {
        id: popupRestartApp
        text: qsTr("Settings changed")
        informativeText: qsTr("In order to apply the changes you need to restart the app.\nDo you want to do it now?")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: Qt.callLater(Qt.quit)
        onNoClicked: this.visible = false;
        visible: false
    }

    // a device changed a setting on its own (auto-detection): the message says what QZ found and why it must restart
    UiMessageDialog {
        id: popupRestartAppDetected
        text: ""
        informativeText: qsTr("Restart now?")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: Qt.callLater(Qt.quit)
        onNoClicked: this.visible = false;
        visible: false
    }

    // an FS- device that reports bike data: ask, because some FitShow treadmills report it too
    UiMessageDialog {
        id: popupFitshowBikeQuestion
        text: qsTr("This FitShow device also reports bike data. Is it a bike?")
        informativeText: qsTr("Yes: QZ enables \"Fit Plus Bike\" and closes, open it again to connect to it as a bike.\nNo: QZ keeps it as a treadmill and won't ask again (a bike can still be set by hand: \"Fit Plus Bike\" in Fitplus Bike Options).")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: { rootItem.fitshowBikeAnswer(true); Qt.callLater(Qt.quit); }
        onNoClicked: { rootItem.fitshowBikeAnswer(false); this.visible = false; }
        visible: false
    }

    Connections {
        target: rootItem
        ignoreUnknownSignals: true
        function onRestartToApplyRequested(message) {
            popupRestartAppDetected.text = message;
            popupRestartAppDetected.visible = true;
        }
        function onFitshowBikeQuestionRequested() { popupFitshowBikeQuestion.visible = true; }
    }

    UiMessageDialog {
        text: qsTr("Strava")
        informativeText: qsTr("Do you want to upload the workout to Strava?")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: {strava_upload_file_prepare(); rootItem.stravaUploadRequested = false;}
        onNoClicked: {rootItem.stravaUploadRequested = false;}
        visible: rootItem.stravaUploadRequested
    }

    UiMessageDialog {
        text: qsTr("Garmin Workout Planned")
        informativeText: qsTr("Workout found:\n") + rootItem.garminWorkoutPromptName +
                         (rootItem.garminWorkoutPromptDate.length > 0 ? qsTr("\nDate: ") + rootItem.garminWorkoutPromptDate : "") +
                         qsTr("\n\nDo you want to start it now?")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: { rootItem.garmin_start_downloaded_workout(); }
        onNoClicked: { rootItem.garmin_dismiss_downloaded_workout_prompt(); }
        visible: rootItem.garminWorkoutPromptRequested
    }

    UiMessageDialog {
        text: qsTr("Garmin FTP Update")
        informativeText: rootItem.garminFtpPromptMessage
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: { rootItem.garmin_accept_ftp_update(); }
        onNoClicked: { rootItem.garmin_dismiss_ftp_update(); }
        visible: rootItem.garminFtpPromptRequested
    }

    UiMessageDialog {
        text: qsTr("Clipboard Workout")
        informativeText: qsTr("Workout found in clipboard:\n%1\n\nDo you want to open the workout preview?").arg(rootItem.clipboardWorkoutPromptName)
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: {
            var workoutUrl = rootItem.clipboard_workout_url()
            rootItem.clipboard_accept_workout_prompt()
            var page = CHARTJS
                    ? stackView.push("TrainingProgramsListJS.qml", { initialWorkoutUrl: workoutUrl })
                    : stackView.push("TrainingProgramsList.qml", { initialWorkoutUrl: workoutUrl })
            page.trainprogram_open_clicked.connect(trainprogram_open_clicked)
            page.trainprogram_open_other_folder.connect(trainprogram_open_other_folder)
            page.trainprogram_preview.connect(trainprogram_preview)
            if (page.trainprogram_autostart_requested) {
                page.trainprogram_autostart_requested.connect(trainprogram_autostart_requested)
            }
            page.trainprogram_open_clicked.connect(function(url) {
                stackView.pop();
            });
        }
        onNoClicked: { rootItem.clipboard_dismiss_workout_prompt(); }
        visible: rootItem.clipboardWorkoutPromptRequested
    }

    UiMessageDialog {
        text: qsTr("Clipboard Workout")
        informativeText: qsTr("The clipboard workout has ended.\n\nDo you want to delete the file?")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: rootItem.clipboard_delete_finished_workout()
        onNoClicked: rootItem.clipboard_keep_finished_workout()
        visible: rootItem.clipboardWorkoutDeletePromptRequested
    }

    UiMessageDialog {
        text: qsTr("Echelon Unlock")
        informativeText: qsTr("The bike has been unlocked and cadence is flowing.\n\nDo you want to switch to the classic Bluetooth bridge for this session?")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: { rootItem.echelon_switch_to_classic_bridge(); }
        onNoClicked: { rootItem.echelon_dismiss_bridge_switch_prompt(); }
        visible: rootItem.echelonBridgeSwitchPromptRequested
    }

    UiPopup {
        id: echelonEnablePopup
        parent: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose
        width: Math.min(window.width - 40, 460)
        height: Math.min(window.height - 60, 420)
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        visible: rootItem.echelonEnablePromptRequested

        background: Rectangle {
            radius: 8
            color: Material.background
            border.color: Material.accent
            border.width: 1
        }

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Label {
                width: parent.width
                text: qsTr("Echelon Locked Bike")
                font.bold: true
                font.pixelSize: 20
                wrapMode: Text.WordWrap
            }

            ScrollView {
                width: parent.width
                height: parent.height - buttonsRow.height - 52
                clip: true

                TextArea {
                    width: echelonEnablePopup.width - 56
                    readOnly: true
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    text:
                        qsTr("Your bike is locked by Echelon, but QZ can unlock it.\n\n") +
                        qsTr("Enable Virtual Echelon in the experimental settings and restart qz, then open the official Echelon app on a separate device and connect to the bike once.\n\n") +
                        qsTr("After initialization, return to QZ and everything will work normally.\n\n") +
                        qsTr("You have to repeat this for each session, would you like to enable the Virtual Echelon setting now for this?")
                }
            }

            Row {
                id: buttonsRow
                width: parent.width
                spacing: 12
                layoutDirection: Qt.RightToLeft

                Button {
                    text: qsTr("Yes")
                    onClicked: rootItem.echelon_enable_virtual_bridge()
                }

                Button {
                    text: qsTr("No")
                    onClicked: rootItem.echelon_dismiss_enable_prompt()
                }
            }
        }
    }

    UiMessageDialog {
        id: stravaLogoutConfirm
        text: qsTr("Strava")
        informativeText: qsTr("You are already connected to Strava. Do you want to log out?")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: { rootItem.strava_logout(); }
        onNoClicked: this.visible = false
        visible: false
    }

    UiMessageDialog {
        id: pelotonLogoutConfirm
        text: qsTr("Peloton")
        informativeText: qsTr("You are already connected to Peloton. Do you want to log out?")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: { rootItem.peloton_logout(); }
        onNoClicked: this.visible = false
        visible: false
    }

    UiMessageDialog {
        id: intervalsICULogoutConfirm
        text: qsTr("Intervals.icu")
        informativeText: qsTr("You are already connected to Intervals.icu. Do you want to log out?")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: { rootItem.intervalsicu_logout(); }
        onNoClicked: this.visible = false
        visible: false
    }

    header: ToolBar {
        contentHeight: toolButton.implicitHeight
        Material.primary: window.ui.modern ? window.ui.bg : settings.theme_status_bar_background_color
        Material.elevation: window.ui.modern ? 0 : 4
        id: headerToolbar
        property bool settingsPageActive: stackView.currentItem && typeof stackView.currentItem.showSettingsSearch === "function"
        // Modern look: load and save belong to the settings page itself. The pages opened from
        // it (the settings files of the load button among them) kept both, and load could open
        // the list again and again. The profiles keep them as the drawer opens them from home.
        // The classic look sets them where it always did
        onSettingsPageActiveChanged: {
            if (window.ui.modern) {
                var keep = settingsPageActive || (stackView.currentItem
                        && typeof stackView.currentItem.profile_open_clicked === "function")
                toolButtonLoadSettings.visible = keep
                toolButtonSaveSettings.visible = keep
            }
        }
        // Set by the tile grid in Home.qml. The toolbar collapses to the status bar inset
        // (topPadding) with an animation instead of disappearing at once
        property bool scrolledAway: false
        height: scrolledAway ? topPadding : implicitHeight
        clip: height < implicitHeight   // keeps the Material shadow when fully shown
        Behavior on height { NumberAnimation { id: headerHeightAnimation; duration: 150; easing.type: Easing.OutQuad } }
        // While the height animates the page moves under the finger; Home.qml ignores that movement
        property bool animating: headerHeightAnimation.running
        topPadding: getTopPadding()

        ToolButton {
            id: toolButton
            icon.source: window.ui.modern ? "" : "icons/icons/icon.png"
            text: window.ui.modern ? "" : (stackView.depth > 1 ? "◄" : "◄")
            UiIcon { anchors.centerIn: parent; width: 24; height: 24; name: stackView.depth > 1 ? "arrow_back" : "menu"; color: window.ui.textMain; visible: window.ui.modern }
            font.pixelSize: Qt.application.font.pixelSize * 1.6
            onClicked: {
                if (stackView.depth > 1) {
                    navigateBack(false)
                } else {
                    drawer.open()
                }
            }
        }

        ToolButton {
            id: toolButtonFloating
            icon.source: window.ui.modern ? "" : "icons/icons/mini-display.png"
            UiIcon { anchors.centerIn: parent; width: 24; height: 24; name: "picture_in_picture_alt"; color: window.ui.textMain; visible: window.ui.modern }
            onClicked: { console.log("floating!"); floatingOpen(); }
            anchors.left: toolButton.right
            visible: OS_VERSION === "Android" ? true : false
        }

        UiNotice {
            id: popupAutoResistance
            text: rootItem.autoResistance ? qsTr("Auto Resistance enabled") : qsTr("Auto Resistance disabled")
        }

        Timer {
            id: popupAutoResistanceAutoClose
            interval: 2000; running: false; repeat: false
            onTriggered: popupAutoResistance.close();
        }

        UiNotice {
            id: popuplockTiles
            text: window.lockTiles ? qsTr("You can move the tiles!") : qsTr("The tiles are locked now")
        }

        Timer {
            id: popuplockTilesAutoClose
            interval: 2000; running: false; repeat: false
            onTriggered: popuplockTiles.close();
        }

        ToolButton {
            id: toolButtonLoadSettings
            icon.source: window.ui.modern ? "" : "icons/icons/tray-arrow-up.png"
            UiIcon { anchors.centerIn: parent; width: 24; height: 24; name: "upload_file"; color: window.ui.textMain; visible: window.ui.modern }
            onClicked: {
                stackView.push("SettingsList.qml")
                stackView.currentItem.loadSettings.connect(loadSettings)
                stackView.currentItem.loadSettings.connect(function(url) {
                    stackView.pop();
                    if (stackView.depth > 1) {
                        stackView.pop()
                    }
                    popupLoadSettings.open();
                 });
                drawer.close()
            }
            anchors.right: toolButtonSaveSettings.left
            visible: false
        }

        ToolButton {
            id: toolButtonSettingsSearch
            text: window.ui.modern ? "" : "\uD83D\uDD0D"
            UiIcon { anchors.centerIn: parent; width: 24; height: 24; name: "search"; color: window.ui.textMain; visible: window.ui.modern }
            font.pixelSize: Qt.application.font.pixelSize * 1.25
            onClicked: {
                if (headerToolbar.settingsPageActive)
                    stackView.currentItem.showSettingsSearch()
            }
            anchors.right: toolButtonLoadSettings.left
            // Modern look: the settings keep their search field on the page itself
            visible: headerToolbar.settingsPageActive && !window.ui.modern
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Search settings")
        }

        ToolButton {
            id: toolButtonSaveSettings
            icon.source: window.ui.modern ? "" : "icons/icons/tray-arrow-down.png"
            UiIcon { anchors.centerIn: parent; width: 24; height: 24; name: "save"; color: window.ui.textMain; visible: window.ui.modern }
            onClicked: {
                saveSettings("settings");
                popupSaveFile.open()
            }
            anchors.right: toolButtonAutoResistance.left/*toolClassifica.left*/
            visible: false
        }

        /*ToolButton {
            id: toolClassifica
            icon.source: "icons/icons/chart.png"
            onClicked: {  if(settings.classifica_enable) stackView.push("Classifica.qml"); else popupClassificaHelper.open(); }
            anchors.right: toolButtonAutoResistance.left
        }*/

        ToolButton {
            function loadMaps() {
                if(rootItem.currentCoordinateValid) {
                    console.log("coordinate is valid for map");
                    if(googleMapUI.status === Loader.Ready)
                        stackView.push(googleMapUI.item);
                    else
                        googleMapUI.active = true;

                } else {
                    console.log("coordinate is NOT valid for map");
                }
            }
            id: toolButtonMaps
            icon.source: window.ui.modern ? "" : ( "icons/icons/maps-icon-16.png" )
            UiIcon { anchors.centerIn: parent; width: 24; height: 24; name: "map"; color: window.ui.textMain; visible: window.ui.modern }
            onClicked: { loadMaps(); }
            anchors.right: toolButtonChart.left
            visible: rootItem.mapsVisible
        }      

        ToolButton {
            function loadVideo() {
                if(rootItem.currentCoordinateValid || rootItem.trainProgramLoadedWithVideo) {
                    console.log("coordinate is valid for map");
                    //stackView.push("videoPlayback.qml");
                    rootItem.videoVisible = !rootItem.videoVisible
                } else {
                    console.log("coordinate is NOT valid for map");
                }
            }
            id: toolButtonVideo
            icon.source: window.ui.modern ? "" : ( "icons/icons/video.png" )
            UiIcon { anchors.centerIn: parent; width: 24; height: 24; name: "videocam"; color: window.ui.textMain; visible: window.ui.modern }
            onClicked: { loadVideo(); }
            anchors.right: toolButtonMaps.left
            visible: rootItem.videoIconVisible
        }

        ToolButton {
            id: toolButtonChart
            icon.source: window.ui.modern ? "" : ( "icons/icons/chart.png" )
            UiIcon { anchors.centerIn: parent; width: 24; height: 24; name: "show_chart"; color: window.ui.textMain; visible: window.ui.modern }
            onClicked: { rootItem.chartFooterVisible = !rootItem.chartFooterVisible }
            anchors.right: toolButtonLockTiles.left
            visible: rootItem.chartIconVisible
        }

        ToolButton {
            id: toolButtonLockTiles
            icon.source: window.ui.modern ? "" : ( window.lockTiles ? "icons/icons/unlock.png" : "icons/icons/lock.png")
            UiIcon { anchors.centerIn: parent; width: 24; height: 24; name: (window.lockTiles ? "lock_open" : "lock"); color: window.ui.textMain; visible: window.ui.modern }
            onClicked: { window.lockTiles = !window.lockTiles; console.log("lock tiles toggled " + window.lockTiles); popuplockTiles.open(); popuplockTilesAutoClose.running = true; }
            anchors.right: toolButtonAutoResistance.left
            // Modern look: the tiles are on the home page only, so is their lock; while the
            // equipment is being searched (rootItem.labelHelp) there are no tiles yet
            visible: window.ui.modern ? stackView.depth === 1 && typeof rootItem !== "undefined" && !rootItem.labelHelp : !toolButtonSaveSettings.visible
            width: visible ? implicitWidth : 0
        }

        ToolButton {
            id: toolButtonAutoResistance
            icon.source: window.ui.modern ? "" : ( rootItem.autoResistance ? "icons/icons/resistance.png" : "icons/icons/pause.png")
            UiIcon { anchors.centerIn: parent; width: 24; height: 24; name: (rootItem.autoResistance ? "motion_mode" : "pause_circle"); color: window.ui.textMain; visible: window.ui.modern }
            onClicked: { rootItem.autoResistance = !rootItem.autoResistance; console.log("auto resistance toggled " + rootItem.autoResistance); popupAutoResistance.open(); popupAutoResistanceAutoClose.running = true; }
            anchors.right: parent.right
            // Modern look: a workout control, on the home page only and once the equipment is
            // connected (before that there is no resistance to follow)
            visible: window.ui.modern ? stackView.depth === 1 && typeof rootItem !== "undefined" && !rootItem.labelHelp : !headerToolbar.settingsPageActive
            width: visible ? implicitWidth : 0
        }

        Label {
            text: stackView.currentItem.title
            font.pixelSize: window.ui.modern ? 18 : Qt.application.font.pixelSize
            font.weight: window.ui.modern ? Font.DemiBold : Font.Normal
            color: window.ui.modern ? window.ui.textMain : Material.foreground
            // Fixed position, like the buttons: centred in the full bar, it moved on its own when the bar collapsed
            anchors.horizontalCenter: parent.horizontalCenter
            y: (headerToolbar.contentHeight - height) / 2
        }
    }

    // The settings pages are about 1.3 MB of QML. The first time after install the engine
    // compiles them when they are opened (then from the disk cache), and the settings froze
    // for a moment. They are compiled ahead instead, off the GUI thread: a few seconds after
    // start, or as soon as the drawer starts to open if that comes first. Only compiled, not
    // created. The components are kept so the engine does not drop the compiled types; a push
    // of the same file while the compilation runs picks it up rather than starting over.
    property var settingsWarmup: []
    function warmUpSettings() {
        if (settingsWarmup.length > 0)
            return
        var started = Date.now()
        var pages = ["settings.qml", "settings-tiles.qml"]
        var components = []
        pages.forEach(function (page) {
            var component = Qt.createComponent(page, Component.Asynchronous)
            var report = function () {
                if (component.status === Component.Ready)
                    console.log("QZ-TIMING warm-up " + page + " ready in " + (Date.now() - started) + " ms")
                else if (component.status === Component.Error)
                    console.warn("QZ-TIMING warm-up " + page + ": " + component.errorString())
            }
            if (component.status === Component.Loading)
                component.statusChanged.connect(report)
            else
                report()
            components.push(component)
        })
        settingsWarmup = components
    }

    Timer {
        interval: 4000; running: true; repeat: false
        onTriggered: window.warmUpSettings()
    }

    // Drawer entries, shared by the classic and the modern drawer
    function drawerAction(key) {
        switch (key) {
        case "profile":
            toolButtonLoadSettings.visible = true;
            toolButtonSaveSettings.visible = true;
            stackView.push("profiles.qml")
            stackView.currentItem.profile_open_clicked.connect(profile_open_clicked)
            break
        case "settings":
            toolButtonLoadSettings.visible = true;
            toolButtonSaveSettings.visible = true;
            var settingsPushStarted = Date.now()
            stackView.push("settings.qml")
            console.log("QZ-TIMING settings.qml opened in " + (Date.now() - settingsPushStarted) + " ms")
            break
        case "history":
            stackView.push("WorkoutsHistory.qml")
            stackView.currentItem.fitfile_preview_clicked.connect(fitfile_preview_clicked)
            break
        case "swagbag":
            stackView.push("SwagBagView.qml")
            break
        case "charts":
            console.log(CHARTJS)
            if(CHARTJS)
                stackView.push("ChartJsTest.qml")
            else
                stackView.push("ChartsEndWorkout.qml")
            break
        case "opengpx":
            stackView.push("GPXList.qml")
            stackView.currentItem.trainprogram_open_clicked.connect(gpx_open_clicked)
            stackView.currentItem.trainprogram_open_other_folder.connect(gpx_open_other_folder)
            stackView.currentItem.trainprogram_preview.connect(gpxpreview_open_clicked)
            stackView.currentItem.trainprogram_open_clicked.connect(function(url) {
                stackView.pop();
                popup.open();
             });
            break
        case "trainprogram":
            if(CHARTJS)
                stackView.push("TrainingProgramsListJS.qml")
            else
                stackView.push("TrainingProgramsList.qml")
            stackView.currentItem.trainprogram_open_clicked.connect(trainprogram_open_clicked)
            stackView.currentItem.trainprogram_open_other_folder.connect(trainprogram_open_other_folder)
            stackView.currentItem.trainprogram_preview.connect(trainprogram_preview)
            stackView.currentItem.trainprogram_autostart_requested.connect(trainprogram_autostart_requested)
            stackView.currentItem.trainprogram_open_clicked.connect(function(url) {
                stackView.pop();
             });
            break
        case "editor":
            var editorPage = stackView.push("WorkoutEditor.qml")
            if (editorPage) {
                editorPage.closeRequested.connect(function() {
                    stackView.pop()
                })
                // Close editor when workout is started from Save & Start
                trainprogram_autostart_requested.connect(function() {
                    console.log("[main.qml] trainprogram_autostart_requested received, closing editor")
                    editorPage.closeRequested()
                })
            }
            break
        case "savegpx":
            gpx_save_clicked()
            drawer.close()
            popupSaveFile.open()
            return
        case "savefit":
            fit_save_clicked()
            drawer.close()
            popupSaveFile.open()
            return
        case "wizard":
            stackView.push("Wizard.qml")
            break
        case "help":
            Qt.openUrlExternally("https://robertoviola.cloud/qdomyos-zwift-guide/");
            break
        case "community":
            Qt.openUrlExternally("https://www.facebook.com/groups/149984563348738");
            break
        case "credits":
            stackView.push("Credits.qml")
            break
        case "quit":
            console.log("closing...")
            Qt.callLater(Qt.quit)
            return
        case "strava":
            if (rootItem.isStravaLoggedIn()) {
                stravaLogoutConfirm.visible = true
            } else {
                stackView.push("WebStravaAuth.qml")
                strava_connect_clicked()
            }
            break
        case "peloton":
            if (rootItem.isPelotonLoggedIn()) {
                pelotonLogoutConfirm.visible = true
            } else {
                stackView.push("WebPelotonAuth.qml")
                stackView.currentItem.goBack.connect(function() {
                    stackView.pop();
                })
                peloton_connect_clicked()
            }
            break
        case "garmin":
            toolButtonLoadSettings.visible = true;
            toolButtonSaveSettings.visible = true;
            stackView.push("settings.qml")
            if (stackView.currentItem) {
                if (stackView.currentItem.openGarminSection) {
                    stackView.currentItem.openGarminSection()
                }
            }
            break
        case "intervals":
            if (rootItem.isIntervalsICULoggedIn()) {
                intervalsICULogoutConfirm.visible = true
            } else {
                stackView.push("WebIntervalsICUAuth.qml")
                intervalsicu_connect_clicked()
            }
            break
        }
        drawer.close()
    }

    Drawer {
        id: drawer
        width: window.ui.modern ? Math.min(window.width * 0.82, 340 + getLeftPadding()) : window.width * 0.66
        height: window.height
        topPadding: getTopPadding()
        bottomPadding: getBottomPadding()
        leftPadding: getLeftPadding()
        rightPadding: window.ui.modern ? 0 : getRightPadding()
        Accessible.ignored: !drawer.opened
        onAboutToShow: window.warmUpSettings()

        // Modern: a sheet with rounded outer corners. The rectangle runs past the left edge,
        // so only the right-hand corners show
        background: Rectangle {
            color: window.ui.modern ? window.ui.surface : Material.dialogColor
            radius: window.ui.modern ? 20 : 0
            x: window.ui.modern ? -radius : 0
            width: parent.width + (window.ui.modern ? radius : 0)
            height: parent.height
        }

        ScrollView {
            visible: !window.ui.modern
            contentWidth: -1
            focus: true
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.fill: parent

            Column {
                anchors.fill: parent
                spacing: 3

                ItemDelegate {
                    text: qsTr("Profile: ") + settings.profile_name
                    width: parent.width
                    onClicked: drawerAction("profile")
                }

                ItemDelegate {
                    text: qsTr("Settings")
                    width: parent.width
                    onClicked: drawerAction("settings")
                }

            ItemDelegate {
                text: qsTr("Workouts History")
                width: parent.width
                onClicked: drawerAction("history")
            }
                ItemDelegate {
                    text: qsTr("Swag Bag")
                    width: parent.width
                    onClicked: drawerAction("swagbag")
                }

                ItemDelegate {
                    text: qsTr("Charts")
                    width: parent.width
                    onClicked: drawerAction("charts")
                }
                ItemDelegate {
                    id: gpx_open
                    text: qsTr("Open GPX")
                    width: parent.width
                    onClicked: drawerAction("opengpx")
                }
                ItemDelegate {
                    id: trainprogram_open
                    text: qsTr("Open Train Program")
                    width: parent.width
                    onClicked: drawerAction("trainprogram")
                }
                ItemDelegate {
                    text: qsTr("Workout Editor")
                    width: parent.width
                    onClicked: drawerAction("editor")
                }
                /*
                ItemDelegate {
                    text: qsTr("What's On Zwift™")
                    width: parent.width
                    onClicked: {
                        popupWhatsOnZwiftHelper.open()
                    }
                }*/

                ItemDelegate {
                    id: gpx_save
                    text: qsTr("Save GPX")
                    width: parent.width
                    onClicked: drawerAction("savegpx")
                }
                ItemDelegate {
                    id: fit_save
                    text: qsTr("Save FIT")
                    width: parent.width
                    onClicked: drawerAction("savefit")
                }
                ItemDelegate {
                    id: wizardItem
                    text: qsTr("Wizard")
                    width: parent.width
                    onClicked: drawerAction("wizard")
                }
                ItemDelegate {
                    id: help
                    text: qsTr("Help")
                    width: parent.width
                    onClicked: drawerAction("help")
                }
                ItemDelegate {
                    id: community
                    text: qsTr("Community")
                    width: parent.width
                    onClicked: drawerAction("community")
                }
                ItemDelegate {
                    text: qsTr("Credits")
                    width: parent.width
                    onClicked: drawerAction("credits")
                }
                ItemDelegate {
                    text: qsTr("Quit")
                    width: parent.width
                    visible: OS_VERSION === "Other" ? true : false
                    onClicked: drawerAction("quit")
                }

                ItemDelegate {
                    text: "version 2.22.0"
                    width: parent.width
                }

                ItemDelegate {
                    id: strava_connect
                    Image {
                        anchors.left: parent.left;
                        anchors.verticalCenter: parent.verticalCenter
                        source: "icons/icons/btn_strava_connectwith_orange.png"
                        fillMode: Image.PreserveAspectFit
                        visible: true
                        width: parent.width
                    }
                    width: parent.width
                    onClicked: drawerAction("strava")
                }

                ItemDelegate {
                    Image {
                        anchors.left: parent.left;
                        anchors.verticalCenter: parent.verticalCenter
                        source: "icons/icons/Button_Connect_Rect_DarkMode.png"
                        fillMode: Image.PreserveAspectFit
                        visible: true
                        width: parent.width
                    }
                    width: parent.width
                    onClicked: drawerAction("peloton")
                }

                ItemDelegate {
                    Image {
                        anchors.left: parent.left;
                        anchors.verticalCenter: parent.verticalCenter
                        source: "icons/icons/garmin-connect-badge.png"
                        fillMode: Image.PreserveAspectFit
                        visible: true
                        width: parent.width
                        height: 48
                    }
                    width: parent.width
                    onClicked: drawerAction("garmin")
                }

				ItemDelegate {
                    Image {
                        anchors.left: parent.left;
                        anchors.verticalCenter: parent.verticalCenter
                        source: "icons/icons/intervals-logo-with-name.png"
                        fillMode: Image.PreserveAspectFit
                        visible: true
                        width: parent.width
                    }
                    width: parent.width
                    onClicked: drawerAction("intervals")
                }

                    FileDialog {
                        id: fileDialogGPX
                         title: qsTr("Please choose a file")
                         folder: "file://" + rootItem.getWritableAppDir() + 'gpx'
                         onAccepted: {
                             console.log("You chose: " + fileDialogGPX.fileUrl)
                              gpx_open_clicked(fileDialogGPX.fileUrl)
                              fileDialogGPX.close()
                              popup.open()
                            }
                         onRejected: {
                             console.log("Canceled")
                              fileDialogGPX.close()
                            }
                        }
            }
        }

        // Modern drawer: header with the connection state and the profile, grouped entries,
        // the service logins as cards at the bottom
        Flickable {
            id: modernDrawerList
            visible: window.ui.modern
            anchors.fill: parent
            contentHeight: modernDrawerColumn.height + 16
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // A scroll that starts on an entry: the entry took the press at once (lit up) and
            // the list got the move only past the drag threshold, while the drawer took a
            // slightly sideways one to close - the list often did not scroll. The entries get
            // the press only when the finger stays put, and only vertical moves scroll
            flickableDirection: Flickable.VerticalFlick
            pressDelay: 120
            ScrollIndicator.vertical: ScrollIndicator { }

            Column {
                id: modernDrawerColumn
                width: modernDrawerList.width

                Item {
                    width: parent.width
                    height: 132

                    Image {
                        id: drawerLogo
                        x: 24
                        y: 22
                        width: 44
                        height: 44
                        source: "qrc:/inner_templates/chartjs/qzlogo.png"
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    Label {
                        id: drawerAppName
                        anchors.left: drawerLogo.right
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        y: drawerLogo.y + 1
                        text: "QZ Fitness"
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                        color: window.ui.textMain
                    }
                    Row {
                        anchors.left: drawerAppName.left
                        anchors.right: drawerAppName.right
                        anchors.top: drawerAppName.bottom
                        anchors.topMargin: 2
                        spacing: 6
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8
                            height: 8
                            radius: 4
                            color: (typeof rootItem !== "undefined" && rootItem && rootItem.device) ? "#7EDC8A" : window.ui.textMuted
                        }
                        Label {
                            width: parent.width - 14
                            text: (typeof rootItem !== "undefined" && rootItem) ? rootItem.info : ""
                            font.pixelSize: 13
                            color: window.ui.textMuted
                            elide: Text.ElideRight
                        }
                    }

                    // Profile chip
                    Rectangle {
                        x: 24
                        y: 82
                        height: 36
                        width: Math.min(parent.width - 48, profileChipRow.implicitWidth + 28)
                        radius: 18
                        color: profileChipArea.pressed ? window.ui.alpha(window.ui.accent, 0.28) : window.ui.alpha(window.ui.accent, 0.16)
                        Row {
                            id: profileChipRow
                            anchors.verticalCenter: parent.verticalCenter
                            x: 12
                            spacing: 8
                            UiIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                height: 18
                                name: "person"
                                color: window.ui.accent
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, drawer.width - 110)
                                text: qsTr("Profile: ") + settings.profile_name
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                color: window.ui.textMain
                                elide: Text.ElideRight
                            }
                        }
                        MouseArea {
                            id: profileChipArea
                            anchors.fill: parent
                            onClicked: drawerAction("profile")
                        }
                    }
                }

                Component {
                    id: drawerSectionHeader
                    Label {
                        leftPadding: 28
                        topPadding: 14
                        bottomPadding: 6
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.4
                        color: window.ui.accent
                    }
                }

                Loader { sourceComponent: drawerSectionHeader; onLoaded: item.text = qsTr("Workout") }
                UiDrawerItem { text: qsTr("Open Train Program"); iconName: "list_alt"; onClicked: drawerAction("trainprogram") }
                UiDrawerItem { text: qsTr("Workout Editor"); iconName: "edit_note"; onClicked: drawerAction("editor") }
                UiDrawerItem { text: qsTr("Open GPX"); iconName: "route"; onClicked: drawerAction("opengpx") }
                UiDrawerItem { text: qsTr("Charts"); iconName: "bar_chart"; onClicked: drawerAction("charts") }
                UiDrawerItem { text: qsTr("Workouts History"); iconName: "history"; onClicked: drawerAction("history") }
                UiDrawerItem { text: qsTr("Save FIT"); iconName: "download"; onClicked: drawerAction("savefit") }
                UiDrawerItem { text: qsTr("Save GPX"); iconName: "download"; onClicked: drawerAction("savegpx") }

                Rectangle { x: 28; width: parent.width - 56; height: 1; color: window.ui.outline; opacity: 0.6 }

                Loader { sourceComponent: drawerSectionHeader; onLoaded: item.text = qsTr("App") }
                UiDrawerItem { text: qsTr("Settings"); iconName: "settings"; onClicked: drawerAction("settings") }
                UiDrawerItem { text: qsTr("Wizard"); iconName: "rocket_launch"; onClicked: drawerAction("wizard") }
                UiDrawerItem { text: qsTr("Swag Bag"); iconName: "redeem"; onClicked: drawerAction("swagbag") }
                UiDrawerItem { text: qsTr("Help"); iconName: "help"; external: true; onClicked: drawerAction("help") }
                UiDrawerItem { text: qsTr("Community"); iconName: "groups"; external: true; onClicked: drawerAction("community") }
                UiDrawerItem { text: qsTr("Credits"); iconName: "info"; onClicked: drawerAction("credits") }
                UiDrawerItem { text: qsTr("Quit"); iconName: "power_settings_new"; visible: OS_VERSION === "Other"; onClicked: drawerAction("quit") }

                Rectangle { x: 28; width: parent.width - 56; height: 1; color: window.ui.outline; opacity: 0.6 }

                Loader { sourceComponent: drawerSectionHeader; onLoaded: item.text = qsTr("Services") }

                Grid {
                    x: 16
                    width: parent.width - 32
                    columns: 2
                    spacing: 8
                    Repeater {
                        model: [
                            { key: "strava", image: "icons/icons/btn_strava_connectwith_orange.png" },
                            { key: "peloton", image: "icons/icons/Button_Connect_Rect_DarkMode.png" },
                            { key: "garmin", image: "icons/icons/garmin-connect-badge.png" },
                            { key: "intervals", image: "icons/icons/intervals-logo-with-name.png" }
                        ]
                        delegate: Rectangle {
                            width: (parent.width - 8) / 2
                            height: 52
                            radius: 14
                            color: serviceArea.pressed ? window.ui.surfaceHighest : window.ui.surfaceHigh
                            Image {
                                anchors.fill: parent
                                anchors.margins: 8
                                source: modelData.image
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }
                            MouseArea {
                                id: serviceArea
                                anchors.fill: parent
                                onClicked: drawerAction(modelData.key)
                            }
                        }
                    }
                }

                Label {
                    width: parent.width
                    leftPadding: 28
                    topPadding: 16
                    text: "version 2.22.0"
                    font.pixelSize: 12
                    color: window.ui.textMuted
                }
            }
        }
    }

    // Wrapper Item to prevent ApplicationWindow from capturing all VoiceOver focus
    Item {
        anchors.fill: parent
        Accessible.ignored: true

        StackView {
            id: stackView
            initialItem: "Home.qml"
            anchors.fill: parent
            anchors.bottomMargin: (Screen.orientation === Qt.PortraitOrientation || Screen.orientation === Qt.InvertedPortraitOrientation) ? getBottomPadding() : 0
            anchors.rightMargin: getRightPadding()
            anchors.leftMargin: getLeftPadding()
            focus: true
            // Only the tile grid scrolls the toolbar away; any other page gets it back
            onCurrentItemChanged: headerToolbar.scrolledAway = false
            Connections {
                target: stackView.currentItem
                ignoreUnknownSignals: true
                function onPeloton_connect_clicked() {
                    if (rootItem.isPelotonLoggedIn()) {
                        pelotonLogoutConfirm.visible = true
                    } else {
                        stackView.push("WebPelotonAuth.qml")
                        stackView.currentItem.goBack.connect(function() {
                            stackView.pop();
                        })
                        peloton_connect_clicked()
                    }
                }
            }
            Keys.onVolumeUpPressed: (event)=> { console.log("onVolumeUpPressed"); volumeUp(); event.accepted = settings.volume_change_gears; }
            Keys.onVolumeDownPressed: (event)=> { console.log("onVolumeDownPressed"); volumeDown(); event.accepted = settings.volume_change_gears; }
            Keys.onPressed: (event)=> {
                if (event.key === Qt.Key_MediaPrevious) {
                    keyMediaPrevious();
                    event.accepted = true;
                } else if (event.key === Qt.Key_MediaNext) {
                    keyMediaNext();
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            }

            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_speed_plus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardPlus("speed") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_speed_minus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardMinus("speed") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_inclination_plus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardPlus("inclination") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_inclination_minus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardMinus("inclination") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_resistance_plus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardPlus("resistance") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_resistance_minus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardMinus("resistance") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_peloton_resistance_plus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardPlus("peloton_resistance") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_peloton_resistance_minus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardMinus("peloton_resistance") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_target_resistance_plus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardPlus("target_resistance") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_target_resistance_minus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardMinus("target_resistance") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_target_power_plus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardPlus("target_power") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_target_power_minus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardMinus("target_power") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_target_zone_plus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardPlus("target_zone") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_target_zone_minus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardMinus("target_zone") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_target_speed_plus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardPlus("target_speed") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_target_speed_minus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardMinus("target_speed") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_target_incline_plus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardPlus("target_inclination") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_target_incline_minus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardMinus("target_inclination") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_fan_plus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardPlus("fan") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_fan_minus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardMinus("fan") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_peloton_offset_plus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardPlus("peloton_offset") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_peloton_offset_minus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardMinus("peloton_offset") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_peloton_remaining_plus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardPlus("peloton_remaining") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_peloton_remaining_minus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardMinus("peloton_remaining") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_remaining_time_plus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardPlus("remainingtimetrainprogramrow") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_remaining_time_minus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardMinus("remainingtimetrainprogramrow") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_gears_plus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardPlus("gears") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_gears_minus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardMinus("gears") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_pid_hr_plus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardPlus("pid_hr") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_pid_hr_minus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardMinus("pid_hr") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_ext_incline_plus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardPlus("external_inclination") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_ext_incline_minus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardMinus("external_inclination") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_biggears_plus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("biggearsplus") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_biggears_minus; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("biggearsminus") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_avs_cruise; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("autoVirtualShiftingCruise") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_avs_climb; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("autoVirtualShiftingClimb") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_avs_sprint; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("autoVirtualShiftingSprint") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_power_avg; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("powerAvg") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_erg_mode; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("erg_mode") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_resistance_1; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_resistance_1") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_resistance_2; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_resistance_2") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_resistance_3; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_resistance_3") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_resistance_4; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_resistance_4") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_resistance_5; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_resistance_5") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_speed_1; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_speed_1") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_speed_2; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_speed_2") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_speed_3; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_speed_3") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_speed_4; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_speed_4") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_speed_5; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_speed_5") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_inclination_1; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_inclination_1") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_inclination_2; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_inclination_2") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_inclination_3; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_inclination_3") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_inclination_4; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_inclination_4") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_inclination_5; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_inclination_5") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_powerzone_1; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_powerzone_1") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_powerzone_2; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_powerzone_2") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_powerzone_3; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_powerzone_3") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_powerzone_4; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_powerzone_4") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_powerzone_5; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_powerzone_5") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_powerzone_6; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_powerzone_6") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_preset_powerzone_7; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLargeButton("preset_powerzone_7") }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_auto_resistance; enabled: shortcutReady(sequence); onActivated: rootItem.setAutoResistance(!rootItem.autoResistance) }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_lap; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardLap() }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_start_stop; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardStartStop() }
            Shortcut { context: Qt.WindowShortcut; sequence: settings.shortcut_stop; enabled: shortcutReady(sequence); onActivated: rootItem.keyboardStop() }
        }
    }
}

/*##^##
Designer {
    D{i:0;autoSize:true;height:480;width:640}
}
##^##*/
