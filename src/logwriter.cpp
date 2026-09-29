#include "logwriter.h"
#include <QDir>
#include <QFileInfo>

LogWriter::LogWriter(QObject *parent) : QObject(parent) {
}

LogWriter::~LogWriter() {
    ts.flush();
    outFile.close();
}

void LogWriter::writeLog(const QString &path, const QString &txt) {
    if (!outFile.isOpen() || outFile.fileName() != path) {
        ts.setDevice(nullptr);
        outFile.close();
        outFile.setFileName(path);
        if (!outFile.open(QIODevice::WriteOnly | QIODevice::Append)) {
            // the folder may not exist yet (it used to be created for every line): create it and try again,
            // and if it still fails try again with the next line
            QDir().mkpath(QFileInfo(path).absolutePath());
            outFile.open(QIODevice::WriteOnly | QIODevice::Append);
        }
        if (outFile.isOpen())
            ts.setDevice(&outFile);
    }
    if (outFile.isOpen()) {
        ts << txt;
        // flushed for every line as before (the file was closed after each one), so a crash or a log
        // attached while the app runs has every line
        ts.flush();
    }
    fprintf(stderr, "%s", txt.toLocal8Bit().constData());
}
