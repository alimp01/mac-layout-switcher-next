# G33 / T38 — Next Option routing QA, 2026-11-08

## User evidence
Screenshot Safari / yandex.ru, text «шорты кмсф», Next generic verified-replacement failure notice. User explicitly confirmed «Только что набрал и нажал Option». This is an actual failure for fresh Option in that field; prior Codex Space/Option acceptance remains scoped and valid.

## Installed baseline
Next1.5.0 binary98e652ed2290c370f262cb2b8b9e84436011138d160db179883a7f29405237e2, autoSwitch=true. Workspace clean at546f3f953fdb137048cbee623901c7f2618995b6 before planning. Source routing confirms readable empty AX capture uses conversionPermit/legacy AX path, while buffered execution is only chosen with nil conversionPermit. Screenshot does not independently reveal which legacy preflight/setter/readback guard failed.

## Scope and workflow
G33 brief/spec/T38 recorded before fresh executor. No dictionary expansion (RVCA not present in raw word lists; that alone does not establish detector verdict). Explicit Option must convert independent of dictionary membership. Root handles docs/release, executor product/tests, two fresh independent reviews follow. Local .autopilot tickets are the tracker explicitly required by the user; no remote issue setup or stage permission is needed.

## Validation
Production Engine RED→GREEN, two final reviews, Linux110/0, native checks and full speech/DMG completed. Publication/installation follows; actual Safari acceptance remains pending. No private Safari/Codex AX or UI automation, no TCC manipulation, no typed-text logging.

## Confirmed production baseline RED
- RussianWin TIS: «шорты кмсф» immediately before Option; final «шорты кмсф» instead of «шорты rvca», same generic notice. Scratch /tmp/mls-keyboard-engine.uPkxM2.
- ABC TIS: ghbdtn immediately before Option; unchanged instead of привет, notice. Scratch /tmp/mls-keyboard-engine.CeG6iZ.
- First RU fixture used incorrect physical key codes and was discarded; corrected fixture asserts literal source before triggering Option.
This demonstrates the routing defect independently of the real Safari private AX details.

## Final implementation and provenance
Code commit 5069c7b0f6b27d6bc2db68c057fdda30fec1514e. Fresh observed words select buffered Backspace/Unicode before legacy mutation even when AX is readable. A readonly BufferedSource binds full value, collapsed caret, source suffix/boundary and target/permit; guards run before deletion and between complete key pairs. Initial nil AX cache no longer discards freshly observed input. Selected/preexisting text keeps the retained AX path.
Untouched cancellation preserves newly delivered input; interruption after mutation discards withheld-input tracking in the same generation. No retry, no clipboard fallback or dictionary changes.

Final 108-file manifest SHA256 5ec38dad3053cf146e5cc1541f06b2c13ed9c4bc3d0919d9030155a9fa56eb25. Both independent Spec and Standards reviews APPROVE, zero findings. Product matches build/review manifest 5664465d696128258d8cc624b4afe94a8857b74348e0f9f648768d50ef33522f; final delta is only bounded readiness in two harness files. All final files verified against frozen hashes.

## Executed checks
- Same final fixture on baseline546f3f9: English and Russian literal replacement RED (9NO37k); final production routing GREEN. Same-body comparison is saved.
- Cancellation before deletion RED→GREEN, and cancellation after one deletion with withheld input RED→GREEN. Independent final b5zNm6 verifies both layouts, initial/cache cases, focus/caret/value/security/input guards, undo, selected/preexisting text and no retry.
- Full native production run6fNJ6c: 29 passing groups including160 navigation combinations. One older protected-PID test failed its fixed250ms readiness window under load. Exact same binary rerun passed. Test-only repair now awaits the existing cache seam with a bound; repaired protected suite eiRIh1 and retained AX8groups fHdMte passed. Assertions preserved. Do not describe the initial full run as wholly green.
- Keyboard adapter, own-process WebKit and root dictation adapter passed. These use AppKit/controlled final-event boundaries, not real Safari WindowServer delivery.
- Actual Linux Swift6.0.3 swift test:110 tests,0 failures, exact code5069c7b. Final Sources/Tests/Package inputs byte-identical; parity receipt saved. Native assertion adapter is supplemental, not XCTest.
- Full native arm64 speech build passed. DMG mounted readonly and detached; deep/strict signature, every bundled file, helper/resources and Applications symlink verified. Binary424068d1e12854912ab7c9f9abb86188793f15333bba2384a5ebe1ca70721bdb; DMGbdcdecfdc1e5b3f6a5637ff46850e36e54fa97a52031ed91b6b972a30887ae9d.

## Acceptance and release boundary
Next1.5.1 is the candidate for the reported Safari fresh Option case. Physical Safari acceptance pending; previous accepted Codex Space/Option was version1.5.0. Do not infer all-window, brand auto-detection or speech acceptance. No private user UI/AX automation, TCC manipulation or typed-text logging used. Evidence lives in audit/next-option-routing; SHA256SUMS files refer to original complete scratch, only textual evidence is committed.
