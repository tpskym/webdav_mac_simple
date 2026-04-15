#!/usr/bin/env bash
# Сборка приложения и упаковка в WebDAVClient.app (GUI-бандл для macOS).
# По умолчанию собирает release; для debug передайте --debug.

set -e
cd "$(dirname "$0")/.."

CONFIG="release"
if [[ "${1:-}" == "--debug" ]]; then
  CONFIG="debug"
fi

if [[ "$CONFIG" == "release" ]]; then
  echo "→ swift build -c release"
  swift build -c release
else
  echo "→ swift build"
  swift build
fi

APP="WebDAVClient.app"
BINARY=".build/$CONFIG/WebDAVClient"

mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

echo "→ копирование бинарника в $APP"
cp "$BINARY" "$APP/Contents/MacOS/WebDAVClient"

if [[ -f Info.plist ]]; then
  echo "→ копирование Info.plist в $APP/Contents/"
  cp Info.plist "$APP/Contents/Info.plist"
else
  echo "⚠ Info.plist не найден; иконка и метаданные приложения могут не отображаться."
fi

if [[ -f AppIcon.icns ]]; then
  echo "→ копирование иконки в $APP/Contents/Resources/"
  cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  echo "⚠ AppIcon.icns не найден в корне проекта; иконка в бандле не обновлена."
fi

echo "✓ Готово ($CONFIG). Запуск GUI-приложения: open $APP"
