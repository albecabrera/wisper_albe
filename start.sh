#!/bin/bash
set -e

APP_NAME="WisperBar"
PROJECT_DIR="$(cd "$(dirname "$0")/WisperBar" && pwd)"
APP_PATH="$PROJECT_DIR/.build/Build/Products/Debug/$APP_NAME.app"

echo "→ Cerrando $APP_NAME..."
pkill -x "$APP_NAME" 2>/dev/null && echo "  proceso terminado" || echo "  no estaba corriendo"
sleep 0.3

echo "→ Compilando con últimos cambios..."
cd "$PROJECT_DIR"
xcodebuild \
    -scheme "$APP_NAME" \
    -configuration Debug \
    -derivedDataPath .build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)"

echo "→ Iniciando $APP_NAME..."
open "$APP_PATH"
echo "✓ Listo"
