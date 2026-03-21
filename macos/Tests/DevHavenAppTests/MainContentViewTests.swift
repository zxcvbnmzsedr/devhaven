import XCTest

final class MainContentViewTests: XCTestCase {
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

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/MainContentView.swift")
    }
}
