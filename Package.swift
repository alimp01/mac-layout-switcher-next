// swift-tools-version:5.9
import PackageDescription
import Foundation

// Manifest runs on the build host. Intel/Linux must not resolve Apple's binary.
// Explicit cross-compilation from an arm64 Mac: MLS_DISABLE_SPEECH=1 swift build --triple …
#if os(macOS) && arch(arm64)
let speechEnabled = ProcessInfo.processInfo.environment["MLS_DISABLE_SPEECH"] != "1"
#else
let speechEnabled = false
#endif

var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .target(name: "SwitcherCore", resources: [.process("Resources")]),
    .executableTarget(name: "MacLayoutSwitcher", dependencies: ["SwitcherCore"]),
    .testTarget(name: "SwitcherCoreTests", dependencies: ["SwitcherCore"],
                resources: [.process("Fixtures")])
]
if speechEnabled {
    dependencies.append(.package(url: "https://github.com/ekhodzitsky/gigastt-swift", exact: "2.17.0"))
    targets.append(.executableTarget(
        name: "SpeechRecognizer",
        dependencies: [.product(name: "GigaSTT", package: "gigastt-swift")],
        // Some objects in the pinned XCFramework require 13.4. Keep the main
        // app at 13.0; it never links this library and gates helper launch.
        swiftSettings: [.unsafeFlags(["-target", "arm64-apple-macosx13.4"])],
        linkerSettings: [.unsafeFlags(["-target", "arm64-apple-macosx13.4"])]
    ))
}
let package = Package(name: "MacLayoutSwitcher", platforms: [.macOS(.v13)],
                      dependencies: dependencies, targets: targets)
