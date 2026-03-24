import XCTest

final class MainContentViewTests: XCTestCase {
    func testMainContentRequestsInitialFocusForSearchField() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("@FocusState private var focusedField: FocusableField?"),
            "主界面应显式声明搜索框焦点状态，避免把初始焦点交给默认 key-view 顺序"
        )
        XCTAssertTrue(
            source.contains("TextField(\"搜索项目...\", text: $viewModel.searchQuery)\n                    .textFieldStyle(.plain)\n                    .foregroundStyle(NativeTheme.textPrimary)\n                    .focused($focusedField, equals: .search)"),
            "顶部搜索框应绑定显式 focus state，保证它能成为主界面的默认输入入口"
        )
        XCTAssertTrue(
            source.contains(".onAppear {\n            requestInitialSearchFocus()\n        }"),
            "主界面出现时应主动触发一次搜索框焦点请求，而不是继续依赖默认 key-view 顺序"
        )
        XCTAssertTrue(
            source.contains("private func requestInitialSearchFocus() {\n        DispatchQueue.main.async {\n            focusedField = .search\n        }\n    }"),
            "主界面出现后应主动请求把焦点交给搜索框，而不是等待侧边栏按钮抢走默认焦点"
        )
    }

    func testListModeRestoresSingleProjectRecycleBinAction() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)
        let occurrences = source.components(separatedBy: "moveProjectToRecycleBin(project.path)").count - 1

        XCTAssertGreaterThanOrEqual(
            occurrences,
            2,
            "列表模式应重新提供单项目移入回收站入口，而不只是卡片模式可用"
        )
    }

    func testEmptyStateMentionsRecycleBinRecoveryWhenProjectsAreHidden() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("可在回收站恢复隐藏项目"),
            "当没有可见项目且回收站非空时，应提示用户可从回收站恢复"
        )
    }

    func testDirectProjectsViewExposesRemoveDirectProjectAction() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("viewModel.isDirectProjectsDirectorySelected"),
            "移除直连项目动作应仅在“直接添加”虚拟目录视图下显示"
        )
        XCTAssertTrue(
            source.contains("viewModel.removeDirectProject(project.path)"),
            "“直接添加”虚拟目录应支持移除直连项目"
        )
    }

    func testToolbarDoesNotExposeRedundantDetailPanelButtonNextToSettings() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertFalse(
            source.contains("toolbarIcon(\"square.split.2x1\", action: { DetailPanelCloseAction.perform(for: viewModel) })"),
            "主界面工具栏里设置左边的冗余详情面板按钮应已删除，避免继续占用顶部操作位"
        )
    }

    func testToolbarPlacesWorkspaceEntryButtonToTheLeftOfSettings() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains(
                """
                toolbarIcon("waveform.path.ecg", action: { viewModel.revealDashboard() })
                            toolbarIcon("terminal", action: { viewModel.enterOrResumeWorkspace() })
                            toolbarIcon("gearshape", action: { viewModel.revealSettings() })
                """
            ),
            "主界面工具栏应在设置按钮左边提供“进入工作区”快捷按钮"
        )
    }

    func testGitProjectsWithoutCommitCacheShowGitProjectLabel() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("Text(\"Git 项目\")"),
            "主列表/卡片在 `isGitRepository == true` 但尚未刷新统计时，应显示“Git 项目”，而不是误标成“非 Git”"
        )
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/MainContentView.swift")
    }
}
