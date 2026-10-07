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

    // Modern look: the page takes the app theme colours (previewchart/chart.htm, qzApplyTheme)
    // from the URL fragment of the first load and through runJavaScript on a later change
    readonly property var pageTheme: window.ui.webTheme
    property bool pageLoaded: false
    // Modern look: the native web view stays off the screen until the page has drawn once.
    // It is white before its first paint and lies over everything QML draws, so it flashed
    // white on the dark theme. Moved aside, not hidden: a hidden view has no size, the page
    // laid out for a wrong width and opened zoomed in
    property bool pageShown: !window.ui.modern
    readonly property real offScreen: pageShown ? 0 : Screen.width + Screen.height
    // A chart spread over the page (chartjs/chartfullscreen.js): the page tells it in its title
    property bool chartFullscreen: false
    // The spread chart takes the app header's room too, as on the charts page
    onChartFullscreenChanged: headerToolbar.scrolledAway = chartFullscreen
    // Left with a spread chart (a start from the web page pops it): the header for the next page
    StackView.onRemoved: handleBack()

    // WORKAROUND: the Android WebView of Qt does not recover from a turn of the screen while the
    // page is shown: turned from upright to landscape, the page got an empty band at the bottom
    // and scrolled down into it, the spread chart too (OnePlus 12). The same as on the charts
    // page and done the same way (ChartJsTest.qml, PR #5265): the native view goes off the
    // screen at the turn and comes back once the size has settled. Kept as a copy until #5265
    // is in: ChartJsTest.qml stays as the PR has it, then both can share one component
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

    // Back (the key; in the modern look also the arrow of the toolbar, main.qml navigateBack)
    // closes the spread chart first instead of the page, as on the charts page (ChartJsTest.qml)
    function handleBack() {
        if (!chartFullscreen)
            return false
        chartFullscreen = false
        webView.runJavaScript("window.qzChartFullscreen && window.qzChartFullscreen.exit()")
        return true
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

    Timer {
        id: revealTimer
        interval: 150; repeat: false
        onTriggered: column1.pageShown = true
    }

    // Safety net: a page that never reports the end of its load is shown anyway
    Timer {
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
        interval: 200; running: true; repeat: true
        onTriggered: {if(rootItem.startRequested) {rootItem.startRequested = false; rootItem.stopRequested = false; stackView.pop(); }}
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
         // Set once, not bound: a new fragment would not reload the page anyway (the theme
         // goes through runJavaScript then)
         webView.url = "http://localhost:" + settings.value("template_inner_QZWS_port") + "/previewchart/chart.htm" + window.ui.webThemeFragment()
     }
}
