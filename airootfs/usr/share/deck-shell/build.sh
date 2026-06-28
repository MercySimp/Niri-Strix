#!/bin/bash
# Quick build script for the Deck Shell on Arch
# Dependencies: qt6-base qt6-declarative sdl2 cmake make

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$DIR/build"

echo "==> Installing build dependencies..."
sudo pacman -S --needed --noconfirm qt6-base qt6-declarative sdl2 cmake make gcc

echo "==> Configuring..."
cmake -S "$DIR" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release

echo "==> Building..."
cmake --build "$BUILD" --parallel

echo "==> Installing..."
sudo cmake --install "$BUILD"

echo "==> Done! Run: deck-shell"
