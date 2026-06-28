#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
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

    const QUrl qmlMain(QStringLiteral("file:///usr/share/deck-shell/main.qml"));
    engine.load(qmlMain);
    if (engine.rootObjects().isEmpty()) return -1;

    return app.exec();
}
