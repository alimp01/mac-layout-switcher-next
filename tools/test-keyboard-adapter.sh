#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d /tmp/mls-keyboard-adapter.XXXXXX)
cp -R Sources/SwitcherCore/Resources "$work/MacLayoutSwitcher_SwitcherCore.bundle"
cp tools/keyboard-harness/adapter.swift "$work/main.swift"
swiftc -emit-library -emit-module -module-name SwitcherCore Sources/SwitcherCore/*.swift -o "$work/libSwitcherCore.dylib" -emit-module-path "$work/SwitcherCore.swiftmodule"
swiftc -I "$work" -L "$work" -lSwitcherCore -Xlinker -rpath -Xlinker "$work" Sources/MacLayoutSwitcher/System/InputFocusGuard.swift Sources/MacLayoutSwitcher/System/Typist.swift Sources/MacLayoutSwitcher/System/TrackedInputBatch.swift Sources/MacLayoutSwitcher/System/SelectionConverter.swift Sources/MacLayoutSwitcher/Speech/DictationTarget.swift Sources/MacLayoutSwitcher/System/SecureInput.swift "$work/main.swift" -o "$work/test-adapter"
"$work/test-adapter"
cp tools/keyboard-harness/notice.swift "$work/main.swift"
swiftc Sources/MacLayoutSwitcher/UI/ConversionNotice.swift "$work/main.swift" -o "$work/test-notice"
"$work/test-notice"
cp tools/keyboard-harness/transport.swift "$work/main.swift"
swiftc Sources/MacLayoutSwitcher/Speech/DictationTarget.swift Sources/MacLayoutSwitcher/System/SecureInput.swift "$work/main.swift" -o "$work/test-transport"
"$work/test-transport"
