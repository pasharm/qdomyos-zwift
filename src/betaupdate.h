#ifndef BETAUPDATE_H
#define BETAUPDATE_H

#include <QObject>
#include <QString>

// personal: the bridge from UiBetaUpdate.qml to BetaUpdate.java (feat/modern-beta only). Android only,
// elsewhere it does nothing and has no download.
class BetaUpdate : public QObject {
    Q_OBJECT

  public:
    explicit BetaUpdate(QObject *parent = nullptr) : QObject(parent) {}

    // The build of a finished download, -1 while it runs, 0 if there is none
    Q_INVOKABLE int downloadedBuild();
    // Percent of the running download, 0 while its size is not known
    Q_INVOKABLE int downloadProgress();
    // Removes the download of the installed build or of an older one
    Q_INVOKABLE void cleanup(int installedBuild);
    // The texts are translated in QML: the download notification, then the one of a download
    // that ended while QZ was in the background
    Q_INVOKABLE void download(const QString &url, int build, const QString &downloadTitle,
                              const QString &doneTitle, const QString &doneText);
    // Opens the installer of Android; false if there is no downloaded build
    Q_INVOKABLE bool install();
};

#endif // BETAUPDATE_H
