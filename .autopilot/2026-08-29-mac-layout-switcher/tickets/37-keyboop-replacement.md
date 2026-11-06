# 37 — Перепечатка и live-интеграция Keyboop

**What to build:** при собственном свежем буфере автоматическое исправление/Option работают без обязательного AX, через перенесённый Backspace/Unicode механизм, с упорядоченным вводом; live-решения T36 подключены с ограничениями upstream.
**Blocked by:** T35, T36.
**Status:** blocked

- [ ] Нет обязательного AX-поля/диапазона для freshly typed word auto/Option; проверка через настоящий Engine с nil AX.
- [ ] Заимствованный механизм burst/serial posting, метки синтетики, границы Unicode и before-Enter порядок.
- [ ] Option word/undo, live high-confidence, snippets, Space/Enter/ShiftEnter/Tab, rapid input и context reset; Chromium mid-word отключён.
- [ ] SecureInput/пауза/recorder/tap reset/модификаторы/контекст; потеря контекста не запускает удаление.
- [ ] Нет blind retry после начала; факт post не объявляется readback. AX остаётся дополнительным для выделенного/старого текста; dictation не регрессирует.
- [ ] Regression native harness + full core suite + полная macOS speech build, результаты пригодны независимым ревьюерам.

Zone: EngineCore, Engine, EventTap/Typist/keyboard transport, related harness/tests and port notices; не менять identity/updater/detector без согласованного repair. Root owns docs/state/release.

Root-approved investigation clarification: T37 may change KeyTranslator cache and related fixture seam to remove TIS calls from callback. Cache immutable layout data and safety/application classification outside callback, warm before tap start. Global synthetic routing must preserve Spotlight target. Prebuild full batch before first delete, bounded modifier-release deferral with original ShiftEnter flags retained.
