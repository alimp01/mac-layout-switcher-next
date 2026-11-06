# Third-party language engine in Mac Layout Switcher Next

The language engine is ported from [Keyboop](https://github.com/iffuno/keyboop),
commit **fb9bdde4eb8f13a486974cf102a8bec9d607e5d2**, retrieved 2026-11-06.
It is not a new dictionary assembled for this fork. All four JSON files and the
complete `ExtraWords.swift` are copied byte for byte. `LayoutDetector.swift`
retains the pinned rules, thresholds, normalization, short-word lists, strict
source-word gate, titlecase/uppercase protection, hyphen rules, numeric-neighbour
rules, elongation protection, mixed rescue and live prefix protection.

The MIT notice for Keyboop contributors and the MIT notice for the language data
(**Copyright (c) 2026 Ilya Granin**, [keyswitcher](https://github.com/graninilya/keyswitcher))
are included in `Sources/SwitcherCore/Resources/KEYBOOP_LICENSE.txt` and
`KEYSWITCHER_LICENSE.txt`. The data attribution is recorded in the pinned
Keyboop `THIRD_PARTY.md`; the latter license contains the complete standard MIT
permission and disclaimer, rather than upstream's shortened display excerpt.
SwiftPM packages both notices with the JSON data. Existing GigaAM attribution
remains in `Resources/Licenses/GigaAM-LICENSE.txt`.

`Sources/SwitcherCore/Resources/KEYBOOP_PROVENANCE.json` records the exact origin
commit, source paths, SHA-256 hashes, imported paths, port hashes and resource
entry counts. It is included in the installed SwiftPM resource bundle.

## Deliberate adaptations

- **Per-instance state.** `Detector` keeps its exclusion list and two preceding
  displayed tokens. Upstream `ExceptionStore.shared` reads are replaced with an
  immutable value passed into the decision. Explicit exclusions and undo-learned
  words share our existing persisted exclusion list. We do not import Keyboop's
  force-swap preference UI or global settings. Bare-core and full-token exclusions
  retain their old semantics, and protect mixed rescue as well. `liveVerdict`
  reads this state without advancing context or learning anything.
- **Prepared resources.** All four dictionaries are decoded during construction,
  before input callbacks. `isReady` is false if any original JSON is missing,
  empty or invalid. Boundary/live decisions then return `.unsure`; live
  conversion returns nil. Additional words do not hide a missing base table.
  App `Contents/Resources` and SwiftPM CLI/test bundle locations are supported;
  there is no source-directory fallback, environment override, or callback I/O.
  Explicit `Detector(dataDirectory:)` supports isolated command-line consumers.
- **Existing physical map.** The pure core still uses our fixed ANSI
  QWERTY/JCUKEN `KeyMap`, the same map as manual conversion. Keyboop's dynamic
  macOS table/TIS access is not imported. Compared with its static fallback, our
  map includes shifted `: " { } < > ~` as `Ж Э Х Ъ Б Ю Ё` and their reverse
  mappings. It keeps `/` unchanged and does not map Russian `.` to `/`.
  Thus `K><K>` and `(K><K>)?!` are recognized as `ЛЮБЛЮ`/`(ЛЮБЛЮ)?!`, while the
  upstream static-map fixture keeps them. Smart-quote aliases in the imported
  conversion helper follow upstream. Arbitrary/phonetic keyboard layouts and
  upstream's number-separator manual conversion are outside this detector port.
- **Conversion is part of the decision seam.** `convertedText(for:to:)` ports
  upstream `smartConvert`; `[kt,` becomes `хлеб`, `ghbdtn.` becomes `привет.`.
  `liveConvertedText` ports `liveConvert`; `gthtrk.` must wait (nil), whereas
  `gthtrk.x` becomes `переключ`. A live verdict alone is not permission to
  truncate a punctuation-shaped letter. Engine/platform safety gates remain
  outside the language detector.
- **Mixed input reaches callers.** Upstream calls `mixedRescue` from Engine before
  `decide`. Here `Detector.verdict` combines those decisions, so `привtn`,
  `приdет`, `ghbdет` become `привет`, and `heддщ` becomes `hello`. Both/neither
  dictionary matches remain unchanged; intentional `helloмир` and `API-ключ`
  stay mixed. Unresolved mixed tokens retain the prior context as in our old API.
  Numeric neighbours are retained for upstream's `5 г` protection. Caret-jump
  trust is enforced by the owning engine's fresh-buffer policy; this public
  detector API does not guess whether an input token is a fragment.
- **Technical-token guard retained.** Our explicit identifier protection for
  `+ # _ = @ \\ /` stays ahead of normalization for both boundary and live paths.
  In particular `C++` and `C#` stay unchanged: bare upstream `decide` would strip
  their terminal signs and interpret `C` as the Russian preposition. This is an
  intentional safety difference, tested against literal upstream output.

## Changes to the stable detector contract

The removed bigram heuristic and its narrow word additions no longer decide
tokens. The public `ShortWords` table remains only for compatibility; it does
not override the imported rules. The old tests were changed explicitly:

- Real source words (`of`, `ща`, `her`, `here`, `herb`, `tv`, `ev`, their Russian
  pairs and `vs`) are protected by Keyboop's strict gate, even in the other
  language's context. `ns` becomes `ты` at a fresh/Russian boundary but is kept
  after English; `jq` and `ble` become `ой` and `иду` without that restriction.
- All eight Russian one-letter words still work in either case. An ordinary
  `hello` neighbour no longer prevents them; upstream's explicit classifiers
  such as `plan`, `vitamin` and `model` do. `drive`, `team` and `channel` are not
  upstream classifiers. Numeric `5` protects Cyrillic `г`.
- Mid-phrase titlecase names are protected even when their target is a valid
  Russian word. This intentionally replaces the old claim that every case
  variant must correct in every context. The `yb` collision is kept after EN;
  `хз` is not recognized by the pinned dictionaries, so `[p` is left alone.
- Long tokens with edge digits and surrounding punctuation are now normalized:
  `ghbdtn123`, `!ghbdtn`, `(ghbdtn`, `ghbdtn)` and `ghbdtn()` are candidates.
  Internal digits/URL/code guards remain. `gh` can resolve to the dictionary
  abbreviation `пр`; there is no blanket minimum-three-letter rule.
- Newline/Tab context reset is still tested at `EngineCore`: after `plan` and a
  reset, `b` becomes `и`. Old `ns`-after-reset assertions were unsuitable because
  pinned Keyboop intentionally converts `ns` even with no previous context.

## Reproducible evidence

`Tests/KeyboopParity/inputs.json` is a curated independent input set.
`generate-reference.sh /path/to/keyboop` verifies the exact commit and an
unchanged upstream worktree, then compiles the original `LayoutDetector`,
`LayoutData`, `ExtraWords` and `Keymap` with only UI/process dependencies stubbed.
It reads the original JSON files and writes the checked-in
`Tests/SwitcherCoreTests/Fixtures/keyboop-reference.json`. Expected decisions are
never generated from the port. Tests compare boundary, live and conversion
results, enumerate the deliberate map/technical differences, and separately
test mixed rescue, independent exclusions, context, readiness and preload.

`run-native-tests.py` compiles the same test bodies with a small assertion adapter
for this Mac's CLT, which has no XCTest. This supplemental run is clearly labelled
and does not claim to be Linux `swift test`. `check-packaging.sh` moves the real
SwiftPM resource bundle into a standalone app-shaped directory, checks default
loading, removes it, and checks fail-closed behavior. These are deterministic
language/packaging checks, not real editor acceptance or an accuracy estimate.
