# Native keyboard regression fixtures — Next

`bash tools/test-keyboard-next.sh` exercises the production EventTap parser,
KeyTranslator, Engine, EngineCore, Typist and optional InputFocusGuard with no
AX target, using owned unshown NSTextViews. `bash tools/test-keyboard-engine.sh`
runs this suite and then the retained AX Option suite. `MLS_OPTION_ONLY=1`
selects only the latter; `MLS_PHYSICAL_ONLY=1` selects the Next suite. No live
application, global tap, input-source selection, TCC, clipboard or microphone
is accessed. The GigaAM coordinator's interruption fixture is explicitly paused.

The old automatic AX-selection hooks have been moved to the appropriate seam:
new buffered auto cancellation uses a held-modifier preflight and native
navigation/click/tap events; partial mutation uses a final-post interruption.
AX hooks still cover selected/preexisting Option capture and replacement.
The original navigation matrix covers normal/repeated arrows, Home/End,
Escape, F1/F12 and Forward Delete in auto, Option capture, Option write and idle
phases. Tap timeout/user interruption retains shortcut, modifier, dictation and
recorder ownership tests. Enter/ShiftEnter/Tab repeats and rapid letters follow
complete replacement; a posted key-down always receives its matching key-up.

The Next suite additionally checks nil-AX Space/Option/live, protected AX fields
with global SecureInput off, PID/secure/recorder/click/tap cancellation,
400 ms held-modifier timeout, interrupted deletion recovery without retry,
Chromium/Electron and edited-word live gates, undo and an emoji at a UTF-16
chunk boundary. Assertions observe literal editor text, separator-time text,
original flags, generated event pairs and the owned recovery panel.

Every runner prints its frozen scratch directory and records source hashes,
compiled sources, resource data, seam diff, run output and checksums. System
boundaries are injected: foreground metadata, secure/modifier state, framework
classification, AX, inert tap registration, local layout selection and final
CGEvent post. Production event creation and CGEvent → NSEvent interpretation
remain in use. Native physical key identities are resolved at the receiver
because this local fixture has no WindowServer; final posting is not proof of
cross-process delivery or confirmed editor readback by the product.

TIS is pinned to an enabled immutable `com.apple.keylayout.ABC` by default.
The dedicated `MLS_NEXT_REPAIR=caret` case uses
`MLS_FIXTURE_INPUT_SOURCE_ID=com.apple.keylayout.RussianWin` without changing
macOS. The default full Next runner also invokes that Russian fixture plus the
manual-choice and snippet/prefix repair cases against the same frozen binary. The raw TIS source and uchr blob
are retained/copied and SHA-256 logged; the production translator warms before
input and can refresh safely even if the user's real layout changes. AX-ready
scenarios wait up to three seconds for readiness; nil-AX cases assert absence.

T37 literal baseline RED snapshots (stable pre-port source):
`/tmp/mls-keyboard-engine.bCRzvB` leaves `ghbdtn ` after Space;
`/tmp/mls-keyboard-engine.FZc372` leaves `ghbdtn` after Option.
Both preserve source-provenance and checksum manifests. Their local outcomes
are independent of hardware acceptance. Restricted builds use
`CLANG_MODULE_CACHE_PATH=/tmp/mls-t37-clang-cache` and
`SWIFT_MODULECACHE_PATH=/tmp/mls-t37-swift-cache`.

The following notes document the retained AX adapter suites and historical
stable regressions. Historical auto-selection scenarios are now represented by
the buffered-post equivalents above, while selected/preexisting/dictation AX
readback checks remain applicable.

`test-keyboard-adapter.sh` separately checks Target/Typist failure and recovery
outcomes plus production Unicode payload generation; its local AppKit checks
also do not establish hardware/WindowServer delivery.

Run `bash tools/test-keyboard-selection-delay.sh` for delayed AX selection and
restoration ACKs through exact Target/Typist/SelectionConverter source copies.
The system seam acknowledges a range before applying it to the private
NSTextView. Physical separators then use native keyDown, so the baseline
source deletion is an actual edit in that view. Unicode uses production
CGEvent generation. Local receiving events run on the main thread, as a native
receiver does; no WindowServer or external posting is involved. Each printed
scratch directory preserves source copies, `SOURCE-SHA256SUMS` and `run.log`.
Baseline: `MLS_SELECTION_BASE_REF=c0be78e bash tools/test-keyboard-selection-delay.sh`.
To isolate preselected conversion, add `MLS_SELECTION_CASE=preselected`.

Run `bash tools/test-keyboard-webkit.sh` for the Safari routing regression.
The baseline command is `MLS_WEBKIT_BASE_REF=ef8be979 bash
tools/test-keyboard-webkit.sh`; it changes only DictationTarget.swift from that
commit. The same real system WebKit input advertises a selected-text setter,
applies AX selection, but the text setter leaves the source unchanged. With the
Safari route selected before mutation, the literal `шднф` becomes `ilya ` once
and the caret reaches 5. This reflects WebCore's empty `setSelectedText`
implementation, unlike its implemented range setter.

This runner uses deprecated in-process WebView deliberately: its actual
WebCore accessibility wrapper is accessible without TCC. WKWebView's remote
AX tree is not accessed. Process bundle lookup is replaced by a private fixture
bundle identifying Safari; input focus/security and observer registration are
injected. Native Unicode construction/serialization is unchanged, but the final
receiver is the fixture's WebHTMLView, with no global or cross-process post.
Enter/ShiftEnter/Tab are inspected at the final post boundary after DOM readback;
ordinary rapid input is interpreted by WebKit. Tests also cover Option word and
selected text, emoji/context, source/focus/cancellation, readonly controls,
partial/no-op recovery, and the shared chunked dictation route. The printed
scratch directory retains original/compiled sources, exact seam description,
SHA256 manifest and run.log. These are local WebKit tests, not live Safari or
physical WindowServer acceptance.

For Option capture regressions, run `MLS_OPTION_ONLY=1 bash
tools/test-keyboard-engine.sh`. The full runner also includes these cases.
The test changes focus between private NSTextViews before the next sampler
turn, verifying literal `context ghbdtn` → `context привет` and unchanged
previous-field content. It covers same-field buffered and preexisting words,
selection precedence, recent undo, empty layout switching, lazy AX bootstrap,
process trust/secure/field/range/text refusal, and field/PID/caret/key/click
cancellation during capture. An external context change during the last AX
read must also cancel before any of the three write routes starts. Bootstrap
may replace a non-editable wrapper, but cannot follow a different text field.

The production base for the fresh-field failure is 99a536c236f18a42e0a8a4bc1291bd74eacd3562.
Use `MLS_ENGINE_SOURCE_ROOT=/absolute/baseline MLS_OPTION_ONLY=1 bash
tools/test-keyboard-engine.sh` with all baseline Sources materialized there;
`MLS_ENGINE_BASE_REF` alone changes only Engine and is insufficient here.
The first Option test fails with unchanged `context ghbdtn` on that base.
Set `CLANG_MODULE_CACHE_PATH=/tmp/mls-swift-module-cache` and
`SWIFT_MODULECACHE_PATH=/tmp/mls-swift-module-cache` in restricted workspaces.
No real cross-process AX trust, live Codex, or general application acceptance
is established by these injected system-boundary tests.

For physical-input integrity, run `MLS_PHYSICAL_ONLY=1 bash
tools/test-keyboard-engine.sh`. Add `MLS_PHYSICAL_GROUP=navigation` or
`MLS_PHYSICAL_GROUP=interruption` to isolate a group. The full runner includes
both; `MLS_OPTION_ONLY=1` retains the separate Option-only scope.

Navigation covers ordinary and repeated Left/Right/Up/Down/Home/End/Escape,
F1/F12 and Forward Delete during auto correction, pending Option capture,
Option replacement and idle, on both AX and Unicode routes. Events must pass,
the literal source must remain unchanged, no synthetic control text may be
posted, and the next ordinary Space must pass after the stale candidate resets.
The application-specific navigation action is deliberately not delivered to the
private editor; these tests establish cancellation and native pass decisions.

Timeout and user-input tap interruptions omit shortcut key-up, then require a
fresh ordinary key pair to pass. Convert, toggle, modifier-only Option,
dictation hold and pending replacement are covered. The dictation coordinator
is paused in that case, so its real gesture/cancellation path cannot start a
microphone or model preparation. Counterexamples retain held shortcut repeats
and key-up across ordinary clicks, and verify recorder transitions do not
dispatch stale modifier gestures. Key-up checks include passed pairs as well
as suppressed pairs.

The T30 baseline requires the pre-fix `Engine.swift`, `EventTap.swift`,
`KeyStroke.swift` and `KeyTranslator.swift` together under an
`MLS_ENGINE_SOURCE_ROOT`; overriding only Engine is insufficient after the new
tap-interruption event kind. The unchanged regression sources then fail on
ordinary Left suppression and consumed-shortcut ownership respectively.


Run `bash tools/test-system-focus.sh` for the shared system focus resolver.
Unlike the earlier fixtures, this compiles the production
`SystemDictationAccessibility.focusedElement` unchanged. Only raw AX C calls
(read/write/capability/owner/timeout/trust) and SecureInput are intercepted;
opaque synthetic AX references cannot reach another process. Editor text and
selection use an owned, unshown NSTextView. The runner freezes originals,
compiled copies, the complete seam diff, source hashes and output under /tmp,
and gives Swift an explicit module-cache directory there.

The first regression is a valid system-focused field while the application
AXFrontmost RPC fails. The second is a positive foreign system focus while the
application still reports its old focused field. The former must permit the
literal `before ghbdtn after` → `before привет after`; the latter must refuse
without a text write. Explicit AXFrontmost=false, malformed focus values and
unknown field owners remain fail-closed. The harness also checks raw errors,
missing PID, bounded bootstrap, Option word/selection/empty capture, automatic
separators, source/caret preservation, readonly/secure targets, cancellation,
and matching keyboard/dictation error details without user text.

Use `MLS_FOCUS_BASE_REF=01ec68262fb1f4c663a9ae6560410223a116cb00 bash
tools/test-system-focus.sh` for the pre-fix baseline; it freezes all relevant
production files at that revision and keeps the same final fixture. Baseline
fails the two focus rules and the new diagnostic assertions. These injected
raw-RPC faults demonstrate resolver behavior, not that either fault occurred
in the user's installed app. They do not establish live AX/WindowServer or
user acceptance; the precise remaining real-app cause is still unknown.


G27 adds a Chromium 155 bootstrap regression at these same raw boundaries.
The fixture supplies process launch/bundle metadata and intercepts the final
CGEvent process post into its own unshown NSTextView; Chromium detection,
resolver, event construction, text and caret readback remain production code.
The hidden NSTextView reports AXEnabled=false, so the synthetic Chromium
metadata reports its own editor's isEditable for that attribute. No live app,
WindowServer input, clipboard or user editor is accessed.

With AXFrontmost=true and both focus queries returning AXError.noValue, a
rejected AXManualAccessibility call can fall back to AXEnhancedUserInterface
only for a detected Chromium framework. The raw fixture delays its tree for
2.05 seconds. An explicit request with no original field only prepares access;
a fresh request after the tree appears must convert literal ghbdtn once. The
same fixture checks readback errors, setter-error-but-actual-field-available,
unsupported native apps, single activation across adapter instances, PID reuse,
temporary missing launch metadata, 32 live-process capacity, off-main Option,
programmatic field changes, cancellation, and three bounded capture attempts.
Metadata/launch changes before activation must reject the in-flight capture.

Use `GIT_DIR=/tmp/mls-g26-git-store MLS_FOCUS_BASE_REF=cd68fedfe0cd2996a4f6f1383d2c03929d3deec2 bash tools/test-system-focus.sh`
when the alternate Git store is available, or omit GIT_DIR in a normal checkout.
The same final fixture fails against that 1.4.9 baseline. These are headless
compatibility/safety proofs; installed Codex Option/auto/dictation acceptance
remains a separate user test.

G28 uses literal framework directories inside an unrelated `Renamed.app` name.
The user confirmed native Bitrix24 as the failing app. Its installed metadata
identifies `BrowserCrApplication`, Chromium branch 7727 (147), and `Bitrix24
Framework.framework`. Installed Yandex metadata independently identifies Chromium
150 and `Yandex Framework.framework`. Both matching Chromium branches implement
the enhanced activation hook. The raw fixture reproduces rejected manual
accessibility plus missing focus for these exact directories, including a fresh
Bitrix24 Option conversion of literal `зщкефд` to `portal` without submission.
The initial request only prepares access, repeated samples
do not restart activation, and fresh Option/automatic requests must use verified
Unicode before a no-op advertised AXSelectedText setter. Full text, caret and
separator delivery are checked alongside all six previously supported families,
unknown/lookalike frameworks, read-only controls, process changes and cancellation.
Use `MLS_FOCUS_BASE_REF=d82a6748ec1c8b523c77c119bbaed3c6fd4637a4` for the
unchanged final fixture's 1.4.10 RED baseline. Actual installed Bitrix24 acceptance
remains independent of these synthetic tests.


G29 adds the Spotlight overlay to the same raw seam. The foreground application's
AXFrontmost is true while the system field belongs to a separate Spotlight PID
whose AXFrontmost is false. Initial capture requires the exact Apple bundle ID,
canonical system bundle/executable paths, and a live kernel process start
(seconds and microseconds from a full, matching-PID `proc_pidinfo` response).
The literal fixture supplies a nil Cocoa launchDate, matching the installed
Spotlight process metadata; no synthetic date substitutes for process identity.
Only raw NSRunningApplication/process metadata, AX calls and final process posts
are substituted. AXObserverCreate creates an observer for this harness's own
process; notification registration is intercepted and never touches a real field.

Option word/selection and direct/Unicode dictation produce literal `привет` from
owned fixture text, checking the actual target/observer/Unicode PID and exact
full value/caret. Automatic Space is in the replacement; Enter/Shift+Enter retain
only their original key pair and flags. Physical replay transport remains the
existing global HID/native-navigation path, licensed by the exact current field;
the fixture inspects generated events and its own receiver routing. It does not
prove WindowServer delivery. As with Chromium fixtures, the hidden Spotlight
fixture reports AXEnabled from its own editor's isEditable.

The same tests reject ordinary foreign focus, spoof identity/path metadata,
missing/truncated/wrong-PID kernel metadata, terminated/replaced processes,
changed elements, readonly/secure controls and cancelled requests. Captured
Spotlight always requires the exact system field, even if AXFrontmost becomes
true and its application-focus attribute remains stale. The same rules apply
when NSWorkspace initially names Spotlight directly, including true/missing
AXFrontmost and unavailable kernel identity. Ordinary process metadata is
checked across initial resolution so a restart cannot enable a replacement
process during bootstrap. Missing initial range
requires a fresh request without background or Spotlight preparation. A native
bootstrap retry cannot select a newly opened Spotlight. An unreadable owner PID
also refuses bootstrap instead of mutating the unconfirmed menu application.

Use `MLS_FOCUS_BASE_REF=6241c86d769382413cbb6e63f59816ada55e2ee5 bash tools/test-system-focus.sh`
for the same-fixture 1.4.11 baseline (plus the alternate GIT_DIR where required).
The original Spotlight Option failure is exactly `AXFrontmost=ok;
SystemFocus=foreign-owner; AppFocus=not-read`. All fixture text is generated by
the harness; no live private AX/UI, microphone, clipboard, or user text is read.
Physical Spotlight acceptance remains a separate user check.


The Engine fixture freezes a real TIS input source and copies its uchr data at
startup, logging the source ID, byte count and SHA256. The retained source and
immutable CFData copy outlive every raw property read; production KeyTranslator
still performs UCKeyTranslate and all modifier math. The runner records these
two raw TIS substitutions in seams.patch. `MLS_FIXTURE_INPUT_SOURCE_ID` can choose
an available source by ID for a read-only RU/EN startup check; it never selects
that source in macOS. The default is enabled ABC; only ABC/RussianWin are accepted.
The literal source-before-separator assertion remains in place.

This test-only stabilization follows a recorded invalid run where startup key5
was `g`, but later real TIS reads produced `п` and typed `привет` instead of the
fixture's expected `ghbdtn` before any correction. Such user layout changes are
not a product failure. The additional capture-final process validation applies
only to Spotlight; native/Chromium samples retain their existing number of AX
round trips. That historical fixture change did not alter Engine/Typist; Next now has the separately documented buffered transport above.

The Engine fixture also waits up to three seconds for a cached target before
ready-field scenarios. Its existing test seam exposes only cached readiness,
with no AX work; genuine early input before capture remains covered by the
adapter's cold-bind tests. The two successful Option bootstrap cases wait for
the literal expected text under the same bounded deadline. Their assertions,
source-before-separator check, and all cancellation/changed-field expectations
remain intact. A controlled stable-ABC run showed the old fixed startup delay
could still precede initial capture: the separator passed natively, while the
same fixture with additional readiness time started its correction. This is
fixture synchronization, not a change to the production early-input policy.
