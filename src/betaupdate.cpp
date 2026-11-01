#include "betaupdate.h"

#ifdef Q_OS_ANDROID
#include <QAndroidJniEnvironment>
#include <QAndroidJniObject>
#include <QtAndroid>

static const char *JAVA_CLASS = "org/cagnulen/qdomyoszwift/BetaUpdate";

// A Java exception left pending makes the next JNI call abort the app
static void clearException() {
    QAndroidJniEnvironment env;
    if (env->ExceptionCheck()) {
        env->ExceptionDescribe();
        env->ExceptionClear();
    }
}
#endif

int BetaUpdate::downloadedBuild() {
#ifdef Q_OS_ANDROID
    jint build = QAndroidJniObject::callStaticMethod<jint>(JAVA_CLASS, "downloadedBuild", "(Landroid/content/Context;)I",
                                                           QtAndroid::androidContext().object());
    clearException();
    return build;
#else
    return 0;
#endif
}

int BetaUpdate::downloadProgress() {
#ifdef Q_OS_ANDROID
    jint percent = QAndroidJniObject::callStaticMethod<jint>(JAVA_CLASS, "downloadProgress", "(Landroid/content/Context;)I",
                                                             QtAndroid::androidContext().object());
    clearException();
    return percent;
#else
    return 0;
#endif
}

void BetaUpdate::cleanup(int installedBuild) {
#ifdef Q_OS_ANDROID
    QAndroidJniObject::callStaticMethod<void>(JAVA_CLASS, "cleanup", "(Landroid/content/Context;I)V",
                                              QtAndroid::androidContext().object(), (jint)installedBuild);
    clearException();
#else
    Q_UNUSED(installedBuild)
#endif
}

void BetaUpdate::download(const QString &url, int build, const QString &downloadTitle, const QString &doneTitle,
                          const QString &doneText) {
#ifdef Q_OS_ANDROID
    QAndroidJniObject::callStaticMethod<void>(
        JAVA_CLASS, "download",
        "(Landroid/content/Context;Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;)V",
        QtAndroid::androidContext().object(), QAndroidJniObject::fromString(url).object<jstring>(), (jint)build,
        QAndroidJniObject::fromString(downloadTitle).object<jstring>(),
        QAndroidJniObject::fromString(doneTitle).object<jstring>(),
        QAndroidJniObject::fromString(doneText).object<jstring>());
    clearException();
#else
    Q_UNUSED(url)
    Q_UNUSED(build)
    Q_UNUSED(downloadTitle)
    Q_UNUSED(doneTitle)
    Q_UNUSED(doneText)
#endif
}

bool BetaUpdate::install() {
#ifdef Q_OS_ANDROID
    jboolean opened = QAndroidJniObject::callStaticMethod<jboolean>(JAVA_CLASS, "install", "(Landroid/content/Context;)Z",
                                                                    QtAndroid::androidContext().object());
    clearException();
    return opened;
#else
    return false;
#endif
}
