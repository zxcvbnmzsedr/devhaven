import XCTest

final class WorkspaceShellViewTests: XCTestCase {
    func testWorkspaceShellViewRefreshesCodexDisplayStateOnTimer() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("CodexAgentDisplayStateRefresher.refresh"), "WorkspaceShellView 应定期刷新 Codex 展示态")
        XCTAssertTrue(source.contains("Timer.publish"), "WorkspaceShellView 应以定时方式触发 Codex 展示态刷新")
        XCTAssertTrue(source.contains("codexDisplayRefreshState"), "WorkspaceShellView 应保留 Codex 展示态刷新所需的运行时观测状态")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceShellView.swift")
    }
}
