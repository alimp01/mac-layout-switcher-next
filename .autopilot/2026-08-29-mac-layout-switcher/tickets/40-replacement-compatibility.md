# T40 — исправление общей замены в редактируемых полях

**What to build:** устранить повторный отказ ручной замены выделенного текста/слова в редактируемых поисковых полях и палитрах, с проверками общего механизма и точным объяснением невозможной операции.
**Blocked by:** None — can start immediately.
**Status:** in-progress — implementation/reviews/build/install complete; live acceptance pending

- [x] Production baseline RED for demonstrated common guard/capability defect; exact source→replacement.
- [x] General minimal fix, selected/fresh/preexisting path coverage, non-text/readonly/secure controls stay protected.
- [x] Focus/selection/value/PID/physical-input cancellation, partial mutation/no retry and source preservation verified.
- [x] Content-free real-stage diagnostics if refusal otherwise remains opaque; no speculative permission blame.
- [x] Existing auto/undo/rapid-input/dictation regressions, two independent reviews and source provenance.
- [ ] Publication and permitted live acceptance; Linux/native speech/DMG/installation already passed.

Spec replacement-compatibility-spec.md. Executor reads implement and TDD skills. Root writes docs/version/releases; executor code/tests only. No live private UI/AX bypass.
