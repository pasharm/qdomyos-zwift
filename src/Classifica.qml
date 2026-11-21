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
    Settings {
        id: settings
    }
    WebView {
        id: webView
        anchors.fill: parent
        // Off the screen while the drawer is open or dragged: the native view lies over it (QTBUG-58365).
        // Moved, not hidden: a hidden native view loses its surface (see ChartJsTest.qml).
        // As far as offScreen there: the page slides in from half its width while the drawer closes
        anchors.leftMargin: drawer.position === 0 ? 0 : -(Screen.width + Screen.height)
        anchors.rightMargin: drawer.position === 0 ? 0 : Screen.width + Screen.height
        url: "http://80.211.67.253:3001/qz-classifica"
        visible: true
        onLoadingChanged: {
            if (loadRequest.errorString)
                console.error(loadRequest.errorString);
        }
    }

    Button {
        id: closeButton
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
     }
}
