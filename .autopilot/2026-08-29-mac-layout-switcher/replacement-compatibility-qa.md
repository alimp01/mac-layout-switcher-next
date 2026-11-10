# G35/T40 — QA,2026-11-10

## Baseline
Installed Next1.5.2 binary50a18d7396b11bee9423555c7be94f390821f18c1f9eb522f6bcaf31327bb41d; publicmain5c2d1c1298f4fa19ba3fb68ea56cb021b1b425bd confirmed10.11. User screenshot: Codex command palette selected мзт, generic unchanged notice. Exact triggering sequence/actual refusing guard remains unknown.
Prior1.5.2 published08.11 and installed; user confirmed permissions/relaunch. G34done. G33 Safari not physically accepted. Earlier08.11 CUA entered literal шорты кмсф but modifier-only Alt_L unsupported; both system input-source shortcuts disabled, so observed привет was ordinary Russian input rather than a conversion. SystemUIServer call hung877s and was aborted by user.

## Investigation
Target.replace already skips a redundant selection setter when desired selection equals original; hypothesis discarded. SystemDictationAccessibility Unicode eligibility instead requires range and value setters and rejects AXComboBox regardless of editability. Owned AppKit audit: editable NSComboBox AXValue settable true, readonly false; readonly NSTextView still range-settable, so range mutability cannot prove editability.
Initial executor fixture /tmp/mls-system-focus.cNcedZ returned untouched with sourceмзт and zero writes, but was NOT an isolated range-capability regression: detached NSTextView reported AXEnabled=false. Discard this run as causal proof. Executor is correcting native enabled metadata and rerunning exact baseline/final; do not count initial log as meaningful RED. Target already skips redundant selection setter. Independent static/native capability audit remains valid; actual Codex guard remains unknown.

## Live attempt10.11
User asked agent to test. Temporarily configured existing convert shortcut Ctrl+Shift+F12 because CUA cannot emit lone Option; kept a local backup and restored original Option after attempt. Only own test text in a new Safari Yandex tab. Native CUA AX read confirmed selected queryмзт; after chord no new field state returned. Next UI lookup timed out; subsequent screenshot/completion calls aborted before dispatch. This is INCONCLUSIVE, no live correction claimed. Original modifier-only Option restored; installed Next process73880 verified afterward. No denied-app AX/CDP/shell UI access used. No private browser contents/screenshots are committed.

## Pending
Meaningful baseline→final regression matrix; exact source freeze, independent Spec/Standards reviews; Linux/native/speech/DMG/release. Actual Codex palette and Safari result must be labeled separately from owned fixtures; no universal guarantee.

## Access review10.11 after user «продолжай»
Scoped Safari getApp was explicitly rejected by automatic access review because selecting the app reads the current window and it might be the authenticated VPS panel. No bypass attempted. Asked user explicit approval or to make Yandex the active tab first. Temporary plain F12 binding was restored immediately to Option; Next PID76860 afterward. Approval pending. Generic native tests continue independently. First executor provider403 failure is infrastructure, not a test failure; fresh retry executor continues preserved WIP per autopilot.
