#!/usr/bin/env bash
# Detached updater. $1 is the installed .app, $2 its owned script directory,
# $3 the exiting application's PID. Build first, retain the old bundle until
# LaunchServices accepts the new launch, and recover on every earlier failure.
set -euo pipefail

LOG="$HOME/Library/Logs/MacLayoutSwitcherNext-update.log"
LOG_READY=false

# Both ends of the transaction must belong to Next. An arbitrary executable
# named MacLayoutSwitcher is not evidence of app identity.
plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null; }
valid_next_app() {
    local app="$1"
    [[ -d "$app" && ! -L "$app" && -f "$app/Contents/Info.plist" &&
       ! -L "$app/Contents/Info.plist" && -x "$app/Contents/MacOS/MacLayoutSwitcher" &&
       ! -L "$app/Contents/MacOS/MacLayoutSwitcher" ]] &&
    [[ "$(plist_value "$app" CFBundleIdentifier)" == space.alimp.maclayoutswitcher.next &&
       "$(plist_value "$app" CFBundleExecutable)" == MacLayoutSwitcher &&
       "$(plist_value "$app" CFBundlePackageType)" == APPL ]]
}
valid_version() { [[ "$1" =~ ^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$ ]]; }
newer_version() {
    local new="$1" old="$2" index
    local -a next_parts old_parts
    valid_version "$new" && valid_version "$old" || return 1
    IFS=. read -r -a next_parts <<< "$new"
    IFS=. read -r -a old_parts <<< "$old"
    for index in 0 1 2; do
        (( next_parts[index] > old_parts[index] )) && return 0
        (( next_parts[index] < old_parts[index] )) && return 1
    done
    return 1
}

APP_PATH="${1:-}"
SCRIPT_TMP="${2:-}"
OLD_PID="${3:-}"
if [[ "$APP_PATH" != /*.app ]] || ! valid_next_app "$APP_PATH"; then
    echo "!! Отказ: '$APP_PATH' не является установленным .app-бандлом Mac Layout Switcher Next"
    exit 1
fi
OLD_VERSION="$(plist_value "$APP_PATH" CFBundleShortVersionString)"
valid_version "$OLD_VERSION" || { echo "!! Отказ: некорректная версия установленного Next"; exit 1; }
if [[ -n "$OLD_PID" && ! "$OLD_PID" =~ ^[1-9][0-9]*$ ]]; then
    echo '!! Отказ: неверный PID предыдущего процесса'
    exit 1
fi
APP_PARENT="$(cd -P "$(dirname "$APP_PATH")" && pwd)"
APP_PATH="$APP_PARENT/$(basename "$APP_PATH")"
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR=""
TRANSACTION=""
BACKUP=""
STAGE="подготовка обновления"
PARENT_STOPPED=false
PARENT_WAIT_FAILED=false

after_previous_exit() {
    if $PARENT_STOPPED; then return 0; fi
    if $PARENT_WAIT_FAILED; then return 1; fi
    if [[ -n "$OLD_PID" ]]; then
        for ((attempt = 0; attempt < 30; attempt++)); do
            if ! kill -0 "$OLD_PID" 2>/dev/null; then
                PARENT_STOPPED=true
                return 0
            fi
            sleep 1
        done
        echo '!! Предыдущий процесс ещё работает; замена и новый запуск отменены'
        PARENT_WAIT_FAILED=true
        return 1
    fi
    PARENT_STOPPED=true
}

cleanup() {
    [[ -z "$TMP_DIR" ]] || rm -rf "$TMP_DIR"
    # A failed restore must keep the previous bundle and all recovery material.
    if [[ -n "$TRANSACTION" && ! -d "$BACKUP" ]]; then rm -rf "$TRANSACTION"; fi
    # Never recursively delete a directory supplied by a caller. Only our exact
    # copied script may be removed; rmdir preserves any unrelated contents.
    local requested_script_dir=""
    if [[ -d "$SCRIPT_TMP" && ! -L "$SCRIPT_TMP" ]]; then
        requested_script_dir="$(cd -P "$SCRIPT_TMP" && pwd)"
    fi
    if [[ "$requested_script_dir" == "$SCRIPT_DIR" &&
          "$(basename "$SCRIPT_DIR")" == MacLayoutSwitcherNext-update-* &&
          "$(basename "${BASH_SOURCE[0]}")" == self-update.sh ]]; then
        rm -f "$SCRIPT_DIR/self-update.sh"
        rmdir "$SCRIPT_DIR" 2>/dev/null || true
    fi
}

finish() {
    local result="$1"
    trap - EXIT
    set +e
    if [[ "$result" -ne 0 ]]; then
        echo "!! Обновление не удалось: $STAGE (код $result)"
        local recovery='Прежняя версия сохранена.'
        if [[ -n "$BACKUP" && -d "$BACKUP" ]]; then
            # Keep the failed candidate too if rollback itself cannot finish.
            if [[ ! -e "$APP_PATH" ]] || mv "$APP_PATH" "$TRANSACTION/failed.app"; then
                if mv "$BACKUP" "$APP_PATH"; then
                    recovery='Прежняя версия восстановлена.'
                else
                    recovery="Не удалось восстановить прежнюю версию. Она сохранена: $BACKUP"
                fi
            else
                recovery="Не удалось освободить путь приложения. Прежняя версия сохранена: $BACKUP"
            fi
        fi
        if [[ ! -d "$BACKUP" ]] && valid_next_app "$APP_PATH" && after_previous_exit; then
            if open "$APP_PATH"; then
                recovery="$recovery Команда её запуска принята macOS. Если значка нет, откройте приложение вручную."
            else
                recovery="$recovery Автоматический запуск не удался; откройте приложение вручную."
            fi
        fi
        local report="${LOG%.log}-failure.txt" message log_detail="$LOG"
        if ! $LOG_READY; then log_detail="Журнал недоступен: $LOG"; fi
        printf -v message 'Не удалось обновить Mac Layout Switcher Next\n\nЭтап: %s (код %s).\n%s\n\nПроверьте сеть, свободное место и права на папку журнала, затем повторите «Проверить обновления…».\nПодробности: %s\n' "$STAGE" "$result" "$recovery" "$log_detail"
        if ! printf '%s\n' "$message" > "$report"; then
            report="$(mktemp "${TMPDIR:-/tmp}/MacLayoutSwitcherNext-update-failure.XXXXXX")"
            [[ -z "$report" ]] || printf '%s\n' "$message" > "$report"
        fi
        if [[ -n "$report" && -s "$report" ]]; then
            # A text report also works when recovering an older app that has no
            # update-error argument handler. Launch failure remains in the log.
            open -t "$report" || echo "!! Откройте отчёт вручную: $report"
        fi
    else
        # Successful open means launch accepted, not proof of a running process.
        # No later cleanup error may roll back a possibly running new version.
        [[ -z "$BACKUP" ]] || rm -rf "$BACKUP"
    fi
    cleanup
    exit "$result"
}
trap 'finish $?' EXIT

STAGE="подготовка журнала (проверьте свободное место и права на папку Logs)"
mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
LOG_READY=true
echo "=== $(date '+%Y-%m-%d %H:%M:%S') self-update: старт ==="
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mls-next-update.XXXXXX")"
STAGE="скачивание исходников (проверьте подключение к сети)"
TARBALL_URL="https://github.com/alimp01/mac-layout-switcher-next/archive/refs/heads/main.tar.gz"
curl -fL --max-time 300 -o "$TMP_DIR/src.tar.gz" "$TARBALL_URL"
STAGE="распаковка исходников (повторите загрузку)"
tar -xzf "$TMP_DIR/src.tar.gz" -C "$TMP_DIR"
SRC_DIR="$TMP_DIR/mac-layout-switcher-next-main"
[[ -f "$SRC_DIR/build.sh" ]] || { echo '!! В архиве нет build.sh'; exit 1; }
STAGE="сборка приложения (см. ошибку компилятора в логе)"
( cd "$SRC_DIR" && unset MLS_DIST_DIR MLS_DISABLE_SPEECH MLS_SWIFT_SCRATCH_PATH; bash ./build.sh )
NEW_APP="$SRC_DIR/dist/MacLayoutSwitcherNext.app"
STAGE="проверка идентичности, версии и подписи Next"
valid_next_app "$NEW_APP" || { echo '!! Сборка не создала корректный Next .app'; exit 1; }
NEW_VERSION="$(plist_value "$NEW_APP" CFBundleShortVersionString)"
newer_version "$NEW_VERSION" "$OLD_VERSION" || { echo '!! Отказ от той же, более старой или некорректной версии'; exit 1; }
codesign --verify --deep --strict "$NEW_APP"

STAGE="подготовка замены (проверьте свободное место и права на папку приложения)"
TRANSACTION="$(mktemp -d "$APP_PARENT/.MacLayoutSwitcherNext-update.XXXXXX")"
BACKUP="$TRANSACTION/previous.app"
cp -R "$NEW_APP" "$TRANSACTION/new.app"
valid_next_app "$TRANSACTION/new.app"
codesign --verify --deep --strict "$TRANSACTION/new.app"
STAGE="ожидание завершения предыдущего процесса"
after_previous_exit
STAGE="повторная проверка установленного Next перед заменой"
valid_next_app "$APP_PATH"
[[ "$(plist_value "$APP_PATH" CFBundleShortVersionString)" == "$OLD_VERSION" ]]
STAGE="замена приложения"
mv "$APP_PATH" "$BACKUP"
mv "$TRANSACTION/new.app" "$APP_PATH"
STAGE="запуск новой версии"
open "$APP_PATH"
# This is the last fallible operation before success is committed.
exit 0
