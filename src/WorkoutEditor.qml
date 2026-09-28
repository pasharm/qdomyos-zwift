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
    readonly property var pageTheme: {
        var ui = window.ui
        if (!ui.modern)
            return null
        return {
            modern: "1",
            dark: ui.dark,
            bg: ui.bg.toString(),
            surface: ui.surface.toString(),
            surfaceHigh: ui.surfaceHigh.toString(),
            surfaceHighest: ui.surfaceHighest.toString(),
            outline: ui.outline.toString(),
            text: ui.textMain.toString(),
            muted: ui.textMuted.toString(),
            accent: ui.accent.toString(),
            accentInk: ui.accentInk.toString(),
            danger: ui.danger.toString()
        }
    }

    function themeFragment() {
        if (!pageTheme)
            return ""
        var parts = []
        for (var key in pageTheme) {
            var value = key === "dark" ? (pageTheme.dark ? "1" : "0") : pageTheme[key]
            parts.push(key + "=" + encodeURIComponent(value))
        }
        return "#" + parts.join("&")
    }

    onPageThemeChanged: {
        if (pageLoaded && pageTheme)
            webView.runJavaScript("window.qzApplyTheme && window.qzApplyTheme(" + JSON.stringify(pageTheme) + ")")
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
            var targetUrl = "http://localhost:" + port + "/workouteditor/index.html" + root.themeFragment()
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

    Component.onCompleted: portPoller.start()
}
