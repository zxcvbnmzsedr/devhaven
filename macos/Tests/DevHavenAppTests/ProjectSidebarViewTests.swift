import XCTest

final class ProjectSidebarViewTests: XCTestCase {
    func testDirectoryMenuButtonDoesNotCompeteForInitialFocus() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains(".menuStyle(.borderlessButton)\n                .focusable(false)\n                .help(\"目录操作\")"),
            "目录操作按钮不应继续参与主界面的默认焦点竞争，否则应用启动时焦点会先落到侧边栏 chrome 按钮上"
        )
    }

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

    func testUserAddedDirectoryRowsExposeRemoveAction() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("if !row.isSystemEntry"),
            "用户添加的目录行应与系统固定分组区分开，才能只对可移除目录显示减号动作"
        )
        XCTAssertTrue(
            source.contains("viewModel.removeProjectDirectory(directoryPath)"),
            "目录侧边栏应为用户添加的工作目录提供移除入口"
        )
        XCTAssertTrue(
            source.contains("Image(systemName: \"minus.circle\")"),
            "目录移除动作应使用减号图标，和现有“移除直接添加项目”语义保持一致"
        )
    }

    func testSuccessfulImportSelectsImportedFilterToAvoidNoReaction() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("viewModel.selectDirectory(.directory(firstPath))"),
            "成功添加工作目录后应切换到新目录筛选，避免用户感觉“选完目录没有任何反应”"
        )
        XCTAssertTrue(
            source.contains("viewModel.selectDirectory(.directProjects)"),
            "成功直接添加项目后应切换到“直接添加”筛选，避免新增项目被当前筛选条件隐藏"
        )
    }

    func testImportFlowRecordsDiagnosticsAtImporterBoundary() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("ProjectImportDiagnostics.shared.recordImporterCallback"),
            "fileImporter 成功回调时应打日志，确认系统文件选择器是否真的回来了 URL"
        )
        XCTAssertTrue(
            source.contains("ProjectImportDiagnostics.shared.recordSecurityScope"),
            "导入链路应记录 security-scoped access 获得情况，排查“选到了目录但后续读不到”"
        )
        XCTAssertTrue(
            source.contains("ProjectImportDiagnostics.shared.recordImportAttempt"),
            "真正执行导入前应记录 action 和 paths，方便排查路径是否被正确传递"
        )
        XCTAssertTrue(
            source.contains("ProjectImportDiagnostics.shared.recordFailure"),
            "导入失败时应显式打日志，而不是只改 errorMessage"
        )
    }

    func testFileImporterPresentationStateDoesNotClearPendingActionBeforeCompletion() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("@State private var isDirectoryImporterPresented = false"),
            "目录导入弹窗应使用独立的 presented 状态，避免把动作类型和是否展示耦合在同一个状态变量上"
        )
        XCTAssertTrue(
            source.contains("isPresented: $isDirectoryImporterPresented"),
            "fileImporter 应绑定独立的展示状态，而不是通过 pending action 的 setter 提前清空动作"
        )
        XCTAssertTrue(
            source.contains("pendingDirectoryImportAction = .addDirectory\n                        isDirectoryImporterPresented = true"),
            "点击“添加工作目录”时应先记录动作，再展示 importer"
        )
        XCTAssertTrue(
            source.contains("pendingDirectoryImportAction = .addProjects\n                        isDirectoryImporterPresented = true"),
            "点击“直接添加为项目”时应先记录动作，再展示 importer"
        )
        XCTAssertTrue(
            source.contains("let action = pendingDirectoryImportAction\n        pendingDirectoryImportAction = nil\n        isDirectoryImporterPresented = false"),
            "应在 onCompletion 中先捕获动作，再清理状态，避免回调回来时 action 变成 unknown"
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
