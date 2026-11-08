# G33 / T38 — Next Option routing QA, 2026-11-08

## User evidence
Screenshot Safari / yandex.ru, text «шорты кмсф», Next generic verified-replacement failure notice. User explicitly confirmed «Только что набрал и нажал Option». This is an actual failure for fresh Option in that field; prior Codex Space/Option acceptance remains scoped and valid.

## Installed baseline
Next1.5.0 binary98e652ed2290c370f262cb2b8b9e84436011138d160db179883a7f29405237e2, autoSwitch=true. Workspace clean at546f3f953fdb137048cbee623901c7f2618995b6 before planning. Source routing confirms readable empty AX capture uses conversionPermit/legacy AX path, while buffered execution is only chosen with nil conversionPermit. Screenshot does not independently reveal which legacy preflight/setter/readback guard failed.

## Scope and workflow
G33 brief/spec/T38 recorded before fresh executor. No dictionary expansion (RVCA not present in raw word lists; that alone does not establish detector verdict). Explicit Option must convert independent of dictionary membership. Root handles docs/release, executor product/tests, two fresh independent reviews follow. Local .autopilot tickets are the tracker explicitly required by the user; no remote issue setup or stage permission is needed.

## Validation
Production Engine RED→GREEN, regression suites, final reviews/build/DMG/publication and actual Safari acceptance pending. No private Safari/Codex AX or UI automation, no TCC manipulation, no typed-text logging.

## Confirmed production baseline RED
- RussianWin TIS: «шорты кмсф» immediately before Option; final «шорты кмсф» instead of «шорты rvca», same generic notice. Scratch /tmp/mls-keyboard-engine.uPkxM2.
- ABC TIS: ghbdtn immediately before Option; unchanged instead of привет, notice. Scratch /tmp/mls-keyboard-engine.CeG6iZ.
- First RU fixture used incorrect physical key codes and was discarded; corrected fixture asserts literal source before triggering Option.
This demonstrates the routing defect independently of the real Safari private AX details.
