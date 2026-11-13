import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Controls.Material 2.12

// Progress of a long process with a known count: a line of text over a flat 4 dp bar, the
// filled part over a pale track of the same colour (no gap, no end dot). Shown only while
// total > 0. In an empty list it sits in the middle with its text; over a list that already
// shows rows it is the bar alone (compact) on the top edge, not over the rows.
Item {
    id: control

    property int done: 0
    property int total: 0
    property bool compact: false
    property string text: qsTr("Restoring files: %1 of %2").arg(done).arg(total)
    readonly property color barColor: window.ui.modern ? window.ui.accent : Material.accent

    visible: total > 0
    implicitHeight: compact ? bar.height : progressLabel.implicitHeight + 12 + bar.height

    Accessible.role: Accessible.ProgressBar
    Accessible.name: text

    Label {
        id: progressLabel
        visible: !control.compact
        width: parent.width
        text: control.text
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: window.ui.modern ? window.ui.textMuted : Material.foreground
        // read as the name of the bar
        Accessible.ignored: true
    }

    Item {
        id: bar
        anchors.bottom: parent.bottom
        width: parent.width
        height: 4

        Rectangle {
            anchors.fill: parent
            radius: 2
            color: control.barColor
            opacity: 0.24
        }

        Rectangle {
            // at least a round dot as soon as the first file is under way
            width: control.total > 0 ? Math.max(parent.height, parent.width * Math.min(control.done, control.total) / control.total) : 0
            height: parent.height
            radius: 2
            color: control.barColor
            Behavior on width { NumberAnimation { duration: 200 } }
        }
    }
}
