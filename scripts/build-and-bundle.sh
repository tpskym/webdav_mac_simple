#!/usr/bin/env bash
# Сборка приложения и упаковка в WebDAVClient.app с иконкой.
# При каждой сборке нужно запускать этот скрипт, иначе в бандле не будет
# актуального бинарника и/или иконки (папка Resources может отсутствовать).

set -e
cd "$(dirname "$0")/.."

echo "→ swift build"
swift build

APP="WebDAVClient.app"
BINARY=".build/debug/WebDAVClient"

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

echo "✓ Готово. Запуск: open $APP"
