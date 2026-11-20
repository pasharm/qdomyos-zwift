import QtQuick 2.12
import QtQuick.Controls 2.5
import Qt.labs.settings 1.0
import QtWebView 1.1

Item {
    id: root
    property string title: qsTr("Workout Editor")
    property bool pageLoaded: false

    signal closeRequested()

    Settings {
        id: settings
    }

    Timer {
        id: portPoller
        interval: 500
        repeat: true
        running: !root.pageLoaded
        onTriggered: {
            var port = settings.value("template_inner_QZWS_port", 0)
            if (!port) {
                return
            }
            var targetUrl = "http://localhost:" + port + "/workouteditor/index.html"
            if (webView.url !== targetUrl) {
                webView.url = targetUrl
            }
        }
    }

    WebView {
        id: webView
        anchors.fill: parent
        visible: root.pageLoaded
        onLoadingChanged: {
            if (loadRequest.status === WebView.LoadSucceededStatus) {
                root.pageLoaded = true
                busy.visible = false
                busy.running = false
                portPoller.stop()
                // loaded after Back (portPoller): hidden already, so off the server at once
                if (root.StackView.status !== StackView.Active)
                    webView.runJavaScript("window.main_ws_pause && main_ws_pause(true)")
            } else if (loadRequest.status === WebView.LoadFailedStatus) {
                root.pageLoaded = false
                busy.visible = true
                busy.running = true
                portPoller.start()
            }
        }
    }

    // Shown again without a reload (the modern look keeps the page, main.qml; any look when a page
    // above it is closed): the page asks again for the connected machine, FTP, the units and the
    // saved workouts. Not at the first opening: the page is still loading and asks itself
    StackView.onActivated: {
        if (root.pageLoaded)
            webView.runJavaScript("window.main_ws_pause && main_ws_pause(false);"
                                  + " window.qzEditorReopened && window.qzEditorReopened()")
    }
    // Hidden (kept by the modern look, or under another page): off the server until shown again,
    // or it would take every update of the workout for nothing (main_ws_manager.js)
    StackView.onDeactivated: {
        if (root.pageLoaded)
            webView.runJavaScript("window.main_ws_pause && main_ws_pause(true)")
    }

    // a new app language: the page asks for its texts again (a reload would lose the edits)
    Connections {
        target: rootItem
        function onAppLanguageChanged() {
            webView.runJavaScript("window.qzRequestTranslations && window.qzRequestTranslations()")
        }
    }

    BusyIndicator {
        id: busy
        anchors.centerIn: parent
        visible: !root.pageLoaded
        running: !root.pageLoaded
    }

    Component.onCompleted: portPoller.start()
}
