#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d /tmp/mls-keyboard-webkit.XXXXXX)
mkdir -p "$work/Sources" "$work/Compiled" "$work/SafariFixture.app/Contents"
cp -R Sources/SwitcherCore "$work/Sources/"
for name in InputFocusGuard Typist TrackedInputBatch SelectionConverter; do
    cp "Sources/MacLayoutSwitcher/System/$name.swift" "$work/Sources/"
done
if [[ -n "${MLS_WEBKIT_BASE_REF:-}" ]]; then
    git show "$MLS_WEBKIT_BASE_REF:Sources/MacLayoutSwitcher/Speech/DictationTarget.swift" > "$work/Sources/DictationTarget.swift"
else
    cp Sources/MacLayoutSwitcher/Speech/DictationTarget.swift "$work/Sources/"
fi
cp Sources/MacLayoutSwitcher/System/SecureInput.swift "$work/Sources/"
cp tools/keyboard-harness/webkit.swift "$work/main.swift"
python3 - "$work" <<'PY'
from pathlib import Path
import hashlib,plistlib,sys
root=Path(sys.argv[1])
(root/'SafariFixture.app/Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.apple.Safari','CFBundlePackageType':'APPL'}))
source=root/'Sources/DictationTarget.swift'
s=source.read_text()
old='NSRunningApplication(processIdentifier: pid)?.bundleURL'
assert s.count(old)==1
s=s.replace(old,'fixtureProcessBundleURL(pid: pid)')
(root/'Compiled/DictationTarget.swift').write_text(s)
(root/'seams.txt').write_text('Only process bundle URL lookup replaced with fixtureProcessBundleURL(pid: pid); all target, selection, routing and event construction code unchanged.\n')
paths=sorted((root/'Sources').rglob('*.swift'))+[root/'main.swift',root/'Compiled/DictationTarget.swift',root/'SafariFixture.app/Contents/Info.plist']
(root/'SOURCE-SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+str(p.relative_to(root))+'\n' for p in paths))
PY
printf 'WebKit snapshot: %s\n' "$work"
swiftc -emit-library -emit-module -module-name SwitcherCore "$work"/Sources/SwitcherCore/*.swift -o "$work/libSwitcherCore.dylib" -emit-module-path "$work/SwitcherCore.swiftmodule"
swiftc -suppress-warnings -I "$work" -L "$work" -lSwitcherCore -Xlinker -rpath -Xlinker "$work" "$work/Sources/InputFocusGuard.swift" "$work/Sources/Typist.swift" "$work/Sources/TrackedInputBatch.swift" "$work/Sources/SelectionConverter.swift" "$work/Compiled/DictationTarget.swift" "$work/Sources/SecureInput.swift" "$work/main.swift" -o "$work/test-webkit"
MLS_WEBKIT_TEST_BUNDLE="$work/SafariFixture.app" "$work/test-webkit" 2>&1 | tee "$work/run.log"
