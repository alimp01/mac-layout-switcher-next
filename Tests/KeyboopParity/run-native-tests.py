#!/usr/bin/env python3
"""Run the real Swift test methods with a tiny assertion adapter when CLT lacks XCTest.

This is a supplemental native seam runner, NOT a replacement for Linux swift test.
The same production sources and test bodies compile; only XCTest's assertions and
teardown registration are adapted. No production data or expected values are patched.
"""
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
scratch = pathlib.Path(tempfile.mkdtemp(prefix="t36-native-"))
selected = sys.argv[1:] or ["DetectorTests", "WordCoverageTests", "KeyboopDetectorTests", "ShortWordsTests"]
adapter = r'''
import Foundation
var checks = 0
var failures = 0
func check(_ condition: Bool, _ message: String, file: StaticString, line: UInt) {
    checks += 1
    if !condition { failures += 1; print("FAIL \(file):\(line): \(message)") }
}
class XCTestCase {
    var teardown: [() throws -> Void] = []
    func addTeardownBlock(_ block: @escaping () throws -> Void) { teardown.append(block) }
    func finish() throws { for block in teardown { try block() } }
}
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T,
 _ m: String = "", file: StaticString = #filePath, line: UInt = #line) rethrows {
    let x = try a(), y = try b(); check(x == y, "\(m) actual=\(x) expected=\(y)", file:file, line:line)
}
func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T, _ m: String = "", file: StaticString = #filePath, line: UInt = #line) {
    check(a != b, m, file:file, line:line)
}
func XCTAssertTrue(_ a: Bool, _ m: String = "", file: StaticString = #filePath, line: UInt = #line) { check(a,m,file:file,line:line) }
func XCTAssertFalse(_ a: Bool, _ m: String = "", file: StaticString = #filePath, line: UInt = #line) { check(!a,m,file:file,line:line) }
func XCTAssertNil<T>(_ a: T?, _ m: String = "", file: StaticString = #filePath, line: UInt = #line) { check(a == nil,m,file:file,line:line) }
func XCTAssertNotNil<T>(_ a: T?, _ m: String = "", file: StaticString = #filePath, line: UInt = #line) { check(a != nil,m,file:file,line:line) }
func XCTAssertGreaterThanOrEqual<T: Comparable>(_ a: T, _ b: T, _ m: String = "", file: StaticString = #filePath, line: UInt = #line) { check(a >= b,m,file:file,line:line) }
enum Missing: Error { case value }
func XCTUnwrap<T>(_ a: T?, _ m: String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let a else { check(false,m,file:file,line:line); throw Missing.value }; return a
}
extension Bundle { static let module = Bundle(path: "FIXTURE_BUNDLE")! }
'''
fixtures = scratch / "Fixtures.bundle"
shutil.copytree(root / "Tests/SwitcherCoreTests/Fixtures", fixtures)
shutil.copytree(root / "Sources/SwitcherCore/Resources", scratch / "MacLayoutSwitcher_SwitcherCore.bundle")
(scratch / "Assertions.swift").write_text(adapter.replace("FIXTURE_BUNDLE", str(fixtures)))
sources = [str(p) for p in (root / "Sources/SwitcherCore").glob("*.swift")]
calls = ["import Foundation", "var methods = 0"]
for name in selected:
    source = (root / f"Tests/SwitcherCoreTests/{name}.swift").read_text()
    source = source.replace("import XCTest\n", "").replace("@testable import SwitcherCore\n", "").replace("import SwitcherCore\n", "")
    output = scratch / f"Native{name}.swift"
    output.write_text(f'#sourceLocation(file: "{root}/Tests/SwitcherCoreTests/{name}.swift", line: 1)\n' + source)
    sources.append(str(output))
    for method in re.findall(r"func (test\w+)\(\)", source):
        calls.append(f'do {{ let t = {name}(); try t.{method}(); try t.finish(); methods += 1 }} catch {{ failures += 1; print("ERROR {name}.{method}: \\(error)") }}')
calls.extend(['print("NATIVE adapter: \\(methods) methods, \\(checks) assertions, \\(failures) failures")', 'exit(failures == 0 ? 0 : 1)'])
(scratch / "main.swift").write_text("\n".join(calls) + "\n")
command = ["swiftc", "-module-cache-path", "/tmp/t36-swift-modules", *sources,
           str(scratch / "Assertions.swift"), str(scratch / "main.swift"), "-o", str(scratch / "check")]
compiled = subprocess.run(command, capture_output=True, text=True)
if compiled.returncode:
    print(compiled.stderr)
    sys.exit(compiled.returncode)
print(f"Scratch: {scratch}")
sys.exit(subprocess.run([str(scratch / "check")]).returncode)
