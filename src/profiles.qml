import QtQuick 2.12
import QtQuick.Layouts 1.3
import QtQuick.Controls 2.5
import QtQuick.Controls.Material 2.12
import Qt.labs.platform 1.1
import Qt.labs.folderlistmodel 2.15
import Qt.labs.settings 1.0
import QtQuick.Dialogs 1.0 as FileDialogClass

ColumnLayout {

    anchors.top: parent.top
    anchors.fill: parent

    signal profile_open_clicked(url name)

    Connections {
        target: rootItem
        function onAndroidDocumentPicked(kind, localUrl) {
            if (kind === "profile") {
                profile_open_clicked(localUrl)
            }
        }
    }

    Settings {
        id: settings
        property string profile_name: "default"
    }

    Loader {
        id: fileDialogLoader
        active: false
        sourceComponent: Component {
            FileDialogClass.FileDialog {
                title: qsTr("Please choose a file")
                folder: shortcuts.home
                visible: true
                onAccepted: {
                    console.log("You chose: " + fileUrl)
                    profile_open_clicked(fileUrl)
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

    UiMessageDialog {
        id: quitDialog
        title: qsTr("Profile loaded")
        text: qsTr("Would you like to quit?")
        informativeText: qsTr("You must quit and restart for changes to take effect.")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: {
            restart()
        }
        onNoClicked: {
            quitDialog.close()
        }
    }

    UiMessageDialog {
        id: deleteDialog
        property string fileUrl
        title: qsTr("Delete profile")
        text: qsTr("Would you like to delete this profile?")
        buttons: (MessageDialog.Yes | MessageDialog.No)
        onYesClicked: {
            deleteSettings(fileUrl)
        }
        onNoClicked: {
            deleteDialog.close()
        }
    }

    UiMessageDialog {
        id: saveDialog
        title: qsTr("Profile Saved")
        text: qsTr("Profile saved correctly!")
        buttons: (MessageDialog.Ok)
        onOkClicked: {
            stackView.pop();
        }
    }

    UiMessageDialog {
        id: restoreSettingsDialog
        title: qsTr("New Profile")
        text: qsTr("New Profile Created with default values. Save it with a name and restart the app to apply them.")
        buttons: (MessageDialog.Ok)
        onOkClicked: {
            restoreSettingsDialog.visible = false
        }
    }

    UiMessageDialog {
        id: newProfileDialog
        title: qsTr("Save Current Profile?")
        text: qsTr("You're creating a new profile with the default values, would you like to save the current one before?")
        buttons: (MessageDialog.Yes | MessageDialog.No | MessageDialog.Abort)
        onYesClicked: {
                if(profileNameTextField.text.length == 0)
                    profileNameTextField.text = qsTr("OldProfile")

            saveProfile(profileNameTextField.text);
            restoreSettings()

            newProfileDialog.visible = false;
            restoreSettingsDialog.visible = true
        }
        onNoClicked: {
            restoreSettings()
            newProfileDialog.visible = false;
            restoreSettingsDialog.visible = true
        }
        onAbortClicked: {
            newProfileDialog.visible = false;
        }
    }

    function loadProfileAt(i) {
        let fileUrl = folderModel.get(i, 'fileUrl') || folderModel.get(i, 'fileURL');
        if (fileUrl) {
            loadSettings(fileUrl);
            quitDialog.visible = true
        }
    }

    function askDeleteProfileAt(i) {
        let name = folderModel.get(i, 'fileName')
        deleteDialog.informativeText = name.substring(0, name.length-4)
        deleteDialog.fileUrl = folderModel.get(i, 'fileUrl') || folderModel.get(i, 'fileURL')
        deleteDialog.visible = true
    }

    // Modern look: a card with the name and the save buttons, the profiles as a list of
    // cards (tap selects, Load or a second tap loads, long press deletes). Same model and
    // dialogs as the classic layout below, which is hidden.
    readonly property int modernMargin: Math.max(16, window.contentSideMargin)

    Rectangle {
        visible: window.ui.modern
        Layout.fillWidth: true
        Layout.leftMargin: modernMargin
        Layout.rightMargin: modernMargin
        Layout.topMargin: 12
        implicitHeight: modernNameColumn.implicitHeight + 32
        radius: 20
        color: window.ui.surface

        ColumnLayout {
            id: modernNameColumn
            anchors.fill: parent
            anchors.margins: 16
            spacing: 4

            Label {
                text: qsTr("Profile name")
                color: window.ui.textMuted
                font.pixelSize: 13
            }
            UiTextField {
                id: modernNameField
                Layout.fillWidth: true
                text: settings.profile_name
                font.pixelSize: 18
                onAccepted: settings.profile_name = text
                onActiveFocusChanged: if (activeFocus) cursorPosition = text.length
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                UiButton {
                    text: qsTr("New profile")
                    flat: true
                    onClicked: {
                        profileNameTextField.text = modernNameField.text
                        newProfileDialog.visible = true;
                    }
                }
                UiButton {
                    text: qsTr("Save")
                    highlighted: true
                    onClicked: {
                        profileNameTextField.text = modernNameField.text
                        saveProfile(modernNameField.text);
                        saveDialog.visible = true;
                    }
                }
            }
        }
    }

    Label {
        visible: window.ui.modern
        Layout.fillWidth: true
        Layout.leftMargin: modernMargin + 4
        Layout.rightMargin: modernMargin
        Layout.topMargin: 12
        text: qsTr("Saved profiles")
        color: window.ui.textMain
        font.pixelSize: 16
        font.weight: Font.DemiBold
    }
    Label {
        visible: window.ui.modern
        Layout.fillWidth: true
        Layout.leftMargin: modernMargin + 4
        Layout.rightMargin: modernMargin
        text: qsTr("Tap a profile to select it, then Load. Long press to delete it.")
        color: window.ui.textMuted
        font.pixelSize: 13
        wrapMode: Text.WordWrap
    }

    ListView {
        id: modernList
        visible: window.ui.modern
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: modernMargin
        Layout.rightMargin: modernMargin
        Layout.topMargin: 4
        clip: true
        spacing: 8
        currentIndex: -1
        model: folderModel
        boundsBehavior: Flickable.StopAtBounds

        // UiFrame, not Rectangle.border: a thin border breaks up on Android
        delegate: UiFrame {
            id: profileCard
            readonly property bool selected: ListView.isCurrentItem
            readonly property string profileName: fileName.substring(0, fileName.length-4)
            readonly property bool active: profileName === settings.profile_name
            width: ListView.view.width
            height: 64
            radius: 16
            fill: selected ? window.ui.alpha(window.ui.accent, 0.14)
                           : (cardArea.pressed ? window.ui.surfaceHigh : window.ui.surface)
            strokeWidth: selected ? 1 : 0
            stroke: window.ui.alpha(window.ui.accent, 0.6)

            MouseArea {
                id: cardArea
                anchors.fill: parent
                onClicked: {
                    // as in the classic list: the user picked, a rescan must not reset it
                    list.clicked = true
                    if (index === modernList.currentIndex)
                        loadProfileAt(index)
                    else
                        modernList.currentIndex = index
                }
                onPressAndHold: askDeleteProfileAt(index)
            }

            Rectangle {
                id: avatar
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 40
                radius: 20
                color: profileCard.active ? window.ui.accent : window.ui.surfaceHighest
                UiIcon {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    name: "person"
                    color: profileCard.active ? window.ui.accentInk : window.ui.textMuted
                }
            }

            Column {
                anchors.left: avatar.right
                anchors.leftMargin: 12
                anchors.right: loadButton.visible ? loadButton.left : parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Label {
                    width: parent.width
                    text: profileCard.profileName
                    color: profileCard.selected ? window.ui.accent : window.ui.textMain
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Label {
                    visible: profileCard.active
                    text: qsTr("Active")
                    color: window.ui.textMuted
                    font.pixelSize: 12
                }
            }

            UiButton {
                id: loadButton
                visible: profileCard.selected
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Load")
                highlighted: true
                onClicked: loadProfileAt(index)
            }
        }
    }

    UiButton {
        visible: window.ui.modern
        Layout.fillWidth: true
        Layout.leftMargin: modernMargin
        Layout.rightMargin: modernMargin
        Layout.bottomMargin: 8
        text: qsTr("Other folders")
        onClicked: {
            if (Qt.platform.os === "android") {
                rootItem.openAndroidDocumentPicker("profile")
            } else {
                fileDialogLoader.active = true
            }
        }
    }

    RowLayout {
        visible: !window.ui.modern
        spacing: 10
        Layout.leftMargin: window.contentSideMargin
        Layout.rightMargin: window.contentSideMargin
        Label {
            id: labelProfileName
            text: qsTr("Profile name")
            Layout.fillWidth: true
        }
        UiTextField {
            id: profileNameTextField
            text: settings.profile_name
            horizontalAlignment: Text.AlignRight
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            onAccepted: settings.profile_name = text
            onActiveFocusChanged: if(this.focus) this.cursorPosition = this.text.length
        }
        Button {
            id: addProfileButton
            text: "+"
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            onClicked: {
                console.log("folder is " + rootItem.getWritableAppDir() + 'profiles')
                newProfileDialog.visible = true;
            }
        }
        Button {
            id: saveProfileNameButton
            text: qsTr("Save")
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            onClicked: {
                console.log("folder is " + rootItem.getWritableAppDir() + 'profiles')
                saveProfile(profileNameTextField.text);
                saveDialog.visible = true;
            }
        }
    }

    StaticAccordionElement {
        visible: !window.ui.modern
        title: qsTr("Profiles")
        indicatRectColor: Material.color(Material.Grey)
        textColor: Material.color(Material.Grey)
        color: Material.backgroundColor
        isOpen: true        
        accordionContent: ColumnLayout {
            ListView {
                id: list
                property bool clicked: false
                anchors.fill: parent
                FolderListModel {
                    id: folderModel
                    nameFilters: ["*.qzs"]
                    folder: "file://" + rootItem.getProfileDir()
                    showDotAndDotDot: false
                    showDirs: false
                    sortReversed: true
                    onStatusChanged: {
                        if(folderModel.status ==
                                FolderListModel.Ready && list.clicked == false) {
                            for(var i=0; i<folderModel.count; i++) {
                                if(folderModel.get(i,
                                                   "fileBaseName") === settings.profile_name) {
                                    list.currentIndex = i;
                                    modernList.currentIndex = i;
                                    return;
                                }
                            }
                        }
                    }
                    Component.onCompleted: {
                        // on Windows it doesn't update the folder
                        folderModel.folder = "file://" + rootItem.getProfileDir();
                    }
                }
                model: folderModel
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
                                list.clicked = true;
                                console.log('onclicked ' + index+ " count "+list.count);
                                if (index == list.currentIndex) {
                                    let fileUrl = folderModel.get(list.currentIndex, 'fileUrl') || folderModel.get(list.currentIndex, 'fileURL');
                                    if (fileUrl) {
                                        loadSettings(fileUrl);
                                        quitDialog.visible = true
                                    }
                                }
                                else {
                                    if (list.currentItem)
                                        list.currentItem.textColor = Material.color(Material.Grey)
                                    list.currentIndex = index
                                }
                            }
                            onPressAndHold: {
                                list.clicked = true;
                                console.log('onPressAndHold ' + index+ " count "+list.count);
                                deleteDialog.informativeText = folderModel.get(index, 'fileName').substring(0, fileName.length-4)
                                deleteDialog.fileUrl = folderModel.get(index, 'fileUrl') || folderModel.get(index, 'fileURL')
                                deleteDialog.visible = true
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
                        for(var i=0; i<folderModel.count; i++) {
                            list.itemAtIndex(i).textColor = Material.color(Material.Grey)
                        }
                        list.currentItem.textColor = window.ui.modern && !window.ui.dark ? window.ui.accent : Material.color(Material.Yellow)
                        console.log(fileUrl + ' selected');
                    }
                }
            }
        }
    }

    Button {
        id: searchButton
        visible: !window.ui.modern
        height: 50
        width: parent.width
        text: qsTr("Other folders")
        Layout.alignment: Qt.AlignCenter | Qt.AlignVCenter
        onClicked: {
            console.log("folder is " + rootItem.getWritableAppDir() + 'training')
            if (Qt.platform.os === "android") {
                rootItem.openAndroidDocumentPicker("profile")
            } else {
                fileDialogLoader.active = true
            }
        }
        anchors {
            bottom: parent.bottom
        }
    }
}
