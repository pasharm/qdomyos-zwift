#include "qdebugfixup.h"
#ifdef Q_OS_ANDROID
#include "keepawakehelper.h"
#include "qzsettings.h"

KeepAwakeHelper::KeepAwakeHelper() {
    QSettings settings;
    ant = 0;
    bool wake = settings.value(QZSettings::android_wakelock, QZSettings::default_android_wakelock).toBool();
    if (!wake) {
        return;
    }

    activity = QAndroidJniObject::callStaticObjectMethod("org/qtproject/qt5/android/QtNative", "activity",
                                                         "()Landroid/app/Activity;");

    // Only the window flag, no wake lock: it keeps the screen on while QZ is visible. A screen wake lock
    // held in the background gets QZ killed on OnePlus.
    m_keepScreenOn = true;
    keepScreenOn(true);

    /*antObject(true);
    KeepAwakeHelper::antObject(true)->callMethod<void>("antStart","(Landroid/app/Activity;)V",
    activity.object<jobject>());*/
}

void KeepAwakeHelper::keepScreenOn(bool on) {
    QtAndroid::runOnAndroidThread([on] {
        QAndroidJniObject activity = QtAndroid::androidActivity();
        if (activity.isValid()) {
            QAndroidJniObject window = activity.callObjectMethod("getWindow", "()Landroid/view/Window;");

            if (window.isValid()) {
                const int FLAG_KEEP_SCREEN_ON = 128;
                if (on) {
                    window.callMethod<void>("addFlags", "(I)V", FLAG_KEEP_SCREEN_ON);
                    qDebug() << "Activated : Keep screen ON";
                } else {
                    window.callMethod<void>("clearFlags", "(I)V", FLAG_KEEP_SCREEN_ON);
                    qDebug() << "Deactivated : Keep screen ON";
                }
            }
        }
        QAndroidJniEnvironment env;
        if (env->ExceptionCheck()) {
            env->ExceptionClear();
        }
    });
}

int KeepAwakeHelper::heart() {
    int heart = KeepAwakeHelper::antObject(true)->callMethod<int>("getHeart", "()I");
    qDebug() << "antHeart:" << heart;
    return heart;
}

QAndroidJniObject *KeepAwakeHelper::antObject(bool forceCreate) {
    if (!ant && forceCreate)
        ant = new QAndroidJniObject("org/cagnulen/qdomyoszwift/Ant");
    return ant;
}

KeepAwakeHelper::~KeepAwakeHelper() {
    if (m_keepScreenOn) {
        QSettings settings;
        if ((settings.value(QZSettings::ant_cadence, QZSettings::default_ant_cadence).toBool() || settings.value(QZSettings::ant_heart, QZSettings::default_ant_heart).toBool()) &&
            KeepAwakeHelper::antObject(false))
            KeepAwakeHelper::antObject(false)->callMethod<void>("doUnbindChannelService", "()V");

        keepScreenOn(false);
    }
}

#endif
