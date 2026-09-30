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

    // Modern look: the page is kept (main.qml) and opened again: the charts of the workout so
    // far are drawn anew, and the mail goes as on a fresh open. Drawn at once ("still" in the
    // query, chart.htm): growing from zero again every block looked like a redraw. A new query
    // loads the page anew, the fragment keeps the current theme
    // The new load is kept off the screen like the first one: the page showed its empty cards
    // and the alt text of the picture for a moment before the charts came
    function reopen() {
        headerToolbar.visible = true
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

    function pageUrl(query) {
        return "http://localhost:" + settings.value("template_inner_QZWS_port") + "/chartjs/chart.htm" +
               query + window.ui.webThemeFragment()
    }
    // A kept page is taken off the stack, not destroyed: hidden until pushed again
    // (and the mail timer stopped: a page destroyed before its 10 s sent nothing)
    StackView.onRemoved: {
        sendMailFallback.stop()
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
        // it), the page runs down to the edge like the other pages. Held sideways the page
        // stack does not keep clear of the gesture bar (main.qml), so the page does
        anchors.bottomMargin: window.ui.modern && (Screen.orientation === Qt.LandscapeOrientation ||
                                                   Screen.orientation === Qt.InvertedLandscapeOrientation)
                              ? window.getBottomPadding() : 0
        anchors.leftMargin: -column1.offScreen
        anchors.rightMargin: column1.offScreen
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
        running: !column1.pageShown
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
