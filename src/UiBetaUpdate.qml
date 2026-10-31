import QtQuick 2.12
import Qt.labs.platform 1.1

// personal: the question about a newer build, only in the builds of feat/modern-beta. At launch,
// once, on Android: the newest release of the fork against the number of this build. The browser
// opens the APK and Android installs it, so QZ needs no permission for that.
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

    text: qsTr("New QZ build")
    informativeText: qsTr("Build %1 is available, you have build %2.\nDownload the APK?").arg(newBuild).arg(buildNumber)
    buttons: (MessageDialog.Yes | MessageDialog.No)
    yesText: qsTr("Download")
    noText: qsTr("Later")
    onYesClicked: Qt.openUrlExternally(apkUrl)

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
                // The wizard of the first run stands over the home page
                if (!rootItem.firstRun())
                    open()
                return
            }
        }
    }

    Component.onCompleted: {
        if (buildNumber === 0 || Qt.platform.os !== "android")
            return
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
}
