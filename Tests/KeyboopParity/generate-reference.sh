#!/bin/sh
# Re-run against an independently cloned upstream. Never compiles the port.
set -eu
upstream=${1:?Usage: generate-reference.sh /path/to/keyboop [output.json]}
pin=fb9bdde4eb8f13a486974cf102a8bec9d607e5d2
test "$(git -C "$upstream" rev-parse HEAD)" = "$pin"
git -C "$upstream" diff --exit-code "$pin" -- Sources/Keyboop/LayoutDetector.swift Sources/Keyboop/LayoutData.swift Sources/Keyboop/ExtraWords.swift Sources/Keyboop/Keymap.swift Sources/Keyboop/Resources
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
scratch=$(mktemp -d /tmp/keyboop-parity.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
swiftc -module-cache-path "$scratch/modules" \
  "$upstream/Sources/Keyboop/LayoutDetector.swift" \
  "$upstream/Sources/Keyboop/LayoutData.swift" \
  "$upstream/Sources/Keyboop/ExtraWords.swift" \
  "$upstream/Sources/Keyboop/Keymap.swift" \
  "$here/reference.swift" -o "$scratch/reference"
KEYBOOP_DATA_DIR="$upstream/Sources/Keyboop/Resources" \
  "$scratch/reference" "$here/inputs.json" "${2:-$here/../SwitcherCoreTests/Fixtures/keyboop-reference.json}"
