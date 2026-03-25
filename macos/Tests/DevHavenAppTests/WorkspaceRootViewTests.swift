import XCTest

final class WorkspaceRootViewTests: XCTestCase {
    func testWorkspaceRootViewOwnsProjectNavigationSplitAndChromeContainer() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("WorkspaceSplitView("),
            "Workspace 根布局应拥有项目导航与右侧工作区 chrome 的 split 容器"
        )
        XCTAssertTrue(
            source.contains("WorkspaceProjectSidebarHostView(viewModel: viewModel)"),
            "项目导航应提升到 Workspace 根布局的外层导航宿主中"
        )
        XCTAssertTrue(
            source.contains("WorkspaceChromeContainerView(viewModel: viewModel)"),
            "Workspace 根布局应把实际工作区内容包进独立的外围 chrome 容器"
        )
        XCTAssertFalse(
            source.contains("workspaceToolWindowStripe"),
            "Tool window stripe 应放在 WorkspaceChromeContainerView 内，而不是提升到 WorkspaceRootView 最外层"
        )
    }

    func testWorkspaceRootViewPersistsProjectNavigationWidth() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("viewModel.workspaceSidebarWidth"),
            "项目外层导航的初始宽度仍应从全局设置读取"
        )
        XCTAssertTrue(
            source.contains("viewModel.updateWorkspaceSidebarWidth"),
            "项目外层导航拖拽结束后应继续写回全局设置"
        )
        XCTAssertTrue(
            source.contains("onRatioChangeEnded"),
            "Workspace 根布局应在拖拽结束时提交项目导航宽度"
        )
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceRootView.swift")
    }
}
