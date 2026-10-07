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

    // Modern look: the page takes the app theme colours (chart.htm, qzApplyTheme) from the URL
    // fragment of the first load and through runJavaScript when the theme changes later
    readonly property var pageTheme: window.ui.webTheme
    property bool pageLoaded: false
    // Modern look: the native web view stays off the screen until the page has drawn once.
    // It is white before its first paint and lies over everything QML draws, so it flashed
    // white on the dark theme. Moved aside, not hidden: a hidden view has no size, the page
    // laid out for a wrong width and opened zoomed in
    property bool pageShown: !window.ui.modern
    readonly property real offScreen: pageShown ? 0 : Screen.width + Screen.height
    // A chart spread over the page (chartfullscreen.js): the page tells it in its title
    property bool chartFullscreen: false
    // The spread chart takes the app header's room too: the header folds to the status bar
    // inset as on the scrolled home page (hidden, it left the page under the status bar).
    // Back is the key or the collapse button of the chart then, the toolbar arrow folds away
    onChartFullscreenChanged: headerToolbar.scrolledAway = chartFullscreen

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
    // The new load is kept off the screen like the first one: the page showed its empty cards
    // and the alt text of the picture for a moment before the charts came
    function reopen() {
        headerToolbar.visible = true
        turnShow.stop()
        turnHidden = false
        if (pageLoaded) {
            if (window.ui.modern) {
                // Opened again before the last load showed: that poll and the rest of that
                // safety net are for the old page, both start over with the new load
                revealTimer.stop()
                pageShown = false
                revealSafety.restart()
            }
            webView.url = pageUrl("?still=" + Date.now())
        }
        sendMailFallback.restart()
    }

    // WORKAROUND: the Android WebView of Qt does not recover from a turn of the screen while the
    // page is shown. Scrolled down afterwards, it moves without momentum and leaves the page
    // blank below a straight line (up is fine). Seen on a OnePlus 12 in both looks; to see it:
    // open the charts upright, turn the phone, scroll down. Moving the native view off the
    // screen and back once the turn has settled brings it round, the page stays as it is.
    // Off at the turn of the screen: the page changes its size in steps after it, and a page
    // shown stretched to those steps flashed
    readonly property bool landscape: width > height
    readonly property bool screenLandscape: Screen.width > Screen.height
    // Moved off by a turn, back once the size settles
    property bool turnHidden: false
    onLandscapeChanged: turnStart()
    onScreenLandscapeChanged: turnStart()
    onWidthChanged: if (turnHidden) turnShow.restart()
    onHeightChanged: if (turnHidden) turnShow.restart()

    function turnStart() {
        if (turnHidden) {
            turnShow.restart()
            return
        }
        // Not loaded or not shown yet: the load shows the page when it has drawn
        if (!pageLoaded || !visible || !pageShown)
            return
        turnHidden = true
        pageShown = false
        turnShow.restart()
    }

    Timer {
        id: turnShow
        interval: 300
        onTriggered: {
            column1.turnHidden = false
            column1.pageShown = true
        }
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
        turnShow.stop()
        turnHidden = false
        column1.visible = false
    }

    onPageThemeChanged: {
        if (pageLoaded && pageTheme)
            webView.runJavaScript(window.ui.webThemeScript())
    }

    Settings {
        id: settings
    }
    WebView {
        id: webView
        anchors.fill: parent
        // The native view lies over everything QML draws: it goes with the page when kept
        visible: column1.visible
        // Modern look: no Close button at the bottom (the back arrow of the toolbar does
        // it), the page runs down to the edge like the other pages
        anchors.leftMargin: -column1.offScreen
        anchors.rightMargin: column1.offScreen
        onTitleChanged: column1.chartFullscreen = title.indexOf("#fullscreen") >= 0
        onLoadingChanged: {
            if (loadRequest.errorString) {
                console.error(loadRequest.errorString);
                console.error("port " + settings.value("template_inner_QZWS_port"));
            }
            if (loadRequest.status === WebView.LoadSucceededStatus) {
                column1.pageLoaded = true
                revealTimer.start()
                // A theme change during the load only moved the fragment: apply the current one
                if (column1.pageTheme)
                    webView.runJavaScript(window.ui.webThemeScript())
            }
        }
    }

    // Shown once the page has drawn: the charts made (they come after the session data over the
    // web socket) and the picture loaded. The end of the load alone came before both
    Timer {
        id: revealTimer
        interval: 100; repeat: true
        onTriggered: {
            if (column1.pageShown) {
                stop()
                return
            }
            webView.runJavaScript("(function () { var i = document.querySelector('.workout_image');" +
                                  " return typeof Chart !== 'undefined' && Object.keys(Chart.instances).length > 0 &&" +
                                  " (!i || i.complete); })()", function (drawn) {
                if (drawn)
                    column1.pageShown = true
            })
        }
    }

    // Safety net: a page that never reports the end of its load is shown anyway
    Timer {
        id: revealSafety
        interval: 4000; running: !column1.pageShown; repeat: false
        onTriggered: column1.pageShown = true
    }

    BusyIndicator {
        anchors.centerIn: parent
        // Not for a turn: nothing loads, the view is only off the screen for a moment
        running: !column1.pageShown && !column1.turnHidden
        visible: running
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

    UiButton {
        id: closeButton
        visible: !window.ui.modern
        height: 50
        width: parent.width
        text: qsTr("Close")
        Layout.alignment: Qt.AlignCenter | Qt.AlignVCenter
        onClicked: {
            popupclose();
        }
        anchors {
            bottom: parent.bottom
        }
    }
	 Component.onCompleted: {
	     headerToolbar.visible = true;
	     // Set once, not bound: the fragment follows the theme, and a new fragment would
	     // not reload the page anyway (the theme goes through runJavaScript then)
	     webView.url = pageUrl("")
	 }
}
