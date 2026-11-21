import QtQuick 2.7
import QtQuick.Layouts 1.3
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.0
import Qt.labs.settings 1.0
import QtWebView 1.1
import QtQuick.Window 2.2

ColumnLayout {
    signal popupclose()
    id: column1
    spacing: 10
    anchors.fill: parent

    // Modern look: the page takes the app theme colours (qz-theme-bridge.js) from the URL
    // fragment of the first load and through runJavaScript when the theme changes later
    readonly property var pageTheme: window.ui.webTheme
    property bool pageLoaded: false
    // Modern look: the native web view stays off the screen until the page has drawn once.
    // It is white before its first paint and lies over everything QML draws (on Android a native
    // view over the Qt surface), so it flashed white on the dark theme. Moved aside, not hidden:
    // hiding takes the view out of the window (QAndroidPlatformForeignWindow::setVisible destroys
    // its surface), the page was laid out for a wrong width and opened zoomed in
    property bool pageShown: !window.ui.modern
    // Off the screen too while the drawer is open or dragged: the native view lies over it (QTBUG-58365)
    readonly property real offScreen: pageShown && drawer.position === 0 ? 0 : Screen.width + Screen.height
    // A chart spread over the page (chartfullscreen.js): the page tells it in its title
    property bool chartFullscreen: false
    // The spread chart takes the app header's room too: the header folds to the status bar
    // inset (hidden, it left the page under the status bar).
    // Back is the key or the collapse button of the chart then, the toolbar arrow folds away
    onChartFullscreenChanged: headerToolbar.folded = chartFullscreen

    // Back (the key; in the modern look also the arrow of the toolbar, main.qml navigateBack)
    // closes the spread chart first instead of the page. Cleared at once: a second back
    // before the new title comes leaves the page as usual
    function handleBack() {
        if (!chartFullscreen)
            return false
        chartFullscreen = false
        webView.runJavaScript("window.qzChartFullscreen && window.qzChartFullscreen.exit()")
        return true
    }

    // Modern look: the page is kept (main.qml) and opened again: the charts of the workout so
    // far are drawn anew, and the mail goes as on a fresh open. Drawn at once ("still" in the
    // query, chart.htm): growing from zero again every block looked like a redraw. A new query
    // loads the page anew, the fragment keeps the current theme
    // The new load is kept off the screen like the first one, until its load ends
    function reopen() {
        headerToolbar.visible = true
        if (pageLoaded) {
            if (window.ui.modern)
                pageShown = false
            reloading = true
            sentTheme = JSON.stringify(pageTheme)
            webView.url = pageUrl("?still=" + Date.now())
        }
        sendMailFallback.restart()
    }

    function pageUrl(query) {
        return "http://localhost:" + settings.value("template_inner_QZWS_port") + "/chartjs/chart.htm" +
               query + window.ui.webThemeFragment()
    }
    // A kept page is taken off the stack, not destroyed: hidden until pushed again
    // (and the mail timer stopped: a page destroyed before its 10 s sent nothing)
    StackView.onRemoved: {
        handleBack() // a spread chart closed, the header back for the next page
        sendMailFallback.stop()
        column1.visible = false
    }

    // The theme the page has, as JSON: that of the fragment of the first load, then of each script sent
    property string sentTheme: ""
    function applyTheme() {
        sentTheme = JSON.stringify(pageTheme)
        webView.runJavaScript(window.ui.webThemeScript())
    }

    // reopen() loads the page again: a theme change waits for the end of that load
    // (onLoadingChanged compares sentTheme), a script sent meanwhile could reach the old document
    property bool reloading: false

    // null (the modern look switched off) takes the theme off the page
    onPageThemeChanged: {
        if (pageLoaded && !reloading)
            applyTheme()
    }

    Settings {
        id: settings
    }
    WebView {
        id: webView
        anchors.fill: parent
        // The native view lies over everything QML draws: it goes with the page when kept
        visible: column1.visible
        anchors.leftMargin: -column1.offScreen
        anchors.rightMargin: column1.offScreen
        onTitleChanged: column1.chartFullscreen = title.indexOf("#fullscreen") >= 0
        onLoadingChanged: {
            if (loadRequest.errorString) {
                console.error(loadRequest.errorString);
                console.error("port " + settings.value("template_inner_QZWS_port"));
            }
            if (loadRequest.status !== WebView.LoadStartedStatus)
                column1.reloading = false
            if (loadRequest.status === WebView.LoadSucceededStatus) {
                column1.pageLoaded = true
                // A theme change during the load reached the page neither in the fragment nor in a
                // script: apply the current one
                if (JSON.stringify(column1.pageTheme) !== column1.sentTheme)
                    column1.applyTheme()
            }
            // Shown when the load ends, failed too: the page has its background by then (the
            // theme is set in its head), the charts follow on it once the session data comes
            if (loadRequest.status !== WebView.LoadStartedStatus)
                column1.pageShown = true
        }
    }

    // On the item that holds the page, not on the ColumnLayout: a layout warns about anchors on
    // each child item it manages. Off with the page: a page pushed over this one hides it
    BusyIndicator {
        parent: column1.parent
        anchors.centerIn: parent
        running: !column1.pageShown && column1.visible
        visible: running
    }

    // a new app language: the page asks for its texts again (no reload, it may be saving the charts)
    Connections {
        target: rootItem
        function onAppLanguageChanged() {
            webView.runJavaScript("window.qzRequestTranslations && window.qzRequestTranslations()")
        }
    }

    Timer {
        id: chartJscheckStartFromWeb
        // Not while the kept page is off the stack: its pop would close another page
        interval: 200; running: column1.visible; repeat: true
        onTriggered: {if(rootItem.startRequested) {rootItem.startRequested = false; rootItem.stopRequested = false; stackView.pop(); }}
    }

    Timer {
        id: sendMailFallback
        interval: 10000; running: true; repeat: false
        onTriggered: rootItem.sendMail()
    }

    // Modern look: no Close button at the bottom (the back arrow of the toolbar does it), the
    // page runs down to the edge like the other pages
    UiButton {
        id: closeButton
        visible: !window.ui.modern
        height: 50
        width: parent.width
        text: qsTr("Close")
        Layout.alignment: Qt.AlignCenter | Qt.AlignVCenter
        // nothing listens to popupclose(): back the same way as the toolbar arrow
        onClicked: {
            window.navigateBack(false);
        }
        anchors {
            bottom: parent.bottom
        }
    }
	 Component.onCompleted: {
	     headerToolbar.visible = true;
	     // Set once, not bound: the fragment is for the first load, a later theme goes
	     // through runJavaScript
	     sentTheme = JSON.stringify(pageTheme)
	     webView.url = pageUrl("")
	 }
}
