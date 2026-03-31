import XCTest
@testable import DevHavenCore

final class WorkspaceRunModelsTests: XCTestCase {
    func testAppendDisplayChunkKeepsSmallBuffersUntouched() {
        var session = makeSession()

        session.appendDisplayChunk("hello\n")
        session.appendDisplayChunk("world\n")

        XCTAssertEqual(session.displayBuffer, "hello\nworld\n")
    }

    func testAppendDisplayChunkTruncatesToRecentWindowAndKeepsSingleNotice() {
        var session = makeSession()
        let largeChunk = String(repeating: "old-line-0123456789\n", count: 9_000)
        let finalMarker = "final-line-marker\n"

        session.appendDisplayChunk(largeChunk)
        session.appendDisplayChunk(finalMarker)

        XCTAssertTrue(
            session.displayBuffer.hasPrefix(WorkspaceRunSession.displayBufferTruncationNotice)
        )
        XCTAssertTrue(session.displayBuffer.hasSuffix(finalMarker))
        XCTAssertEqual(
            session.displayBuffer.components(separatedBy: WorkspaceRunSession.displayBufferTruncationNotice).count - 1,
            1
        )
        XCTAssertLessThanOrEqual(
            session.displayBuffer.utf8.count,
            WorkspaceRunSession.maxDisplayBufferUTF8Bytes
        )
    }

    private func makeSession() -> WorkspaceRunSession {
        WorkspaceRunSession(
            id: "session",
            configurationID: "config",
            configurationName: "Run",
            configurationSource: .projectRunConfiguration,
            projectPath: "/tmp/project",
            rootProjectPath: "/tmp/project",
            command: "echo test",
            workingDirectory: "/tmp/project",
            state: .running,
            startedAt: Date()
        )
    }
}
