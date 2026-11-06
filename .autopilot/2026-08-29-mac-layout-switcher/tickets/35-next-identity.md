# 35 — Отдельное приложение и канал Next

**What to build:** Next собирается в отдельный app/DMG, запускается с отдельными настройками и обновляется только из нового репозитория.
**Blocked by:** None — can start immediately.
**Status:** ready-for-agent

- [ ] MacLayoutSwitcherNext.app, space.alimp.maclayoutswitcher.next, отличимое display name/menu/title.
- [ ] Раздельные конфиги/логи/модель; нет неявной записи в стабильные пути. Если предусмотрена миграция модели — проверенная копия без изменения оригинала.
- [ ] Собственный updater alimp01/mac-layout-switcher-next; проверка identity загруженного app, no upstream rollback.
- [ ] Одновременный захват клавиатуры стабильной и Next предотвращён, без принудительного убийства процесса.
- [ ] build.sh копирует все SwiftPM ресурсные .bundle в app Resources для T36, speech-helper сохранён.
- [ ] README и тесты updater/identity объясняют две app, корректную установку, rollback, пользовательскую приёмку.

Zone: packaging/build scripts, Config/Speech paths, main startup, UI identity/updater and their fixtures; NOT Package.swift, SwitcherCore, Engine or EventTap. Root owns VERSION, CLAUDE/.autopilot, git/release.
