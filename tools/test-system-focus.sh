#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
focus_work=$(mktemp -d /tmp/mls-system-focus.XXXXXX)
mkdir -p "$focus_work/Sources" "$focus_work/Compiled" "$focus_work/modules"
cp -R Sources/SwitcherCore "$focus_work/Sources/"
for name in InputFocusGuard Typist TrackedInputBatch SelectionConverter SecureInput; do
    if [[ -n "${MLS_FOCUS_BASE_REF:-}" && "$name" != "TrackedInputBatch" ]]; then
        git show "$MLS_FOCUS_BASE_REF:Sources/MacLayoutSwitcher/System/$name.swift" > "$focus_work/Sources/$name.swift"
    else
        cp "Sources/MacLayoutSwitcher/System/$name.swift" "$focus_work/Sources/"
    fi
done
if [[ -n "${MLS_FOCUS_BASE_REF:-}" ]]; then
    git show "$MLS_FOCUS_BASE_REF:Sources/MacLayoutSwitcher/Speech/DictationTarget.swift" > "$focus_work/Sources/DictationTarget.swift"
else
    cp Sources/MacLayoutSwitcher/Speech/DictationTarget.swift "$focus_work/Sources/"
fi
cp tools/keyboard-harness/system-focus.swift "$focus_work/main.swift"
python3 - "$focus_work" <<'PY'
from pathlib import Path
import difflib,hashlib,re,sys
root=Path(sys.argv[1]); seams=[]
names=['AXUIElementCopyAttributeValue','AXUIElementSetAttributeValue','AXUIElementIsAttributeSettable',
       'AXUIElementGetPid','AXUIElementSetMessagingTimeout','AXIsProcessTrusted',
       'AXObserverCreate','AXObserverAddNotification']
for path in (root/'Sources').glob('*.swift'):
    original=path.read_text(); compiled=original
    if path.name=='DictationTarget.swift':
        assert 'NSRunningApplication(processIdentifier: pid)' in compiled
        compiled=re.sub(r'NSRunningApplication\(processIdentifier: ([^)]+)\)', r'fixtureRunningApplication(processIdentifier: \1)', compiled)
        assert '$0.postToPid($1)' in compiled
        compiled=compiled.replace('$0.postToPid($1)', 'fixturePostEvent($0, $1)')
        compiled=re.sub(r'\bproc_pidinfo\b', 'fixtureproc_pidinfo', compiled)
        for name in names:
            assert name in compiled, name
            compiled=re.sub(r'\b'+name+r'\b', 'fixture'+name, compiled)
    if path.name=='SecureInput.swift':
        assert compiled.count('        IsSecureEventInputEnabled()')==1
        compiled=compiled.replace('        IsSecureEventInputEnabled()', '        fixtureSecureInput')
    (root/'Compiled'/path.name).write_text(compiled)
    seams.extend(difflib.unified_diff(original.splitlines(True),compiled.splitlines(True),fromfile='Sources/'+path.name,tofile='Compiled/'+path.name))
(root/'seams.patch').write_text(''.join(seams))
paths=sorted((root/'Sources').rglob('*.swift'))+sorted((root/'Compiled').glob('*.swift'))+[root/'main.swift']
(root/'SOURCE-SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+str(p.relative_to(root))+'\n' for p in paths))
PY
printf 'System focus snapshot: %s\n' "$focus_work"
swiftc -module-cache-path "$focus_work/modules" -emit-library -emit-module -module-name SwitcherCore "$focus_work"/Sources/SwitcherCore/*.swift -o "$focus_work/libSwitcherCore.dylib" -emit-module-path "$focus_work/SwitcherCore.swiftmodule"
swiftc -module-cache-path "$focus_work/modules" -I "$focus_work" -L "$focus_work" -lSwitcherCore -Xlinker -rpath -Xlinker "$focus_work" "$focus_work"/Compiled/*.swift "$focus_work/main.swift" -o "$focus_work/test-focus"
focus_status=0
"$focus_work/test-focus" > "$focus_work/run.log" 2>&1 || focus_status=$?
cat "$focus_work/run.log"
exit "$focus_status"
