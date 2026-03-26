import XCTest

final class WorkspaceCommitSideToolWindowHostViewTests: XCTestCase {
    func testWorkspaceCommitSideHostRoutesCommitRootViewAndEmptyStates() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceCommitRootView("), "Commit 侧边工具窗宿主应挂载既有 Commit 根容器")
        XCTAssertTrue(source.contains("activeWorkspaceCommitViewModel"), "Commit 侧边工具窗宿主应消费 NativeAppViewModel 的 commit view model 真相源")
        XCTAssertTrue(source.contains("快速终端暂不支持 Commit 模式"), "Commit 侧边工具窗宿主应保留快速终端空状态")
        XCTAssertTrue(source.contains("当前项目不是 Git 仓库"), "Commit 侧边工具窗宿主应保留非 Git 项目空状态")
    }

    func testWorkspaceCommitSideHostSetsFocusedAreaToSideCommit() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("setWorkspaceFocusedArea(.sideToolWindow(.commit))"), "点击 Commit 侧边工具窗内容时应显式把 focused area 切到侧边 Commit")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceCommitSideToolWindowHostView.swift")
    }
}
