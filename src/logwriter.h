// logwriter.h
#ifndef LOGWRITER_H
#define LOGWRITER_H

#include <QObject>
#include <QFile>
#include <QTextStream>

class LogWriter : public QObject {
    Q_OBJECT
public:
    explicit LogWriter(QObject *parent = nullptr);
    virtual ~LogWriter();

public slots:
    void writeLog(const QString &path, const QString &txt);

private:
    // kept open between lines: the handler logs dozens of lines per second
    QFile outFile;
    QTextStream ts;
};

#endif // LOGWRITER_H
