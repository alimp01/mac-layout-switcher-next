# G35 — общая совместимость замены, 2026-11-10

## Problem
Next1.5.2 screenshot: Codex command palette selected «мзт», generic untouched failure. Previous T38 fixed only freshly observed collapsed-caret stream. Selected/preexisting text still uses guarded AX transaction. Exact actual failing guard is unknown; do not declare a hypothesis proven by screenshot. User wants repeat bugs fixed generally and verification done by agent.

## User-visible solution
Manual conversion changes known selected text (мзт→vpn, кмсф→rvca, ghbdtn→привет), or current word without selection, in supported editable text/search/combobox/palette controls. Preserve prefix/suffix/emoji/caret and input order. Auto Space/Enter/ShiftEnter remains working. Never delete source and then silently lose replacement. Safety refusals preserve text and report accurate actionable reason rather than an undifferentiated generic popup.

## Decisions
1. Investigate production replacement from capture through source/selection/capability preflight, mutation, readback and cancellation. Audit common conditions rather than adding app names without evidence.
2. Use captured positive text/selection/focus authority for explicit selection/preexisting operations. No blind conversion of unknown old content. Fresh observed input keeps authorized Next buffered route.
3. Select a single transport before any mutation. When the exact desired selection already exists, do not require or issue an unnecessary selection change. Investigate this only with meaningful baseline regression.
4. Editable search/combobox controls may expose different AX capabilities; distinguish text-editable from readonly/non-text/secure controls using actual capabilities. Do not blanket-allow any focused role.
5. Keep permit/focus/PID/source/value/selection guards, secure-input protection, cancellation, no retry after potentially applied write, and honest partial recovery. No blocking AX/TIS/filesystem in tap. No clipboard fallback unless separately justified and recorded; no dictionary changes.
6. If generic refusal obscures diagnosis, add content-free stage reason returned by the real path, not guessed from a later probe. No typed-text logs or OS permission blame without evidence.
7. Root owns docs/version/git/release. Fresh executor T40 owns code/tests; two independent reviews. Current1.5.2 and stable1.4.12 retained until validated successor.

## Verification
Highest existing native production Engine/SelectionConverter/InputFocusGuard/SystemDictationAccessibility seams, not duplicate algorithm or implementation-mirroring test. Reproduce baseline failures then compare literal outcomes on final code with same fixtures. Matrix: NSTextField/NSTextView, editable/noneditable NSComboBox, owned WebKit input/textarea/contenteditable/palette-like field where feasible; selected word/phrase, empty selection fresh/preexisting word, unsupported setter/no-op setter, already-correct selection, no selection setter, prefixes/suffixes/emoji/multiline, undo, source/caret/field/PID/input/security change, partial/cancel/no retry, auto boundaries and rapid input. Keep exact source/provenance; no app names in fixture equals proof of actual app.
Actual app checks only via permitted CUA, separate from native fixtures. CUA rejected modifier-only Alt_L on08.11; Control+Space/Control+Option+Space OS shortcuts disabled. Safari showed ordinary Russian typing, not proof of auto-correction. Do not repeat hanging SystemUIServer getApp (877s). Do not bypass any denied Codex/stable UI with shell/AX/CDP. If necessary use a temporary existing configurable chord via an authorized app setting and restore it; label this as replacement-path validation, not physical Option-key acceptance. Record tested/version/method/result and untested fields explicitly.
Full relevant native regressions, actual Linux Swift tests, native speech build, mounted signed DMG and published source hashes. User screenshot is new actual failure; G33 remains unaccepted. No universal100% promise.

## Out of scope
Dictionary expansion, changes to stable app/repository/update archive, redesign of speech, forced writes into secure or unidentified fields, permanent user preference changes, private UI access bypass.
