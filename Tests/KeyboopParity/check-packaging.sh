#!/bin/sh
# Supplemental native check: relocate the REAL SwiftPM bundle into an app layout,
# then remove it and require fail-closed readiness without a Bundle.module crash.
set -eu
bundle=${1:?Usage: check-packaging.sh /path/to/MacLayoutSwitcher_SwitcherCore.bundle}
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../.." && pwd)
scratch=$(mktemp -d /tmp/t36-packaging.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
app="$scratch/Relocated.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp -R "$bundle" "$app/Contents/Resources/MacLayoutSwitcher_SwitcherCore.bundle"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>check</string><key>CFBundleIdentifier</key><string>space.alimp.t36.fixture</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
cat > "$scratch/main.swift" <<'SWIFT'
import Foundation
let detector = Detector()
if CommandLine.arguments.contains("--missing") {
    precondition(!detector.isReady)
    precondition(detector.verdict(for: "ghbdtn") == .unsure)
    precondition(detector.liveVerdict(for: "ghbdtn") == .unsure)
    print("missing packaged resources: fail-closed PASS")
} else {
    precondition(detector.isReady)
    precondition(detector.verdict(for: "ghbdtn") == .ru)
    precondition(detector.convertedText(for: "ghbdtn.", to: .ru) == "привет.")
    print("relocated app Contents/Resources: PASS")
}
SWIFT
swiftc -module-cache-path /tmp/t36-swift-modules "$root"/Sources/SwitcherCore/*.swift \
  "$scratch/main.swift" -o "$app/Contents/MacOS/check"
"$app/Contents/MacOS/check"
rm -rf "$app/Contents/Resources/MacLayoutSwitcher_SwitcherCore.bundle"
"$app/Contents/MacOS/check" --missing
