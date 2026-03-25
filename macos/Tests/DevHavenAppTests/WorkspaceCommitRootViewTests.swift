import XCTest

final class WorkspaceCommitRootViewTests: XCTestCase {
    func testWorkspaceCommitRootViewComposesChangesBrowserDiffPreviewAndCommitPanel() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceCommitChangesBrowserView("), "Commit 根容器应包含 changes browser 子视图")
        XCTAssertTrue(source.contains("WorkspaceCommitDiffPreviewView("), "Commit 根容器应包含 diff preview 子视图")
        XCTAssertTrue(source.contains("WorkspaceCommitPanelView("), "Commit 根容器应包含 commit panel 子视图")
    }

    func testWorkspaceCommitRootViewRefreshesSnapshotOnAppear() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("onAppear"), "Commit 根容器应在进入时触发初始化动作")
        XCTAssertTrue(source.contains("refreshChangesSnapshot()"), "Commit 根容器应在进入时刷新 changes snapshot")
    }

    func testWorkspaceCommitChangesBrowserBindsInclusionToggleAndChangeSelection() throws {
        let source = try String(contentsOf: changesBrowserSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("viewModel.toggleInclusion(for: change.path)"), "changes browser 应把 inclusion toggle 绑定到 ViewModel，而不是只显示静态图标")
        XCTAssertTrue(source.contains("viewModel.selectChange(change.path)"), "changes browser 点击变更后应驱动选中与 diff preview 联动")
    }

    func testWorkspaceCommitDiffPreviewDefinesStableEmptyErrorAndContentStates() throws {
        let source = try String(contentsOf: diffPreviewSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("viewModel.diffPreview.errorMessage"), "diff preview 应显式处理错误态")
        XCTAssertTrue(source.contains("选择变更以查看 Diff"), "diff preview 应保留空态文案")
        XCTAssertTrue(source.contains("viewModel.diffPreview.content"), "diff preview 在正常态应展示 diff 文本内容")
    }

    func testWorkspaceCommitPanelProvidesMessageOptionsActionsAndExecutionStateFeedback() throws {
        let source = try String(contentsOf: panelSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("TextEditor(text: messageBinding)"), "Commit Panel 应提供可编辑的 message editor")
        XCTAssertTrue(source.contains("viewModel.updateCommitMessage"), "Commit Panel 的 message editor 应通过 ViewModel 更新入口驱动状态，避免跳过执行反馈重置逻辑")
        XCTAssertTrue(source.contains("viewModel.commitStatusLegend"), "Commit Panel 顶部应展示基础 status/legend（至少包含 included 数量与分支/执行态摘要）")
        XCTAssertTrue(source.contains("Toggle(\"Amend\""), "Commit Panel 应提供 amend option 开关")
        XCTAssertTrue(source.contains("Toggle(\"Sign-off\""), "Commit Panel 应提供 sign-off option 开关")
        XCTAssertTrue(source.contains("viewModel.updateOptionAuthor"), "Commit Panel 的 author 输入应通过 ViewModel 更新，避免直接改写可选值导致状态漂移")
        XCTAssertTrue(source.contains("viewModel.executeCommit(action: .commit)"), "Commit Panel 至少应提供 Commit 主动作入口")
        XCTAssertTrue(source.contains("viewModel.executeCommit(action: .commitAndPush)"), "Commit Panel 应保留 commitAndPush 入口，便于快速验证执行反馈链路")
        XCTAssertTrue(source.contains("case .idle"), "Commit Panel 应显式处理 idle execution state")
        XCTAssertTrue(source.contains("case .running"), "Commit Panel 应显式处理 running execution state")
        XCTAssertTrue(source.contains("case .succeeded"), "Commit Panel 应显式处理 succeeded execution state")
        XCTAssertTrue(source.contains("case .failed"), "Commit Panel 应显式处理 failed execution state")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceCommitRootView.swift")
    }

    private func changesBrowserSourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceCommitChangesBrowserView.swift")
    }

    private func diffPreviewSourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceCommitDiffPreviewView.swift")
    }

    private func panelSourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceCommitPanelView.swift")
    }
}
