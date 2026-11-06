#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
identity_work=$(mktemp -d /tmp/mls-next-identity.XXXXXX)
export CLANG_MODULE_CACHE_PATH="$identity_work/module-cache"
export SWIFT_MODULECACHE_PATH="$identity_work/module-cache"
printf 'Next identity scratch: %s\n' "$identity_work"
# Config only needs the hotkey/dictation value types. No SwiftPM build/cache or detector resources
# are needed for these native identity and real advisory-lock boundary checks.
swiftc -emit-library -emit-module -module-name SwitcherCore Sources/SwitcherCore/Hotkey.swift Sources/SwitcherCore/DictationSession.swift \
  -o "$identity_work/libSwitcherCore.dylib" -emit-module-path "$identity_work/SwitcherCore.swiftmodule"
swiftc -I "$identity_work" -L "$identity_work" -lSwitcherCore -Xlinker -rpath -Xlinker "$identity_work" \
  Sources/MacLayoutSwitcher/Config.swift Sources/MacLayoutSwitcher/System/SpeechModelStore.swift \
  Sources/MacLayoutSwitcher/System/CaptureSessionGuard.swift tools/identity-harness/main.swift \
  -o "$identity_work/test-identity"
"$identity_work/test-identity" "$identity_work/owned"
python3 tools/identity-harness/packaging.py
