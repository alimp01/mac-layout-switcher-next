#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
engine_probe_dir=$(mktemp -d /tmp/mls-keyboard-engine.XXXXXX)
engine_source_root="${MLS_ENGINE_SOURCE_ROOT:-$PWD}"
engine_source_file="$engine_source_root/Sources/MacLayoutSwitcher/Engine.swift"
if [[ -n "${MLS_ENGINE_BASE_REF:-}" ]]; then
    git show "${MLS_ENGINE_BASE_REF}:Sources/MacLayoutSwitcher/Engine.swift" > "$engine_probe_dir/baseline-Engine.swift.txt"
    engine_source_file="$engine_probe_dir/baseline-Engine.swift.txt"
fi
printf 'Engine regression scratch: %s\n' "$engine_probe_dir"
python3 - "$engine_source_root" "$engine_source_file" "$engine_probe_dir" <<'PY'
import difflib, hashlib, json, shutil, sys
from pathlib import Path
root, engine, dest = map(Path, sys.argv[1:])
files = ['System/KeyboardEnvironment.swift', 'System/TrackedInputBatch.swift', 'Engine.swift', 'Config.swift', 'System/InputFocusGuard.swift', 'System/Typist.swift',
 'System/SelectionConverter.swift', 'System/SecureInput.swift', 'System/FrontApp.swift',
 'System/EventTap.swift', 'System/KeyTranslator.swift', 'System/KeyStroke.swift',
 'Speech/DictationTarget.swift', 'Speech/DictationCoordinator.swift', 'Speech/DictationRecorder.swift',
 'System/SpeechModelStore.swift', 'System/SpeechRecognitionProcess.swift',
 'UI/DictationPanel.swift', 'UI/ConversionNotice.swift', 'UI/Sounds.swift']
records, patch = [], []
def exact(source, old, new, count=1):
    assert source.count(old) == count, f'Boundary rewrite drift: {old!r}'
    return source.replace(old, new)
for name in files:
    path = engine if name == 'Engine.swift' else root/'Sources/MacLayoutSwitcher'/name
    before = path.read_text()
    source = before
    if name == 'Engine.swift':
        source = exact(source, 'let detector = Detector()', 'let detector = Detector(dataDirectory: URL(fileURLWithPath: '+json.dumps(str(dest/'SwitcherCore/Resources'))+'))')
        source = exact(source, 'NSWorkspace.shared.frontmostApplication?.processIdentifier', 'Optional(harnessFrontPID)')
        source = exact(source, 'tap.start {', 'tap.installProbeHandler {')
        source = exact(source, 'ConversionNotice()', 'ConversionNotice(presentsWindow: false)')
        source = exact(source, '    private func isExcludedApp() -> Bool {',
          '    func probeEvent(_ event: CGEvent) -> TapDecision { tap.process(type: event.type, event: event) }\n    var probeFocusReady: Bool { inputFocus.ticket != nil }\n\n    private func isExcludedApp() -> Bool {')
    elif name == 'System/KeyboardEnvironment.swift':
        source = exact(source, 'NSWorkspace.shared.frontmostApplication?.processIdentifier', 'Optional(harnessFrontPID)')
        source = exact(source, 'Self.isChromium(pid: nextPID, bundleID: nextBundle)', 'currentFixture.chromium')
    elif name == 'System/TrackedInputBatch.swift':
        source = exact(source, 'NSWorkspace.shared.frontmostApplication?.processIdentifier', 'Optional(harnessFrontPID)')
        source = exact(source, 'CGEventSource.flagsState(.combinedSessionState)', 'mainValue { currentFixture.physicalModifiers }')
    elif name == 'System/InputFocusGuard.swift':
        source = exact(source, 'SystemDictationAccessibility()', 'harnessAccessibility', 2)
        source = exact(source, 'NSWorkspace.shared.frontmostApplication?.processIdentifier', 'Optional(harnessFrontPID)', 2)
    elif name == 'System/Typist.swift':
        # Preserve production Self.post marker and delay; replace only final post.
        source = exact(source, 'event.post(tap: .cghidEventTap)', 'harnessPost(event)')
    elif name == 'System/EventTap.swift':
        source = exact(source, '    private func process(type: CGEventType, event: CGEvent) -> TapDecision {',
          '    func process(type: CGEventType, event: CGEvent) -> TapDecision {')
        source = exact(source, '    public init() {}',
          '    public init() {}\n    func installProbeHandler(handler: @escaping (KeyStroke) -> TapDecision) -> Bool { self.handler = handler; return true }')
    elif name == 'System/KeyTranslator.swift':
        # Retain native translation, but freeze the read-only TIS input for the
        # fixture so concurrent user layout changes cannot change its source.
        source = exact(source, 'TISCopyCurrentKeyboardInputSource()', 'harnessCopyKeyboardInputSource()')
        source = exact(source, 'TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)', 'harnessKeyboardLayoutData(source)')
    elif name == 'System/SecureInput.swift':
        source = exact(source, '        IsSecureEventInputEnabled()', '        mainValue { currentFixture?.isSecure ?? false }')
    elif name == 'System/FrontApp.swift':
        source = exact(source, '        NSWorkspace.shared.frontmostApplication?.bundleIdentifier', '        "com.example.MLSEngineFixture"')
    target = dest/Path(name).name
    target.write_text(source)
    records.append({'source': str(path), 'source_sha256': hashlib.sha256(before.encode()).hexdigest(),
      'compiled_sha256': hashlib.sha256(source.encode()).hexdigest(), 'transformed': source != before})
    patch.extend(difflib.unified_diff(before.splitlines(True), source.splitlines(True), fromfile=str(path), tofile=str(target)))
shutil.copytree(root/'Sources/SwitcherCore', dest/'SwitcherCore')
for path in sorted(p for p in (root/'Sources/SwitcherCore').rglob('*') if p.is_file()):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    records.append({'source': str(path), 'source_sha256': digest, 'compiled_sha256': digest, 'transformed': False})
shutil.copy(Path.cwd()/'tools/keyboard-harness/next-engine.swift', dest/'main.swift')
shutil.copy(Path.cwd()/'tools/keyboard-harness/engine-boundary.swift', dest/'boundary.swift')
shutil.copy(Path.cwd()/'tools/keyboard-harness/physical-input.swift', dest/'physical-input.swift')
(dest/'source-provenance.json').write_text(json.dumps(records, indent=2)+'\n')
(dest/'seams.patch').write_text(''.join(patch))
PY
swiftc -emit-library -emit-module -module-name SwitcherCore "$engine_probe_dir"/SwitcherCore/*.swift -o "$engine_probe_dir/libSwitcherCore.dylib" -emit-module-path "$engine_probe_dir/SwitcherCore.swiftmodule"
swiftc -I "$engine_probe_dir" -L "$engine_probe_dir" -lSwitcherCore -Xlinker -rpath -Xlinker "$engine_probe_dir" "$engine_probe_dir"/*.swift -o "$engine_probe_dir/test-engine"
engine_test_status=0
"$engine_probe_dir/test-engine" > "$engine_probe_dir/run.log" 2>&1 || engine_test_status=$?
if [[ "$engine_test_status" == "0" && -z "${MLS_NEXT_REPAIR:-}" ]]; then
    for repair in manual snippet protected; do
        MLS_NEXT_REPAIR="$repair" "$engine_probe_dir/test-engine" >> "$engine_probe_dir/run.log" 2>&1 || engine_test_status=$?
    done
    MLS_NEXT_REPAIR=caret MLS_FIXTURE_INPUT_SOURCE_ID=com.apple.keylayout.RussianWin "$engine_probe_dir/test-engine" >> "$engine_probe_dir/run.log" 2>&1 || engine_test_status=$?
    MLS_NEXT_REPAIR=caret MLS_NEXT_CHANGED_APP=1 MLS_FIXTURE_INPUT_SOURCE_ID=com.apple.keylayout.RussianWin "$engine_probe_dir/test-engine" >> "$engine_probe_dir/run.log" 2>&1 || engine_test_status=$?
fi
cat "$engine_probe_dir/run.log"
python3 - "$engine_probe_dir" <<'PY'
from pathlib import Path
import hashlib, sys
root=Path(sys.argv[1])
files=sorted(p for p in root.rglob('*') if p.is_file() and p.name != 'SHA256SUMS')
(root/'SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+str(p.relative_to(root))+'\n' for p in files))
PY
exit "$engine_test_status"
