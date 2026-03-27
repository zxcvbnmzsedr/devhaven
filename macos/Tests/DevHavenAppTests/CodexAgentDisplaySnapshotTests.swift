import XCTest
@testable import DevHavenApp

@MainActor
final class CodexAgentDisplaySnapshotTests: XCTestCase {
    func testCaptureKeepsLastActivityAtWhenRecentTextWindowUnchanged() {
        let initialTime = Date(timeIntervalSinceReferenceDate: 100)
        let refreshTime = Date(timeIntervalSinceReferenceDate: 150)

        let firstSnapshot = CodexAgentDisplaySnapshot.capture(
            from: "Codex output",
            now: initialTime
        )
        let secondSnapshot = CodexAgentDisplaySnapshot.capture(
            from: "Codex output",
            previous: firstSnapshot,
            now: refreshTime
        )

        XCTAssertEqual(secondSnapshot?.recentTextWindow, "Codex output")
        XCTAssertEqual(secondSnapshot?.lastActivityAt, initialTime)
    }

    func testCaptureAdvancesLastActivityAtWhenRecentTextWindowChanges() {
        let initialTime = Date(timeIntervalSinceReferenceDate: 100)
        let refreshTime = Date(timeIntervalSinceReferenceDate: 150)

        let firstSnapshot = CodexAgentDisplaySnapshot.capture(
            from: "Codex output",
            now: initialTime
        )
        let secondSnapshot = CodexAgentDisplaySnapshot.capture(
            from: "Codex output updated",
            previous: firstSnapshot,
            now: refreshTime
        )

        XCTAssertEqual(secondSnapshot?.recentTextWindow, "Codex output updated")
        XCTAssertEqual(secondSnapshot?.lastActivityAt, refreshTime)
    }
}
