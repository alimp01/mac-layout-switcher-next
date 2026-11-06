# 36 — Языковые решения Keyboop в нашем ядре

**What to build:** завершённые слова и live-кандидаты получают решения из словарей, триграмм и правил закреплённого Keyboop с сохранением наших исключений/undo.
**Blocked by:** None — independent of T35, integration before release.
**Status:** ready-for-agent

- [ ] Полные JSON RU/EN, оригинальные rules/ExtraWords, MIT notices/пин/hash manifest; загрузка при подготовке, не в callback.
- [ ] Detector.verdict API совместим; liveVerdict(for:) доступен и не меняет контекст. Не менять EngineCore: T37 интегрирует live-события.
- [ ] Поддержать upstream нормализацию/коллизии/смешанные слова и осознанно документировать адаптации карты и собственных исключений.
- [ ] Независимые literal/parity проверки с исходным Keyboop; baseline failures → final decisions; ресурсы реально читаются.
- [ ] Старые тесты обновлять только с объяснением смены контракта, не подгонять expected из production.
- [ ] Linux full suite и SwiftPM packaging ресурсов; сообщить точные результаты и ограничения.

Zone: Package.swift, Detector and new language modules/resources, detection-related Tests, THIRD_PARTY/LICENSE notices. NOT build scripts, identity/UI, EngineCore, Engine/EventTap/Typist. Root owns .autopilot/CLAUDE/git.
