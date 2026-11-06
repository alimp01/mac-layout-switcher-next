# Next 1.5.0 — проверка релиза 2026-11-06

## Исходники и объём
Репозиторий: https://github.com/alimp01/mac-layout-switcher-next .
Родитель: 7043925e2f4f7028c6cb1539669290dbf5e0d446 (stable1.4.12).
Keyboop: fb9bdde4eb8f13a486974cf102a8bec9d607e5d2.
T35:31d71a7; T36:3735b80; итоговый код T37:a0b060076612c5fe0c4cb98056a9f10e775a8d2f.
Последующие релизные коммиты меняют только документацию/метаданные.

Перенесены полные RU/EN словари и триграммы, правила решений, live-решения
и buffered Backspace/Unicode замена. Независимая app, настройки и обновления;
GigaAM сохранён. Адаптации и лицензии: THIRD_PARTY.md, ADR0014.

## Проверки
| Проверка | Результат |
|---|---|
| Реальный Linux SwiftPM XCTest из свежего публичного клона @a0b0600 | 110 тестов, 0 ошибок |
| Нативный дополнительный адаптер тестов ядра | 110 методов, 4593 утверждения, 0 ошибок; это не XCTest runtime |
| Независимый паритет с неизменённым закреплённым Keyboop | 257 fixture результатов воспроизведены; 4 языковых JSON побайтно совпадают |
| Собственный свежий ghbdtn при недоступном AX | Space и Option: baseline RED → production Engine GREEN |
| Нативный Engine | границы/модификаторы/повторы/быстрый ввод, навигация176 комбинаций, отмена/tap/secure, Unicode/snippets/undo/live PASS |
| Финальные дополнительные проверки | ручной выбор, trigger/prefix, caret при смене app, protected→unknown→ordinary/newPID PASS |
| Сохранённый AX путь | Option/выделение/readonly failures, нечитаемое выделение без fallback PASS |
| Диктовка | root adapter/completion/panel PASS; длинный текст, отмена, уведомления, no retry |
| Установка/обновление | identity/session/packaging/resume PASS; updater23 случаев PASS |
| Полная native arm64 speech-сборка | PASS, SpeechRecognizer в app |
| Реальный resource bundle вне build tree | PASS; при удалении ресурсов isReady=false/unsure |
| DMG | mounted readonly, deep/strict signature, все файлы сравнены, helper и 4 JSON сверены |

Полные результаты и source-seam provenance: audit/keyboop-fork/.
Финальный T37 manifest SHA256:77fc86007fefe2b1a6962f3a76639bfc023cb611f73bc362f15080cb54fa550b.
Реальный Linux лог SHA256:564a0c51c8f95deb0ac67d26acd4719e57bae4bd63d40abb13699ad28a74204e.

## Ревью
Два независимых ревью Spec и Standards: финальный v3 APPROVED, 0 оставшихся
замечаний. Закрыты воспроизведённые P2 по ручному Option/live, snippets/live,
фрагменту после клика и потере этого guard при техническом сбросе. Самопроверка
добавила sticky-защиту известного парольного поля, ограниченную его PID.
Standards независимо повторил changed-app caret на точном финальном binary.

## Артефакт и выпуск
MacLayoutSwitcherNext-1.5.0.dmg, 12224867 байт.
SHA256:170ef576e14f3b0f076f7ffbdfc3f7fc6be365e2e3a1371e0dc460be43ca3a1a.
Bundle:space.alimp.maclayoutswitcher.next. Полный receipt: audit/keyboop-fork/dmg-receipt.json.
Публикация только в Next main и отдельный mac-layout-switcher-next.tar.gz.
Финальный HTTP/rawVERSION/PAX/blob receipt сохраняется в workspace outputs/keyboop-fork;
архив со всем содержимым Git проверяется после последнего metadata-коммита.

## Установка и аппаратная приёмка — 2026-11-06
Next1.5.0 установлен в /Applications/MacLayoutSwitcherNext.app. Подпись и
binary/helper SHA256 соответствуют проверенному артефакту. Старый процесс
MacLayoutSwitcher завершён; его app сохранён. После ручной выдачи пользователем
Accessibility/Input Monitoring и перезапуска найден только Next PID75271;
autoSwitch=true.

В поле сообщения Codex пользователь обычной клавиатурой проверил английский
`ghbdtn + Space` и отдельно `ghbdtn + Option` без выделения, с очисткой поля
и повторным выбором EN между случаями. Ответ: **«Оба раза получилось «привет»»**.
Это аппаратная приёмка ровно этих двух путей Next, а не перенос результатов stable.

## Ограничения доказательств
Другие приложения, Enter/Shift+Enter, быстрый набор и голосовая вставка этим
ответом не приняты. Нативный стенд использует собственные скрытые NSTextView,
настоящие CGEvent/NSEvent/TIS и подменяет внешний AX/последний OS post;
он не доказывает доставку через WindowServer во все редакторы. Posted не
называется readback. TCC разрешения выдал сам пользователь, их база не менялась.
CUA показал первый диалог Next; последующее управление меню завершалось
timeout и не использовалось как доказательство успешной замены. Исторические
build/DMG receipts отражают состояние до этой ручной приёмки.

## Публикация исходников
Автоматическая проверка первоначально отклонила непроверенную передачу рабочих
исходников субагентом. Root проверил заданный пользователем сервер, путь, origin и
публичный parent HEAD; затем опубликовал только прошедшие оба ревью Git commits.
Linux проверки выполнены из публичных GitHub clones. Секреты не выводились и
не включались в исходники. Ограничение передачи для текущего релиза устранено.
