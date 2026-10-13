import QtQuick 2.12
import QtQuick.Controls 2.5
import Qt.labs.settings 1.0
import QtWebView 1.1

Item {
    id: root
    property string title: qsTr("Workout Editor")
    property bool pageLoaded: false

    signal closeRequested()

    // Modern look: the page takes the app theme colours (index.html, qzApplyTheme). They go in
    // the URL fragment for the first load and through runJavaScript when the theme changes
    // later, so an open workout is not reloaded. Null in the classic look: the page keeps its
    // own dark palette.
    readonly property var pageTheme: window.ui.webTheme

    onPageThemeChanged: {
        if (pageLoaded && pageTheme)
            webView.runJavaScript(window.ui.webThemeScript())
    }

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
            var targetUrl = "http://localhost:" + port + "/workouteditor/index.html" + window.ui.webThemeFragment()
            if (webView.url !== targetUrl) {
                webView.url = targetUrl
            }
        }
    }

    WebView {
        id: webView
        anchors.fill: parent
        // root.visible too: the kept page (modern look, main.qml) is only hidden when closed,
        // and the native view does not follow the visibility of its parents by itself
        visible: root.pageLoaded && root.visible
        onLoadingChanged: {
            if (loadRequest.status === WebView.LoadSucceededStatus) {
                root.pageLoaded = true
                // A theme change during the load only moved the fragment: apply the current one
                if (root.pageTheme)
                    webView.runJavaScript(window.ui.webThemeScript())
                busy.visible = false
                busy.running = false
                portPoller.stop()
            } else if (loadRequest.status === WebView.LoadFailedStatus) {
                root.pageLoaded = false
                busy.visible = true
                busy.running = true
                portPoller.start()
            }
        }
    }

    BusyIndicator {
        id: busy
        anchors.centerIn: parent
        visible: !root.pageLoaded
        running: !root.pageLoaded
    }

    // The kept page (modern look) goes back to its first parent when closed: hidden there
    StackView.onRemoved: root.visible = false

    Component.onCompleted: portPoller.start()
}
