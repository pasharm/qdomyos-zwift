import QtQuick 2.7
import Qt.labs.folderlistmodel 2.15
import QtQuick.Layouts 1.3
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.0
import QtQuick.Dialogs 1.0

ColumnLayout {
    id: settingsListPage
    signal loadSettings(url name)

    // Modern look: a page title, a hint and the saved settings as cards (like the profile
    // list); a tap selects a file, a second tap or Load loads it

    Connections {
        target: rootItem
        function onAndroidDocumentPicked(kind, localUrl) {
            if (kind === "settings") {
                loadSettings(localUrl)
            }
        }
    }

    Loader {
        id: fileDialogLoader
        active: false
        sourceComponent: Component {
            FileDialog {
                title: qsTr("Please choose a file")
                folder: shortcuts.home
                visible: true
                onAccepted: {
                    console.log("You chose: " + fileUrl)
                    loadSettings(fileUrl)
                    close()
                    // Destroy and recreate the dialog for next use
                    fileDialogLoader.active = false
                }
                onRejected: {
                    console.log("Canceled")
                    close()
                    // Destroy the dialog
                    fileDialogLoader.active = false
                }
            }
        }
    }

    ColumnLayout {
        visible: window.ui.modern
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: window.ui.pageMargin
        Layout.rightMargin: window.ui.pageMargin
        spacing: 8

        Label {
            Layout.fillWidth: true
            text: qsTr("Settings folder")
            color: window.ui.textMain
            font.pixelSize: 22
            font.weight: Font.DemiBold
            topPadding: 12
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("Tap a file to select it, then Load.")
            color: window.ui.textMuted
            wrapMode: Text.WordWrap
        }

        ListView {
            id: modernList
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 4
            clip: true
            spacing: 8
            currentIndex: -1
            boundsBehavior: Flickable.StopAtBounds
            ScrollIndicator.vertical: ScrollIndicator {}

            FolderListModel {
                id: modernFolderModel
                nameFilters: ["*.qzs"]
                // Always the settings folder: an empty one makes FolderListModel watch the
                // working directory instead
                folder: "file://" + rootItem.getWritableAppDir() + 'settings'
                showDotAndDotDot: false
                showDirs: false
                sortReversed: true
            }
            model: window.ui.modern ? modernFolderModel : null

            function loadAt(i) {
                let fileUrl = modernFolderModel.get(i, 'fileUrl') || modernFolderModel.get(i, 'fileURL');
                if (fileUrl)
                    loadSettings(fileUrl);
            }

            // UiFrame, not Rectangle.border: a thin border breaks up on Android
            delegate: UiFrame {
                id: settingsCard
                readonly property bool selected: ListView.isCurrentItem
                width: ListView.view.width
                height: 60
                radius: window.ui.radius
                fill: selected ? window.ui.alpha(window.ui.accent, 0.14)
                               : (cardArea.pressed ? window.ui.surfaceHigh : window.ui.surface)
                strokeWidth: selected ? 1 : 0
                stroke: window.ui.alpha(window.ui.accent, 0.6)

                MouseArea {
                    id: cardArea
                    anchors.fill: parent
                    onClicked: {
                        if (index === modernList.currentIndex)
                            modernList.loadAt(index)
                        else
                            modernList.currentIndex = index
                    }
                }

                Rectangle {
                    id: settingsAvatar
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: 40
                    radius: 20
                    color: window.ui.surfaceHighest
                    UiIcon {
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        name: "settings"
                        color: settingsCard.selected ? window.ui.accent : window.ui.textMuted
                    }
                }

                Label {
                    anchors.left: settingsAvatar.right
                    anchors.leftMargin: 12
                    anchors.right: loadButton.visible ? loadButton.left : parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: fileName.substring(0, fileName.length-4)
                    color: settingsCard.selected ? window.ui.accent : window.ui.textMain
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                UiButton {
                    id: loadButton
                    visible: settingsCard.selected
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Load")
                    highlighted: true
                    onClicked: modernList.loadAt(index)
                }
            }

            Label {
                parent: modernList
                anchors.centerIn: parent
                // only once the folder is read: the model fills in asynchronously
                visible: modernList.count === 0 && modernFolderModel.status === FolderListModel.Ready
                text: qsTr("No saved settings")
                color: window.ui.textMuted
            }
        }
    }

    StaticAccordionElement {
        visible: !window.ui.modern
        title: qsTr("Settings folder")
        indicatRectColor: Material.color(Material.Grey)
        textColor: Material.color(Material.Grey)
        color: Material.backgroundColor
        accordionContent: ColumnLayout {
            ListView {
                id: list
                anchors.fill: parent
                FolderListModel {
                    id: folderModel
                    nameFilters: ["*.qzs"]
                    folder: "file://" + rootItem.getWritableAppDir() + 'settings'
                    showDotAndDotDot: false
                    showDirs: true
                    sortReversed: true
                }
                model: window.ui.modern ? null : folderModel
                delegate: Component {
                    Rectangle {
                        property alias textColor: fileTextBox.color
                        width: parent.width
                        height: 40
                        color: Material.backgroundColor
                        z: 1
                        Text {
                            id: fileTextBox
                            color: Material.color(Material.Grey)
                            font.pixelSize: Qt.application.font.pixelSize * 1.6
                            text: fileName.substring(0, fileName.length-4)
                            leftPadding: window.contentSideMargin
                        }
                        MouseArea {
                            anchors.fill: parent
                            z: 100
                            onClicked: {
                                console.log('onclicked ' + index+ " count "+list.count);
                                if (index == list.currentIndex) {
                                    let fileUrl = folderModel.get(list.currentIndex, 'fileUrl') || folderModel.get(list.currentIndex, 'fileURL');
                                    if (fileUrl) {
                                        loadSettings(fileUrl);
                                    }
                                }
                                else {
                                    if (list.currentItem)
                                        list.currentItem.textColor = Material.color(Material.Grey)
                                    list.currentIndex = index
                                }
                            }
                        }
                    }
                }
                highlight: Rectangle {
                    color: Material.color(Material.Green)
                    z:3
                    radius: 5
                    opacity: 0.4
                    focus: true
                    /*Text {
                        anchors.centerIn: parent
                        text: 'Selected ' + folderModel.get(list.currentIndex, "fileName")
                        color: "white"
                    }*/
                }
                focus: true
                onCurrentItemChanged: {
                    let fileUrl = folderModel.get(list.currentIndex, 'fileUrl') || folderModel.get(list.currentIndex, 'fileURL');
                    if (fileUrl) {
                        list.currentItem.textColor = window.ui.modern && !window.ui.dark ? window.ui.accent : Material.color(Material.Yellow)
                        console.log(fileUrl + ' selected');
                    }
                }
            }
        }
    }
    spacing: 10

    UiButton {
        id: searchButton
        height: window.ui.modern ? implicitHeight : 50
        width: window.ui.modern ? parent.width - 2 * window.ui.pageMargin : parent.width
        Layout.fillWidth: window.ui.modern
        Layout.leftMargin: window.ui.modern ? window.ui.pageMargin : 0
        Layout.rightMargin: window.ui.modern ? window.ui.pageMargin : 0
        Layout.bottomMargin: window.ui.modern ? 8 : 0
        text: qsTr("Other folders")
        Layout.alignment: Qt.AlignCenter | Qt.AlignVCenter
        onClicked: {
            console.log("folder is " + rootItem.getWritableAppDir() + 'settings')
            if (Qt.platform.os === "android") {
                rootItem.openAndroidDocumentPicker("settings")
            } else {
                fileDialogLoader.active = true
            }
        }
        anchors {
            bottom: parent.bottom
        }
    }
}
