import XCTest

final class ProjectSidebarViewTests: XCTestCase {
    func testDirectorySectionUsesArchiveSidebarPlusMenuActions() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("Menu {"),
            "目录分区右侧加号应和 2.8.3 一样弹出菜单，而不是直接触发单一动作"
        )
        XCTAssertTrue(
            source.contains("添加工作目录（扫描项目）"),
            "目录加号菜单应包含“添加工作目录（扫描项目）”"
        )
        XCTAssertTrue(
            source.contains("直接添加为项目"),
            "目录加号菜单应包含“直接添加为项目”"
        )
        XCTAssertTrue(
            source.contains("刷新项目列表"),
            "目录加号菜单应包含“刷新项目列表”"
        )
    }

    func testSidebarRestoresFixedRecycleBinEntryLikeArchiveSidebar() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("viewModel.revealRecycleBin()"),
            "侧栏应恢复固定回收站入口，而不是只能从菜单栏打开"
        )
        XCTAssertTrue(
            source.contains("\"回收站\""),
            "侧栏应展示“回收站”文案，提升可发现性"
        )
    }

    func testSidebarRowUsesWholeRowContentShapeForHitTesting() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains(".contentShape(.rect(cornerRadius: 8))"),
            "目录行应显式声明整行 contentShape，避免点击热区只落在文字/可见内容上"
        )
    }

    func testCliSessionSectionUsesRealQuickTerminalSessionActions() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("viewModel.activateWorkspaceProject(item.projectPath)"),
            "CLI 会话项点击后应恢复 / 激活真实 quick terminal session"
        )
        XCTAssertTrue(
            source.contains("viewModel.closeWorkspaceProject(item.projectPath)"),
            "CLI 会话项应提供关闭 quick terminal session 的入口"
        )
        XCTAssertTrue(
            source.contains("暂无 CLI 会话，点击 + 开启快速终端"),
            "CLI 会话空状态文案应直接反映真实会话为空"
        )
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/ProjectSidebarView.swift")
    }
}
