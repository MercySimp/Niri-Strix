#pragma once
#include <QObject>
#include <SDL2/SDL.h>
#include <QTimer>

// GamepadHandler polls SDL2 gamepad events on a timer and emits Qt signals
// that main.qml consumes via a Connections block.
// Inject into QML with: engine.rootContext()->setContextProperty("Gamepad", &handler);

class GamepadHandler : public QObject {
    Q_OBJECT
public:
    explicit GamepadHandler(QObject *parent = nullptr) : QObject(parent) {
        SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
        SDL_Init(SDL_INIT_GAMECONTROLLER);
        m_timer = new QTimer(this);
        connect(m_timer, &QTimer::timeout, this, &GamepadHandler::poll);
        m_timer->start(16); // ~60 Hz polling
    }

    ~GamepadHandler() {
        if (m_controller) SDL_GameControllerClose(m_controller);
        SDL_QuitSubSystem(SDL_INIT_GAMECONTROLLER);
    }

signals:
    void buttonA();
    void buttonB();
    void buttonX();
    void buttonY();
    void dpadUp();
    void dpadDown();
    void dpadLeft();
    void dpadRight();
    void axisLeftY(float value);
    void axisLeftX(float value);
    void lb();   // Left bumper  — cycle filter left
    void rb();   // Right bumper — cycle filter right

private slots:
    void poll() {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            switch (e.type) {
            case SDL_CONTROLLERDEVICEADDED:
                if (!m_controller)
                    m_controller = SDL_GameControllerOpen(e.cdevice.which);
                break;
            case SDL_CONTROLLERDEVICEREMOVED:
                if (m_controller) {
                    SDL_GameControllerClose(m_controller);
                    m_controller = nullptr;
                }
                break;
            case SDL_CONTROLLERBUTTONDOWN:
                switch (e.cbutton.button) {
                case SDL_CONTROLLER_BUTTON_A:             emit buttonA();  break;
                case SDL_CONTROLLER_BUTTON_B:             emit buttonB();  break;
                case SDL_CONTROLLER_BUTTON_X:             emit buttonX();  break;
                case SDL_CONTROLLER_BUTTON_Y:             emit buttonY();  break;
                case SDL_CONTROLLER_BUTTON_DPAD_UP:       emit dpadUp();   break;
                case SDL_CONTROLLER_BUTTON_DPAD_DOWN:     emit dpadDown(); break;
                case SDL_CONTROLLER_BUTTON_DPAD_LEFT:     emit dpadLeft(); break;
                case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:    emit dpadRight();break;
                case SDL_CONTROLLER_BUTTON_LEFTSHOULDER:  emit lb();       break;
                case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: emit rb();       break;
                }
                break;
            case SDL_CONTROLLERAXISMOTION:
                if (e.caxis.axis == SDL_CONTROLLER_AXIS_LEFTY)
                    emit axisLeftY(e.caxis.value / 32768.0f);
                if (e.caxis.axis == SDL_CONTROLLER_AXIS_LEFTX)
                    emit axisLeftX(e.caxis.value / 32768.0f);
                break;
            }
        }
    }

private:
    SDL_GameController *m_controller = nullptr;
    QTimer *m_timer = nullptr;
};
