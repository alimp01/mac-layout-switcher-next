#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
lifecycle_dir=$(mktemp -d /tmp/mls-resume-lifecycle.XXXXXX)
lifecycle_root="${MLS_LIFECYCLE_SOURCE_ROOT:-$PWD}"
printf 'Resume lifecycle scratch: %s\n' "$lifecycle_dir"
python3 - "$lifecycle_root" "$lifecycle_dir" <<'PY'
import difflib, hashlib, json, os, subprocess, sys
from pathlib import Path
root, dest = map(Path, sys.argv[1:])
base = os.environ.get('MLS_LIFECYCLE_BASE_REF')
records, patches = [], []
def exact(text, old, new, count=1):
    assert text.count(old) == count, f'boundary drift: {old!r}'
    return text.replace(old, new)
paths = sorted(root.glob('Sources/MacLayoutSwitcher/**/*.swift')) + sorted(root.glob('Sources/SwitcherCore/*.swift'))
for path in paths:
    relative = path.relative_to(root)
    before = subprocess.check_output(['git', 'show', f'{base}:{relative}'], cwd=root, text=True) if base else path.read_text()
    text = before
    if relative.parts[1] == 'SwitcherCore':
        target = dest/'SwitcherCore'/path.name
    else:
        target = dest/('AppDelegate.swift' if path.name == 'main.swift' else path.name)
    if path.name == 'main.swift':
        text = exact(text, 'private let config = Config()', 'private let config = Config(directory: harnessConfigDirectory)')
        text = exact(text, 'CaptureSessionGuard(directory: config.directory)',
                     'CaptureSessionGuard(directory: config.directory, applications: { [] }, notifications: NotificationCenter())')
        offset = text.index('\nlet app = NSApplication.shared\n')
        text = text[:offset] + '\n#endif\n'
        text = text.replace('alert.runModal()', 'harnessAlert(alert)')
    elif path.name == 'StatusBarUI.swift':
        start = text.index('    public func install() {')
        end = text.index('\n    /// Обновляет', start)
        text = text[:start] + '    public func install() { harnessMenus.append(buildMenu()); refresh() }\n' + text[end:]
    elif path.name == 'Permissions.swift':
        text = exact(text, '        AXIsProcessTrusted()', '        true')
    elif path.name == 'EventTap.swift':
        text = exact(text, 'CGEvent.tapCreate(', 'harnessTapCreate(')
        text = exact(text, 'CGEvent.tapEnable(', 'harnessTapEnable(', 3)
    elif path.name == 'InputFocusGuard.swift':
        text = exact(text, 'NSWorkspace.shared.frontmostApplication?.processIdentifier', 'Optional(pid_t(12345))', 2)
    elif path.name == 'DictationTarget.swift':
        text = exact(text, 'var isTrusted: Bool { AXIsProcessTrusted() }', 'var isTrusted: Bool { harnessFocusTrust() }')
    target.parent.mkdir(exist_ok=True)
    target.write_text(text)
    records.append({'source': str(relative), 'base': base, 'source_sha256': hashlib.sha256(before.encode()).hexdigest(),
                    'compiled_sha256': hashlib.sha256(text.encode()).hexdigest(), 'transformed': before != text})
    patches.extend(difflib.unified_diff(before.splitlines(True), text.splitlines(True), fromfile=str(relative), tofile=str(target)))
(dest/'source-provenance.json').write_text(json.dumps(records, indent=2)+'\n')
(dest/'seams.patch').write_text(''.join(patches))
PY
cp tools/lifecycle-harness/resume.swift "$lifecycle_dir/main.swift"
cp tools/lifecycle-harness/resume-boundary.swift "$lifecycle_dir/boundary.swift"
swiftc -emit-library -emit-module -module-name SwitcherCore "$lifecycle_dir"/SwitcherCore/*.swift -o "$lifecycle_dir/libSwitcherCore.dylib" -emit-module-path "$lifecycle_dir/SwitcherCore.swiftmodule"
swiftc -I "$lifecycle_dir" -L "$lifecycle_dir" -lSwitcherCore -Xlinker -rpath -Xlinker "$lifecycle_dir" "$lifecycle_dir"/*.swift -o "$lifecycle_dir/test-resume"
lifecycle_status=0
"$lifecycle_dir/test-resume" "$lifecycle_dir/config" > "$lifecycle_dir/run.log" 2>&1 || lifecycle_status=$?
"$lifecycle_dir/test-resume" "$lifecycle_dir/config-engine" --engine > "$lifecycle_dir/engine.log" 2>&1 || lifecycle_status=$?
cat "$lifecycle_dir/run.log" "$lifecycle_dir/engine.log"
(cd "$lifecycle_dir" && find . -type f ! -name SHA256SUMS -exec shasum -a 256 {} \;) > "$lifecycle_dir/SHA256SUMS"
exit "$lifecycle_status"
