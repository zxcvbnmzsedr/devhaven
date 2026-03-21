import XCTest

final class WorkspaceShellViewTests: XCTestCase {
    func testWorkspaceShellUsesResizableSplitViewForSidebar() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("WorkspaceSplitView("),
            "工作区壳层应改用可拖拽的分栏容器，否则左侧项目侧边栏无法调整宽度"
        )
    }

    func testWorkspaceShellDoesNotPinSidebarToFixedWidth() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertFalse(
            source.contains(".frame(width: 280)"),
            "工作区左侧侧边栏不应再被固定到 280pt，否则拖拽分隔线不会生效"
        )
    }

    func testWorkspaceShellReadsInitialSidebarWidthFromViewModelSettings() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("viewModel.workspaceSidebarWidth"),
            "工作区侧边栏初始宽度应从 ViewModel 的全局设置读取，而不是永远只用运行时默认值"
        )
    }

    func testWorkspaceShellPersistsSidebarWidthWhenDragEnds() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("onRatioChangeEnded"),
            "工作区侧边栏应在拖拽结束时提交持久化，而不是只更新本地状态"
        )
        XCTAssertTrue(
            source.contains("viewModel.updateWorkspaceSidebarWidth"),
            "工作区侧边栏拖拽结束后应把宽度写回全局设置"
        )
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceShellView.swift")
    }
}
