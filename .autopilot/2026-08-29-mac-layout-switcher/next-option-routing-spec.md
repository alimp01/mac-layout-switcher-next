# Next: свежий Option в браузере с доступным AX

## Problem Statement
После принятой Next1.5.0 в Codex пользователь только что набрал «кмсф» в Safari / Яндекс и нажал Option. Текст остался, показан общий отказ проверяемой замены. Собственный свежий буфер в Next должен использовать перенесённый механизм Keyboop и не зависеть от доступности AX-записи. Наличие AX-чтения сейчас ошибочно направляет ручную конвертацию через прежний путь выделения/замены. Конкретный этап отказа на реальном Safari пока не измерен: скрин сам по себе не доказывает отказ setter или изменение range.

## Solution
Option конвертирует только что набранное слово через разрешённый buffered Backspace/Unicode путь, также когда браузер предоставляет AX-чтение. Сохраняются проверки контекста и явного выделения.

## User Stories
1. Я только что набрал «шорты кмсф», нажимаю Option без выделения и получаю «шорты rvca» с сохранением префикса/хвоста и курсора.
2. Я могу сделать ту же замену ghbdtn→привет и повторно отменить/конвертировать по существующим правилам.
3. Читаемое, но не поддерживающее AX-запись поле не ухудшает работу собственного свежего буфера.
4. При выделении текста применяется прежний проверяемый путь; неизвестное непустое выделение не становится разрешением Backspace.
5. Если я вернулся к старому тексту/сменил поле/переместил курсор, прошлый буфер не разрешает слепое удаление. Старый текст остаётся в AX-маршруте.
6. SecureInput и известное парольное поле, changed PID/field/caret/value, ввод во время захвата и отмена останавливают операцию до удаления.
7. После начала изменения не выполняется автоматическая повторная разрушающая попытка; результат post честно отличается от readback.
8. Автоисправление по Space/Enter/ShiftEnter/Tab, rapid input, live guards и диктовка сохраняются.

## Implementation Decisions
- База 546f3f953fdb137048cbee623901c7f2618995b6; только Next. ADR0014 остаётся границей разрешения: fresh observed stream разрешает buffered replacement, произвольный старый текст — нет.
- Найти и воспроизвести отказ в настоящем Engine, где capture возвращает пустое выделение/читаемый текст, но AX replacement capability ограничена. Не ограничиваться nil-AX fixture.
- Выбирать маршрут до первой мутации. Не пробовать слепой retry после legacy mutation failure.
- Положительное AX-свидетельство несоответствия source/caret/selection нельзя игнорировать ради свежего буфера. Доступные guards проверяются перед записью без обязательного AX-setter/readback для buffered success.
- Отсутствие ранее закешированного AX-элемента само по себе не обнуляет свежий наблюдавшийся поток. Реальная смена известного поля по-прежнему отзывает его authority.
- Нет AX/TIS/I/O/sleep в EventTap. Нет новых clipboard-операций, приватного UI обхода или TCC manipulation.
- Границы изменения: ручной routing/guards и необходимые tests; не расширять dictionaries только ради RVCA. Указать отдельно, что автоматическое распознавание бренда и явная конвертация Option — разные решения.

## Testing Decisions
- Highest production Engine/EventTap/Typist seam: русский ввод «шорты кмсф» + Option без выделения, readable AX/unsupported mutation, baseline RED→GREEN, literal resulting text/prefix/caret and absence of conversion notice. Add EN ghbdtn→привет.
- Positive contradictory value/range/field, known unreadable selection, lost source authority, protected field, new key/click/caret/PID, no mutation/retry after abort. Include initial nil cached AX becoming readable.
- Keep retained selected/preexisting-text behavior, undo, auto boundary/rapid/live safety; existing speech regressions by changed scope.
- Root runs appropriate existing native regressions, full Linux SwiftPM suite once on final public reviewed commit, full native speech build, signed/mounted DMG. Two independent Spec/Standards reviews.
- Installed Safari acceptance remains separate and user-driven; no universal editor claim from owned fixture.

## Out of Scope
Dictionary expansion, blind conversion of arbitrary older text, clipboard fallback, changes to stable, unrelated feature rewrites.

## Further Notes
User answered fresh typed immediately before Option; no more general app/trigger questions needed. Local ticket38 is the configured project tracker under existing /autopilot user instructions. Next release candidate1.5.1; VERSION→commit→push Next→separate archive.
