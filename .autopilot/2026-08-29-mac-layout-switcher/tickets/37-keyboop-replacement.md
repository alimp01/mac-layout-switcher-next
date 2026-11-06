# 37 — Перепечатка и live-интеграция Keyboop

**What to build:** при собственном свежем буфере автоматическое исправление/Option работают без обязательного AX, через перенесённый Backspace/Unicode механизм, с упорядоченным вводом; live-решения T36 подключены с ограничениями upstream.
**Blocked by:** T35, T36.
**Status:** done (Spec + Standards approved, release checks passed)

- [x] Нет обязательного AX-поля/диапазона для freshly typed word auto/Option; проверка через настоящий Engine с nil AX.
- [x] Заимствованный механизм burst/serial posting, метки синтетики, границы Unicode и before-Enter порядок.
- [x] Option word/undo, live high-confidence, snippets, Space/Enter/ShiftEnter/Tab, rapid input и context reset; Chromium mid-word отключён.
- [x] SecureInput/пауза/recorder/tap reset/модификаторы/контекст; потеря контекста не запускает удаление.
- [x] Нет blind retry после начала; факт post не объявляется readback. AX остаётся дополнительным для выделенного/старого текста; dictation не регрессирует.
- [x] Regression native harness + full core suite + полная macOS speech build, результаты пригодны независимым ревьюерам.

Zone: EngineCore, Engine, EventTap/Typist/keyboard transport, related harness/tests and port notices; не менять identity/updater/detector без согласованного repair. Root owns docs/state/release.

Root-approved investigation clarification: T37 may change KeyTranslator cache and related fixture seam to remove TIS calls from callback. Cache immutable layout data and safety/application classification outside callback, warm before tap start. Global synthetic routing must preserve Spotlight target. Prebuild full batch before first delete, bounded modifier-release deferral with original ShiftEnter flags retained.

Final code commit: `a0b060076612c5fe0c4cb98056a9f10e775a8d2f`. Native/full Linux/speech/DMG evidence: keyboop-fork-qa.md. Physical acceptance passed for Codex ghbdtn+Space and ghbdtn+Option on2026-11-06; other paths remain untested.
