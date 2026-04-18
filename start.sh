#!/bin/bash
set -e

APP_NAME="WisperBar"
PROJECT_DIR="$(dirname "$0")/WisperBar"
DERIVED_DATA=$(xcodebuild -project "$PROJECT_DIR/WisperBar.xcodeproj" \
    -showBuildSettings 2>/dev/null | grep " BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')

echo "→ Cerrando $APP_NAME..."
pkill -x "$APP_NAME" 2>/dev/null && echo "  proceso terminado" || echo "  no estaba corriendo"
sleep 0.3

echo "→ Compilando..."
xcodebuild -project "$PROJECT_DIR/WisperBar.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Debug \
    build 2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)"

APP_PATH=$(xcodebuild -project "$PROJECT_DIR/WisperBar.xcodeproj" \
    -scheme "$APP_NAME" -configuration Debug \
    -showBuildSettings 2>/dev/null \
    | grep "^\s*BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')/"$APP_NAME.app"

echo "→ Iniciando $APP_PATH..."
open "$APP_PATH"
echo "✓ Listo"
