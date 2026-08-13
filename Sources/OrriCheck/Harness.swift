import Foundation

/// Minimal check harness.
///
/// This project deliberately avoids XCTest and swift-testing: both resolve only
/// with full Xcode installed, and Command Line Tools alone — which is what this
/// machine has — cannot see either module. An executable target keeps checks
/// runnable via `swift run orri-check` while still linking `OrriKit` and its SPM
/// dependencies, which porcelain's concatenate-and-`swift file` trick cannot do.
enum Check {
    static var passed = 0
    static var failures: [String] = []

    static func expect(
        _ condition: Bool, _ label: String, file: String = #fileID, line: UInt = #line
    ) {
        if condition {
            passed += 1
        } else {
            failures.append("\(file):\(line) — \(label)")
        }
    }

    static func equal<T: Equatable>(
        _ actual: T, _ expected: T, _ label: String, file: String = #fileID, line: UInt = #line
    ) {
        if actual == expected {
            passed += 1
        } else {
            failures.append(
                """
                \(file):\(line) — \(label)
                        expected: \(expected)
                        actual:   \(actual)
                """)
        }
    }

    /// Records a failure and returns `nil` so the caller can bail out early.
    static func unwrap<T>(
        _ value: T?, _ label: String, file: String = #fileID, line: UInt = #line
    ) -> T? {
        guard let value else {
            failures.append("\(file):\(line) — \(label) was nil")
            return nil
        }
        passed += 1
        return value
    }

    static func report() -> Never {
        if failures.isEmpty {
            print("orri-check: \(passed) checks passed")
            exit(0)
        }
        print("orri-check: \(failures.count) FAILED, \(passed) passed\n")
        for failure in failures {
            print("  ✘ \(failure)")
        }
        exit(1)
    }
}
