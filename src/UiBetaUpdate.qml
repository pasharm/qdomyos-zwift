import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Controls.Material 2.12
import Qt.labs.platform 1.1

// personal: the question about a newer build, only in the builds of feat/modern-beta. At launch,
// once, on Android: a downloaded build newer than this one is offered for install at once, without
// the network; otherwise the newest release of the fork against the number of this build.
// "Download" hands the APK to the download manager of Android (betaUpdate, BetaUpdate.java): while
// it runs QZ watches it and asks again when it ends ("Install" opens the installer of Android, which
// ends QZ: not opened by itself, a workout may be running); in the background a notification asks.
// The strip at the bottom shows the percent of the download; a tap hides it, the download goes on.
// Launch only: QZ starts counting a workout by itself, a late answer must not cover it.
UiMessageDialog {
    id: root

    // The Android job of main.yml writes the run number here on feat/modern-beta.
    // 0: a build of another branch, it does not check
    readonly property int buildNumber: 0
    readonly property string releaseUrl: "https://api.github.com/repos/pasharm/qdomyos-zwift/releases/latest"
    readonly property int answerLimitMs: 15000

    property int newBuild: 0
    property string apkUrl: ""
    // The APK of newBuild is downloaded already: the answer installs it
    property bool downloaded: false
    property int downloadPercent: 0
    property bool stripHidden: false

    text: qsTr("New QZ build")
    informativeText: downloaded
                     ? qsTr("Build %1 is downloaded, you have build %2.\nInstall it?").arg(newBuild).arg(buildNumber)
                     : qsTr("Build %1 is available, you have build %2.\nDownload the APK?").arg(newBuild).arg(buildNumber)
    buttons: (MessageDialog.Yes | MessageDialog.No)
    yesText: downloaded ? qsTr("Install") : qsTr("Download")
    noText: qsTr("Later")
    onYesClicked: {
        if (downloaded) {
            betaUpdate.install()
        } else {
            betaUpdate.download(apkUrl, newBuild, qsTr("QZ build %1").arg(newBuild), qsTr("New QZ build"),
                                qsTr("Build %1 is downloaded, tap to install").arg(newBuild))
            downloadWatch.start()
        }
    }

    // A download is running: its end is asked about on the screen
    function readDownload() {
        var ready = betaUpdate.downloadedBuild()
        if (ready === -1) {
            downloadPercent = betaUpdate.downloadProgress()
            return
        }
        downloadWatch.stop()
        if (ready > buildNumber) {
            newBuild = ready
            downloaded = true
            offer()
        } else {
            console.log("beta update: the download did not finish")
        }
    }

    Timer {
        id: downloadWatch
        interval: 2000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            try {
                root.readDownload()
            } catch (e) {
                stop()
                console.log("beta update: " + e)
            }
        }
    }

    // Not modal: the page around it stays usable, and the bottom is where the notices of
    // UiNotice stand, above the navigation bar
    UiPopup {
        id: downloadStrip
        readonly property string label: qsTr("Downloading the QZ build: %1%").arg(root.downloadPercent)
        readonly property color ink: modern ? window.ui.bg : Material.foreground

        parent: Overlay.overlay
        visible: downloadWatch.running && !root.stripHidden && !rootItem.firstRun()
        inverse: true
        closePolicy: Popup.NoAutoClose
        x: Math.round((parent.width - width) / 2)
        y: parent.height - height - 24 - window.getBottomPadding()
        width: Math.min(parent.width - 32, 560)
        leftPadding: 20
        rightPadding: 20
        topPadding: 12
        bottomPadding: 12

        contentItem: Item {
            implicitHeight: stripColumn.implicitHeight

            Column {
                id: stripColumn
                width: parent.width
                spacing: 8

                Label {
                    width: parent.width
                    text: downloadStrip.label
                    wrapMode: Text.WordWrap
                    color: downloadStrip.ink
                    font.pixelSize: window.ui.fontLabel
                }

                Item {
                    width: parent.width
                    height: 4

                    Rectangle {
                        anchors.fill: parent
                        radius: 2
                        color: downloadStrip.ink
                        opacity: 0.3
                    }

                    Rectangle {
                        width: parent.width * root.downloadPercent / 100
                        height: parent.height
                        radius: 2
                        color: downloadStrip.ink
                        Behavior on width { NumberAnimation { duration: 500 } }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.stripHidden = true
                Accessible.role: Accessible.Button
                Accessible.name: downloadStrip.label
                Accessible.onPressAction: root.stripHidden = true
            }
        }
    }

    function offer() {
        // The wizard of the first run stands over the home page
        if (!rootItem.firstRun())
            open()
    }

    function readAnswer(answer) {
        var release = JSON.parse(answer)
        var name = release.tag_name.split("-")
        if (name.length !== 2 || name[0] !== "beta" || !(parseInt(name[1]) > buildNumber))
            return
        for (var i = 0; i < release.assets.length; i++) {
            var url = release.assets[i].browser_download_url
            if (url.endsWith(".apk")) {
                newBuild = parseInt(name[1])
                apkUrl = url
                offer()
                return
            }
        }
    }

    function check() {
        betaUpdate.cleanup(buildNumber)
        var ready = betaUpdate.downloadedBuild()
        if (ready > buildNumber) {
            newBuild = ready
            downloaded = true
            offer()
            return
        }
        // A download is running, started before a restart of QZ
        if (ready === -1) {
            downloadWatch.start()
            return
        }
        var started = Date.now()
        var request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE)
                return
            if (request.status !== 200 || Date.now() - started > answerLimitMs) {
                console.log("beta update: no answer in time, status " + request.status)
                return
            }
            try {
                readAnswer(request.responseText)
            } catch (e) {
                console.log("beta update: " + e)
            }
        }
        request.open("GET", releaseUrl)
        request.send()
    }

    // rootItem comes from C++ only after main.qml is loaded (main.cpp): the check waits for it,
    // as the wizard of the first run does (Home.qml)
    Timer {
        interval: 300
        running: root.buildNumber !== 0 && Qt.platform.os === "android" && typeof betaUpdate !== "undefined"
        onTriggered: {
            try {
                root.check()
            } catch (e) {
                console.log("beta update: " + e)
            }
        }
    }
}
