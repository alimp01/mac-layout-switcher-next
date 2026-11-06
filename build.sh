#!/usr/bin/env bash
#
# build.sh — сборка Mac Layout Switcher в запускаемый .app одной командой.
#
# Запускать ТОЛЬКО на macOS 13+ с установленным Swift toolchain
# (Xcode Command Line Tools: `xcode-select --install`). На Linux-машине сборки
# агента этот скрипт не проверяется запуском — только шеллчеком (`bash -n`);
# логика системного слоя закрыта тестами ядра на Linux (`swift test`).
#
# Шаги:
#   1. Собрать релизный бинарник через SwiftPM.
#   2. Разложить бандл MacLayoutSwitcherNext.app (Contents/MacOS + Info.plist).
#   3. Подписать ad-hoc (без сертификата разработчика) — иначе macOS не даст
#      выдать приложению Accessibility/Input Monitoring.
#   4. Напечатать путь к .app и что делать дальше.

# -e: падать на первой же ошибке; -u: необъявленная переменная — ошибка;
# -o pipefail: ошибка в любом звене пайпа валит весь пайп. Без этого скрипт
# бодро «соберёт» битый .app и отрапортует успех.
set -euo pipefail

# Каталог скрипта = корень репозитория (Package.swift рядом). Так build.sh
# работает из любого cwd, а не только из корня.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Параметры бандла ---------------------------------------------------------
APP_NAME="MacLayoutSwitcherNext"             # отдельный bundle; SwiftPM product сохранён
EXECUTABLE_NAME="MacLayoutSwitcher"
BUNDLE_ID="space.alimp.maclayoutswitcher.next"
# CFBundleShortVersionString — из файла VERSION в корне репо (одна строка
# semver). Это источник истины для автообновления: Updater сравнивает версию
# бандла с raw VERSION из main на GitHub, поэтому зашивать её здесь нельзя.
VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION")"
if [[ -z "$VERSION" ]]; then
    echo "!! Файл VERSION пуст или не найден" >&2
    exit 1
fi
BUILD="1"                                    # CFBundleVersion
MIN_MACOS="13.0"

# --- 1. Релизная сборка -------------------------------------------------------
echo "==> swift build -c release"
SWIFT_BUILD_ARGS=(-c release)
if [[ -n "${MLS_SWIFT_SCRATCH_PATH:-}" ]]; then
    SWIFT_BUILD_ARGS+=(--scratch-path "$MLS_SWIFT_SCRATCH_PATH")
fi
swift build "${SWIFT_BUILD_ARGS[@]}"

# Путь к каталогу с собранными артефактами (…/.build/release или арх-специфичный).
BIN_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
BIN_PATH="$BIN_DIR/$EXECUTABLE_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "!! Бинарник не найден: $BIN_PATH" >&2
    exit 1
fi

# --- 2. Раскладка бандла ------------------------------------------------------
# Кладём .app в dist/ рядом с репозиторием; полностью пересобираем каждый раз,
# чтобы не тащить старые файлы Contents.
DIST_DIR="${MLS_DIST_DIR:-$SCRIPT_DIR/dist}"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

echo "==> Собираю бандл $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"

# Исполняемый файл.
cp "$BIN_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

# Native offline recognizer is available only in arm64 builds. Main executable
# remains macOS 13.0; the helper has its own 13.4 minimum.
if [[ "$(uname -m)" == "arm64" && "${MLS_DISABLE_SPEECH:-0}" != "1" ]]; then
    HELPER_PATH="$BIN_DIR/SpeechRecognizer"
    if [[ ! -x "$HELPER_PATH" ]]; then
        echo "!! SpeechRecognizer отсутствует в arm64-сборке" >&2
        exit 1
    fi
    mkdir -p "$APP_BUNDLE/Contents/Helpers"
    cp "$HELPER_PATH" "$APP_BUNDLE/Contents/Helpers/SpeechRecognizer"
    chmod +x "$APP_BUNDLE/Contents/Helpers/SpeechRecognizer"
    codesign --force --sign - "$APP_BUNDLE/Contents/Helpers/SpeechRecognizer"
fi
mkdir -p "$RESOURCES_DIR/Licenses"
cp "$SCRIPT_DIR"/Resources/Licenses/* "$RESOURCES_DIR/Licenses/"

# SwiftPM places resource bundles next to the products. Bundle.module looks in
# the app Resources at runtime; copy every bundle, including dependency data.
shopt -s nullglob
for resource_bundle in "$BIN_DIR"/*.bundle; do
    cp -R "$resource_bundle" "$RESOURCES_DIR/"
done
shopt -u nullglob

# Иконка приложения (Finder, «Программы», Dock при запуске, .dmg).
# Генерируется на Linux-машине: python3 tools/make-icns.py (из Resources/AppIcon.svg)
# и лежит в репозитории. Если её нет — собираем без иконки, но предупреждаем:
# .app останется рабочим, просто с дефолтной иконкой.
ICNS_SRC="$SCRIPT_DIR/Resources/AppIcon.icns"
ICON_PLIST_KEYS=""
if [[ -f "$ICNS_SRC" ]]; then
    mkdir -p "$RESOURCES_DIR"
    cp "$ICNS_SRC" "$RESOURCES_DIR/AppIcon.icns"
    # Перевод строки и отступ внутри значения не важны — plist это переживёт,
    # но держим формат ровным для читаемости готового Info.plist.
    ICON_PLIST_KEYS="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
else
    echo "!! Resources/AppIcon.icns не найден — собираю без иконки." >&2
    echo "!! Сгенерировать: python3 tools/make-icns.py (нужен cairosvg)." >&2
fi

# Скрипт самообновления — в Resources бандла: приложение (Updater) копирует
# его оттуда во временную папку и запускает detached, когда пользователь
# соглашается обновиться (см. tools/self-update.sh).
mkdir -p "$RESOURCES_DIR"
cp "$SCRIPT_DIR/tools/self-update.sh" "$RESOURCES_DIR/self-update.sh"
chmod +x "$RESOURCES_DIR/self-update.sh"

# Info.plist. LSUIElement=true → приложение без иконки в Dock (только меню-бар),
# как и просит .accessory-режим в main.swift. LSMinimumSystemVersion фиксирует
# macOS 13. NSPrincipalClass=NSApplication нужен, чтобы .app стартовал как GUI.
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Mac Layout Switcher Next</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
${ICON_PLIST_KEYS}
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Микрофон нужен для локальной диктовки. Аудио распознаётся на этом Mac и не отправляется на сервер.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Свой аналог Punto/Caramba. Открытый код.</string>
</dict>
</plist>
PLIST

# PkgInfo — необязателен, но традиционен для .app (тип APPL, без подписи-кода).
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# --- 3. Ad-hoc подпись --------------------------------------------------------
# `-s -` = подпись «личность отсутствует» (ad-hoc). Без подписи TCC не запомнит
# выданные разрешения между запусками. --deep подписывает вложенное, --force
# перекрывает прежнюю подпись при пересборке.
echo "==> codesign (ad-hoc)"
# Finder / downloaded source archives can carry resource forks or FinderInfo.
# Strip metadata only from our freshly assembled output, before sealing it.
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE"

# --- 4. Итог ------------------------------------------------------------------
cat <<DONE

Готово: $APP_BUNDLE

Первый запуск:
  1. Открыть приложение: open "$APP_BUNDLE"
     (ad-hoc подпись — Gatekeeper может ругнуться: правый клик по .app → «Открыть».)
  2. Выдать разрешения по подсказке приложения:
       Системные настройки → Конфиденциальность и безопасность →
         • Универсальный доступ (Accessibility)
         • Мониторинг ввода (Input Monitoring)
     Включить «Mac Layout Switcher Next» в обоих списках.
  3. Перезапустить приложение (пункт меню-бара «Я выдал разрешения»).

Иконка появится в меню-баре (клавиатура). Dock-иконки нет — это ожидаемо.

Для .dmg-дистрибутива (установка перетаскиванием в «Программы»): ./build-dmg.sh
DONE
