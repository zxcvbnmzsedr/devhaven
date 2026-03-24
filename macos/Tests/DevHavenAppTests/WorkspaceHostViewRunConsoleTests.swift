import XCTest

final class WorkspaceHostViewRunConsoleTests: XCTestCase {
    func testWorkspaceHostAddsRunToolbarAndBottomConsolePanel() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceRunToolbarView("), "WorkspaceHostView 顶部右侧应接入运行工具栏")
        XCTAssertTrue(source.contains("WorkspaceRunConsolePanel("), "WorkspaceHostView 底部应挂载 Run Console 面板")
        XCTAssertTrue(source.contains("viewModel.runSelectedWorkspaceConfiguration"), "WorkspaceHostView 应把 Run 动作桥接到运行配置级 ViewModel API")
        XCTAssertTrue(source.contains("viewModel.stopSelectedWorkspaceRunSession"), "WorkspaceHostView 应把 Stop 动作桥接到 ViewModel")
        XCTAssertTrue(source.contains("viewModel.toggleWorkspaceRunConsole"), "WorkspaceHostView 应把 Logs 展开/收起桥接到 ViewModel")
        XCTAssertTrue(source.contains("WorkspaceScriptConfigurationSheet("), "WorkspaceHostView 的配置入口应打开项目脚本配置面板")
        XCTAssertFalse(source.contains("viewModel.revealSettings(section: .scripts)"), "WorkspaceHostView 不应再把配置按钮直接指向通用脚本设置页")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceHostView.swift")
    }
}
