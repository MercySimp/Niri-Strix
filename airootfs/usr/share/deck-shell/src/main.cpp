#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QMetaMethod>
#include <QDebug>
#include "GamepadHandler.h"
#include "SteamLibrary.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName("DeckShell");
    app.setOrganizationName("NiriStrix");

    QQmlApplicationEngine engine;

    // SDL2 controller backend — signals emitted into QML as "Gamepad"
    GamepadHandler gamepad;
    engine.rootContext()->setContextProperty("Gamepad", &gamepad);

    // Steam library model — exposed to QML as "SteamLibrary"
    SteamLibraryModel steamLibrary;
    engine.rootContext()->setContextProperty("SteamLibrary", &steamLibrary);

    // ── Meta-object debug dump ──────────────────────────────────────────────
    // Prints every method registered on SteamLibraryModel so we can confirm
    // fetchOwnedGamesForId is visible to the QML meta-object system.
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
