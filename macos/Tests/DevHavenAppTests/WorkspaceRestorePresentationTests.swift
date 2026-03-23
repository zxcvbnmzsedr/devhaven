import XCTest

final class WorkspaceRestorePresentationTests: XCTestCase {
    func testGhosttySurfaceHostDoesNotRenderRestoreBannerPresentation() throws {
        let source = try String(contentsOf: ghosttySurfaceHostURL(), encoding: .utf8)

        XCTAssertFalse(source.contains("restoreBannerText"), "GhosttySurfaceHost 不应继续读取 restore banner 状态")
        XCTAssertFalse(source.contains("已恢复工作上下文快照"), "恢复后不应继续展示上下文恢复弹窗")
        XCTAssertFalse(source.contains("原终端进程未恢复"), "恢复提示文案不应再出现在 UI 源码中")
    }

    func testGhosttyRuntimeUsesResolvedWorkingDirectoryInsteadOfProjectRootOnly() throws {
        let source = try String(contentsOf: ghosttyRuntimeURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("workingDirectory: request.workingDirectory"), "恢复后的 fresh shell 应优先使用 pane 快照里的 cwd，而不是固定退回 projectPath")
    }

    private func ghosttySurfaceHostURL() -> URL {
        sourceRootURL().appendingPathComponent("Sources/DevHavenApp/Ghostty/GhosttySurfaceHost.swift")
    }

    private func ghosttyRuntimeURL() -> URL {
        sourceRootURL().appendingPathComponent("Sources/DevHavenApp/Ghostty/GhosttyRuntime.swift")
    }

    private func sourceRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
