import QtQuick 2.7
import QtQuick.Window 2.2

// WORKAROUND: the Android WebView of Qt does not recover from a turn of the screen while the
// page is shown. Turned from upright to landscape it kept an empty band at the bottom and the
// page scrolled down into it, or scrolled without momentum and stayed blank below a straight
// line. Seen on a OnePlus 12 in both looks: the charts, the workout history, the workout editor,
// the preview of a training program. Moving the native view off the screen and back once the
// turn has settled brings it round; the page stays as it is.
// The page moves its WebView by `shift` (anchors.leftMargin: -shift, anchors.rightMargin: shift)
// and says when it may: `active` (loaded and shown). Not a size: the layouts skip it.
// ChartJsTest.qml does the same with its own copy, as PR #5265 has it upstream.
Item {
    id: turnFix
    visible: false

    // The item that changes its size with the screen (the page or the box of the view)
    property Item area: parent
    // Loaded and shown: a page still loading is shown by its load when it has drawn
    property bool active: true
    // Off the screen for a moment after a turn
    property bool hidden: false
    readonly property real shift: hidden ? Screen.width + Screen.height : 0

    readonly property bool landscape: area ? area.width > area.height : false
    readonly property bool screenLandscape: Screen.width > Screen.height
    onLandscapeChanged: start()
    onScreenLandscapeChanged: start()

    // The page changes its size in steps after the turn: back once they stop, a view shown
    // stretched to those steps flashed
    Connections {
        target: turnFix.area
        function onWidthChanged() { if (turnFix.hidden) settle.restart() }
        function onHeightChanged() { if (turnFix.hidden) settle.restart() }
    }

    function start() {
        if (hidden) {
            settle.restart()
            return
        }
        if (!active)
            return
        hidden = true
        settle.restart()
    }

    // The page leaves: no view left off the screen for the next time
    function reset() {
        settle.stop()
        hidden = false
    }

    Timer {
        id: settle
        interval: 300
        onTriggered: turnFix.hidden = false
    }
}
