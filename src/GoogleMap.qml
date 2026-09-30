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
    // Modern look, as ChartJsTest.qml: the page takes the app theme (maps.htm, qzApplyTheme)
    // from the URL fragment and through runJavaScript when it changes, and the native view
    // stays off the screen until the page has drawn (it is white before and lies over QML)
    readonly property var pageTheme: window.ui.webTheme
    property bool pageLoaded: false
    property bool pageShown: !window.ui.modern
    readonly property real offScreen: pageShown ? 0 : Screen.width + Screen.height

    onPageThemeChanged: {
        if (pageLoaded && pageTheme)
            webView.runJavaScript(window.ui.webThemeScript())
    }

    Settings {
        id: settings
        property string maps_type: "3D"
    }
    WebView {
        id: webView
        anchors.fill: parent
        anchors.leftMargin: -column1.offScreen
        anchors.rightMargin: column1.offScreen
        url: "http://localhost:" + settings.value("template_inner_QZWS_port") + "/" + (settings.value("maps_type") === "3D" ? "googlemaps" : "maps2d") + "/maps.htm" + window.ui.webThemeFragment()
        visible: true
        onLoadingChanged: {
            if (loadRequest.errorString)
                console.error(loadRequest.errorString);
            if (loadRequest.status === WebView.LoadSucceededStatus) {
                column1.pageLoaded = true
                revealTimer.start()
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
        running: !column1.pageShown
        visible: running
    }

    // Modern look: no Close button (nothing listens to popupclose; the back arrow of the
    // toolbar closes the page), the map runs down to the edge
    Button {
        id: closeButton
        visible: !window.ui.modern
        height: 50
        width: parent.width
        text: "Close"
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
     }
}
