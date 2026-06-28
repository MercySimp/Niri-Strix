cmake_minimum_required(VERSION 3.20)
project(DeckShell VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Qml Network)
find_package(SDL2 REQUIRED)

# GamepadHandler.h and SteamLibrary.h must be listed as sources so that
# AUTOMOC processes their Q_OBJECT macros and generates signal/slot impls.
add_executable(deck-shell
    src/main.cpp
    src/GamepadHandler.h
    src/SteamLibrary.h
    src/SteamLibrary.cpp
)

target_include_directories(deck-shell PRIVATE src)

target_link_libraries(deck-shell PRIVATE
    Qt6::Quick
    Qt6::Qml
    Qt6::Network
    SDL2::SDL2
)

# Install binary and QML files
install(TARGETS deck-shell DESTINATION /usr/local/bin)
install(FILES main.qml DESTINATION /usr/share/deck-shell)
