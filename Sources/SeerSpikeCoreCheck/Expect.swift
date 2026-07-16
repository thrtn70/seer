import Foundation

/// Minimal assertion harness for the Phase 0 spike. This machine has Command Line
/// Tools only, so XCTest/swift-testing are unavailable; we run checks via `swift run`.
final class Check {
    private var total = 0
    private var failures = 0

    func expect(_ condition: Bool, _ message: @autoclosure () -> String,
                file: StaticString = #file, line: UInt = #line) {
        total += 1
        if !condition {
            failures += 1
            FileHandle.standardError.write(Data("FAIL [\(file):\(line)] \(message())\n".utf8))
        }
    }

    func equal<T: Equatable>(_ actual: T, _ expected: T, _ label: String,
                             file: StaticString = #file, line: UInt = #line) {
        expect(actual == expected, "\(label): expected \(expected), got \(actual)", file: file, line: line)
    }

    var exitCode: Int32 { failures == 0 ? 0 : 1 }
    func summary(_ suite: String) { print("[\(suite)] \(total - failures)/\(total) checks passed") }
}
