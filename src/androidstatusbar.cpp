#include "androidstatusbar.h"
#include <QQmlEngine>
#include <QDebug>
#include <QColor>
#include <QGuiApplication>
#include <QFont>

#ifdef Q_OS_ANDROID
#include <QtAndroid>
#include <QAndroidJniEnvironment>
#endif
#ifdef Q_OS_IOS
#include "ios/lockscreen.h"
#endif

AndroidStatusBar* AndroidStatusBar::m_instance = nullptr;

AndroidStatusBar::AndroidStatusBar(QObject *parent) : QObject(parent)
{
    m_instance = this;
}

AndroidStatusBar* AndroidStatusBar::instance()
{
    return m_instance;
}

void AndroidStatusBar::registerQmlType()
{
    qmlRegisterSingletonType<AndroidStatusBar>("AndroidStatusBar", 1, 0, "AndroidStatusBar",
        [](QQmlEngine *engine, QJSEngine *scriptEngine) -> QObject* {
            Q_UNUSED(engine)
            Q_UNUSED(scriptEngine)
            return new AndroidStatusBar();
        });
}

int AndroidStatusBar::apiLevel() const
{
#ifdef Q_OS_ANDROID
    return QAndroidJniObject::callStaticMethod<jint>("org/cagnulen/qdomyoszwift/CustomQtActivity", "getApiLevel", "()I");
#else
    return 0;
#endif
}

double AndroidStatusBar::systemFontScale() const
{
#ifdef Q_OS_ANDROID
    QAndroidJniObject context = QtAndroid::androidContext();
    if (!context.isValid())
        return 1.0;
    QAndroidJniObject resources = context.callObjectMethod("getResources", "()Landroid/content/res/Resources;");
    QAndroidJniObject configuration = resources.isValid()
        ? resources.callObjectMethod("getConfiguration", "()Landroid/content/res/Configuration;")
        : QAndroidJniObject();
    QAndroidJniEnvironment env;
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        return 1.0;
    }
    if (!configuration.isValid())
        return 1.0;
    const jfloat scale = configuration.getField<jfloat>("fontScale");
    return scale > 0 ? scale : 1.0;
#elif defined(Q_OS_IOS) && !defined(IO_UNDER_QT)
    return lockscreen::systemFontScale();
#elif defined(Q_OS_IOS)
    // The qmake build has no ios/lockscreen.mm (IO_UNDER_QT). Qt gives the app font the size of the
    // body text, 17 at the default system text size: the same scale, read when QZ starts
    const QFont font = QGuiApplication::font();
    const double size = font.pixelSize() > 0 ? font.pixelSize() : font.pointSizeF();
    return size > 0 ? size / 17.0 : 1.0;
#else
    return 1.0;
#endif
}

bool AndroidStatusBar::systemDarkMode() const
{
#ifdef Q_OS_ANDROID
    // The dark theme of the system came with Android 10 (API 29). Before it the night bit is
    // usually "not night" on phones and gym consoles alike, and following it would turn the page
    // light, while the look these users know is the dark classic one.
    if (apiLevel() < 29)
        return true;
    QAndroidJniObject context = QtAndroid::androidContext();
    if (!context.isValid())
        return true;
    QAndroidJniObject resources = context.callObjectMethod("getResources", "()Landroid/content/res/Resources;");
    QAndroidJniObject configuration = resources.isValid()
        ? resources.callObjectMethod("getConfiguration", "()Landroid/content/res/Configuration;")
        : QAndroidJniObject();
    QAndroidJniEnvironment env;
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        return true;
    }
    if (!configuration.isValid())
        return true;
    const jint uiMode = configuration.getField<jint>("uiMode");
    // Configuration.UI_MODE_NIGHT_MASK = 0x30, UI_MODE_NIGHT_YES = 0x20
    return (uiMode & 0x30) == 0x20;
#else
    return true;
#endif
}

QString AndroidStatusBar::systemAccentColor(bool dark) const
{
#ifdef Q_OS_ANDROID
    if (apiLevel() < 31)
        return QString();
    // Material 3 primary of the dynamic palette: tone 80 on a dark page, tone 40 on a light one
    const char *name = dark ? "system_accent1_200" : "system_accent1_600";
    QAndroidJniEnvironment env;
    const jint id = QAndroidJniObject::getStaticField<jint>("android/R$color", name);
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        return QString();
    }
    QAndroidJniObject context = QtAndroid::androidContext();
    if (!context.isValid() || id == 0)
        return QString();
    const jint argb = context.callMethod<jint>("getColor", "(I)I", id);
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        return QString();
    }
    return QColor::fromRgb(static_cast<QRgb>(argb)).name(QColor::HexRgb);
#else
    Q_UNUSED(dark)
    return QString();
#endif
}

void AndroidStatusBar::onInsetsChanged(int top, int bottom, int left, int right, int waterfallTop,
                                        int waterfallBottom, int waterfallLeft, int waterfallRight)
{
    if (m_top != top || m_bottom != bottom || m_left != left || m_right != right ||
        m_waterfallTop != waterfallTop || m_waterfallBottom != waterfallBottom ||
        m_waterfallLeft != waterfallLeft || m_waterfallRight != waterfallRight) {
        m_top = top;
        m_bottom = bottom;
        m_left = left;
        m_right = right;
        m_waterfallTop = waterfallTop;
        m_waterfallBottom = waterfallBottom;
        m_waterfallLeft = waterfallLeft;
        m_waterfallRight = waterfallRight;
        qDebug() << "Insets changed - Top:" << m_top << "Bottom:" << m_bottom << "Left:" << m_left
                 << "Right:" << m_right << "WaterfallTop:" << m_waterfallTop
                 << "WaterfallBottom:" << m_waterfallBottom << "WaterfallLeft:" << m_waterfallLeft
                 << "WaterfallRight:" << m_waterfallRight;
        emit insetsChanged();
    }
}

void AndroidStatusBar::onSystemBarSideInsetsChanged(int left, int right)
{
    if (m_systemBarLeft != left || m_systemBarRight != right) {
        m_systemBarLeft = left;
        m_systemBarRight = right;
        qDebug() << "System bar side insets changed - Left:" << m_systemBarLeft << "Right:" << m_systemBarRight;
        emit insetsChanged();
    }
}

#ifdef Q_OS_ANDROID
// JNI method with standard naming convention
extern "C" JNIEXPORT void JNICALL
Java_org_cagnulen_qdomyoszwift_CustomQtActivity_onInsetsChanged(JNIEnv *env, jobject thiz, jint top,
                                                                    jint bottom, jint left, jint right,
                                                                    jint waterfallTop, jint waterfallBottom,
                                                                    jint waterfallLeft, jint waterfallRight)
{
    Q_UNUSED(env);
    Q_UNUSED(thiz);
    if (AndroidStatusBar::instance()) {
        AndroidStatusBar::instance()->onInsetsChanged(top, bottom, left, right, waterfallTop, waterfallBottom,
                                                       waterfallLeft, waterfallRight);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_org_cagnulen_qdomyoszwift_CustomQtActivity_onSystemBarSideInsetsChanged(JNIEnv *env, jobject thiz, jint left,
                                                                                 jint right)
{
    Q_UNUSED(env);
    Q_UNUSED(thiz);
    if (AndroidStatusBar::instance()) {
        AndroidStatusBar::instance()->onSystemBarSideInsetsChanged(left, right);
    }
}
#endif
