# 38 — Option использует свежий буфер и при читаемом AX

**What to build:** только что набранное слово в обычном браузерном поле меняется по Option через buffered механизм Next; неполный AX-запись интерфейс не заставляет показывать прежний отказ.
**Blocked by:** None — can start immediately.
**Status:** implemented/reviewed — physical Safari acceptance pending

- [x] Baseline production Engine RED with readable AX but unsupported mutation, Russian «шорты кмсф» and English ghbdtn.
- [x] Final literal replacements preserve unrelated text, caret and single action; use buffered route before any legacy mutation.
- [x] Selected/preexisting text retain correct authority; fresh nil-cache capture does not unnecessarily lose observed buffer; contradictory positive AX blocks stale conversion.
- [x] secure/field/caret/value/PID/input cancellation and no retry remain intact; existing boundary/live/undo/snippet/selected-text/dictation regressions as relevant.
- [x] Native source provenance and meaningful RED→GREEN evidence; freeze for both reviews.
- [x] Root full Linux/native speech/DMG/release checks; Safari physical outcome recorded separately.

Spec: next-option-routing-spec.md. Executor reads /implement and applies TDD. Root owns .autopilot/CLAUDE/NEXT_SESSION/VERSION/git/release; executor owns scoped product/tests only. No live private UI/TCC access.

Code5069c7b; both final reviews APPROVE0. Linux110/0; native/full speech/mounted DMG passed with documented fixture timing repair. Actual Safari user outcome remains pending.
