#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QMetaMethod>
#include <QDebug>
#include <QStandardPaths>
#include <QDir>
#include "GamepadHandler.h"
#include "SteamLibrary.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName("deck-shell");
    // NOTE: do NOT set OrganizationName — it causes Qt to nest storage paths
    // as <org>/<app>/... instead of the flat ~/.local/share/deck-shell/... we want.

    QQmlApplicationEngine engine;

    // Resolve XDG-compliant paths using the real running user's home.
    // Exposed as context properties so QML never needs to hardcode any username
    // or rely on QtCore's StandardPaths QML singleton (unreliable on some distros).
    const QString webDataPath  = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation) + "/webengine";
    const QString webCachePath = QStandardPaths::writableLocation(QStandardPaths::CacheLocation)        + "/webengine";

    // Pre-create the directories before the QML engine and QtWebEngine renderer
    // subprocess spin up — Chromium's disk cache code runs in a separate process
    // and will fail with FILE_ERROR_ACCESS_DENIED if the parent dirs don't exist yet.
    QDir().mkpath(webDataPath);
    QDir().mkpath(webCachePath);

    engine.rootContext()->setContextProperty("webDataPath",  webDataPath);
    engine.rootContext()->setContextProperty("webCachePath", webCachePath);

    // SDL2 controller backend — signals emitted into QML as "Gamepad"
    GamepadHandler gamepad;
    engine.rootContext()->setContextProperty("Gamepad", &gamepad);

    // Steam library model — exposed to QML as both:
    //   SteamLibrary      → used as ListView/GridView model (data roles)
    //   SteamLibraryCtrl  → used for Q_INVOKABLE method calls from QML
    // This split avoids a Qt6 issue where QAbstractListModel objects used
    // as view models get wrapped in a proxy that shadows Q_INVOKABLE methods.
    SteamLibraryModel steamLibrary;
    engine.rootContext()->setContextProperty("SteamLibrary",     &steamLibrary);
    engine.rootContext()->setContextProperty("SteamLibraryCtrl", &steamLibrary);

    // ── Meta-object debug dump ────────────────────────────────────────────────────
    const QMetaObject *mo = steamLibrary.metaObject();
    qDebug() << "Class =" << mo->className();
    for (int i = mo->methodOffset(); i < mo->methodCount(); ++i)
        qDebug() << mo->method(i).methodSignature();
    // ───────────────────────────────────────────────────────────────────────

    const QUrl qmlMain(QStringLiteral("file:///usr/share/deck-shell/main.qml"));
    engine.load(qmlMain);
    if (engine.rootObjects().isEmpty()) return -1;

    return app.exec();
}
