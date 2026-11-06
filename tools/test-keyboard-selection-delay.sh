#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d /tmp/mls-keyboard-selection-delay.XXXXXX)
mkdir -p "$work/Sources"
cp -R Sources/SwitcherCore "$work/Sources/"
for name in InputFocusGuard Typist TrackedInputBatch SelectionConverter; do
    if [[ -n "${MLS_SELECTION_BASE_REF:-}" && "$name" != "TrackedInputBatch" ]]; then
        git show "$MLS_SELECTION_BASE_REF:Sources/MacLayoutSwitcher/System/$name.swift" > "$work/Sources/$name.swift"
    else
        cp "Sources/MacLayoutSwitcher/System/$name.swift" "$work/Sources/"
    fi
done
cp Sources/MacLayoutSwitcher/Speech/DictationTarget.swift Sources/MacLayoutSwitcher/System/SecureInput.swift "$work/Sources/"
cp tools/keyboard-harness/selection-delay.swift "$work/main.swift"
python3 - "$work" <<'PY'
from pathlib import Path
import hashlib,sys
root=Path(sys.argv[1])
paths=sorted((root/'Sources').rglob('*.swift'))+[root/'main.swift']
(root/'SOURCE-SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+str(p.relative_to(root))+'\n' for p in paths))
PY
printf 'Selection-delay snapshot: %s\n' "$work"
swiftc -emit-library -emit-module -module-name SwitcherCore "$work"/Sources/SwitcherCore/*.swift -o "$work/libSwitcherCore.dylib" -emit-module-path "$work/SwitcherCore.swiftmodule"
swiftc -I "$work" -L "$work" -lSwitcherCore -Xlinker -rpath -Xlinker "$work" "$work/Sources/InputFocusGuard.swift" "$work/Sources/Typist.swift" "$work/Sources/TrackedInputBatch.swift" "$work/Sources/SelectionConverter.swift" "$work/Sources/DictationTarget.swift" "$work/Sources/SecureInput.swift" "$work/main.swift" -o "$work/test-delay"
"$work/test-delay" 2>&1 | tee "$work/run.log"
