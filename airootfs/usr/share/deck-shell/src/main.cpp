#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include "GamepadHandler.h"

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    app.setApplicationName("DeckShell");
    app.setOrganizationName("NiriStrix");

    GamepadHandler gamepad;

    QQmlApplicationEngine engine;
    // Expose SDL2 gamepad handler to QML as "Gamepad"
    engine.rootContext()->setContextProperty("Gamepad", &gamepad);

    const QUrl qmlMain(QStringLiteral("/usr/share/deck-shell/main.qml"));
    engine.load(qmlMain);

    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
