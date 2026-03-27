import XCTest

final class WorkspaceCommitRootViewTests: XCTestCase {
    func testWorkspaceCommitRootViewComposesChangesBrowserAndCommitPanelWithoutDiffPreview() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("WorkspaceCommitChangesBrowserView("), "Commit 根容器应包含 changes browser 子视图")
        XCTAssertTrue(source.contains("WorkspaceCommitPanelView("), "Commit 根容器应包含 commit panel 子视图")
        XCTAssertFalse(source.contains("WorkspaceCommitDiffPreviewView("), "按当前产品决策，Commit 根容器应先移除 Diff Preview 分区")
    }

    func testWorkspaceCommitRootViewRefreshesSnapshotOnAppear() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("onAppear"), "Commit 根容器应在进入时触发初始化动作")
        XCTAssertTrue(source.contains("refreshChangesSnapshot()"), "Commit 根容器应在进入时刷新 changes snapshot")
    }

    func testWorkspaceCommitRootViewAutoRefreshesSnapshotWhileVisible() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("Timer.publish("), "Commit 根容器应提供自动刷新 timer，避免只能依赖手动刷新按钮")
        XCTAssertTrue(source.contains(".onReceive("), "Commit 根容器应在可见期间消费自动刷新 timer")
        XCTAssertTrue(source.contains("viewModel.refreshChangesSnapshot()"), "自动刷新 timer 到期后应主动刷新 changes snapshot")
    }

    func testWorkspaceCommitChangesBrowserUsesIdeaLikeToolbarGroupHeaderAndFileRows() throws {
        let source = try String(contentsOf: changesBrowserSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("toolbar"), "changes browser 应提供顶部 icon toolbar，以对齐 IDEA 的操作入口密度")
        XCTAssertTrue(source.contains("groupHeader"), "changes browser 应包含类似 IDEA 的 Changes 分组头，而不是直接平铺卡片")
        XCTAssertTrue(source.contains("Text(\"\\(title) \\(changes.count) files\")"), "changes browser 分组头应支持按分组标题展示文件总数，形成与 IDEA 接近的结构心智")
        XCTAssertTrue(source.contains("viewModel.toggleAllInclusion()"), "changes browser 分组头应提供总 inclusion 开关，便于快速全选/清空")
        XCTAssertTrue(source.contains("viewModel.toggleInclusion(for: change.path)"), "changes browser 应把 inclusion toggle 绑定到 ViewModel，而不是只显示静态图标")
        XCTAssertTrue(source.contains("viewModel.selectChange(change.path)"), "changes browser 点击变更后应驱动选中与 diff preview 联动")
        XCTAssertTrue(source.contains("fileNameText(for: change)"), "changes browser 行主标题应拆出文件名层级，而不是直接整行展示完整路径")
        XCTAssertTrue(source.contains("directoryText(for: change)"), "changes browser 行次标题应拆出目录路径层级，以对齐 IDEA 的文件名 / 路径信息结构")
        XCTAssertTrue(source.contains("fileNameColor(for: change)"), "changes browser 在移除问号图标后，仍应保留基于文件状态的视觉语义")
        XCTAssertFalse(source.contains(".clipShape(.rect(cornerRadius: 8))"), "对齐 IDEA 时，changes browser 不应继续沿用卡片圆角列表样式")
        XCTAssertFalse(source.contains("change.group.rawValue.uppercased()"), "对齐 IDEA 时，changes browser 不应继续把 group 文案作为主次信息直接暴露")
    }

    func testWorkspaceCommitChangesBrowserSeparatesUnversionedFilesSection() throws {
        let source = try String(contentsOf: changesBrowserSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("unversionedChanges"), "changes browser 应显式拆出 unversioned 集合，而不是把所有文件直接混在一个 Changes 分组里")
        XCTAssertTrue(source.contains("\"Unversioned Files\""), "对齐 IDEA 时，untracked 文件应单独展示为 Unversioned Files 分组")
        XCTAssertTrue(source.contains("title: \"Unversioned Files\""), "unversioned files 应通过独立分组头渲染，而不是复用普通 Changes 标题")
    }

    func testWorkspaceCommitChangesBrowserUsesSingleLineInlineTitleLayoutLikeIdeaRenderer() throws {
        let source = try String(contentsOf: changesBrowserSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("inlineTitleRow(change)"), "Commit browser 行标题应抽成单行 inline renderer，而不是继续在 row 内堆两行文本")
        XCTAssertTrue(source.contains("HStack(alignment: .firstTextBaseline, spacing: 0)"), "文件名与父路径应按同一基线对齐，接近 IDEA renderer 的 append 模式")
        XCTAssertTrue(source.contains("Text(\" \\(directoryText)\")"), "父路径应以内联灰字追加到文件名后方，而不是另起一行")
        XCTAssertFalse(source.contains("VStack(alignment: .leading, spacing: 2)"), "对齐 IDEA renderer 时，Commit browser 行不应继续使用两行 VStack 标题结构")
    }

    func testWorkspaceCommitChangesBrowserUsesRealFileIconsInsteadOfQuestionBadge() throws {
        let source = try String(contentsOf: changesBrowserSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("Image(nsImage: fileIcon(for: change))"), "Commit browser 应显示真实文件图标，而不是把状态问号当作图标列")
        XCTAssertTrue(source.contains("NSWorkspace.shared.icon(forFile:"), "Commit browser 应通过 macOS 文件图标能力按文件类型渲染图标")
        XCTAssertTrue(source.contains("fileNameColor(for: change)"), "移除问号 badge 后，状态语义应至少保留在文件名字色上")
        XCTAssertFalse(source.contains("Text(statusBadgeText(for: change))"), "对齐 IDEA 时，文件图标列不应继续由状态 badge 文本充当")
    }

    func testWorkspaceCommitChangesBrowserUsesGroupBasedColorSemantics() throws {
        let source = try String(contentsOf: changesBrowserSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("switch change.group"), "用户要求按分组而不是按状态着色时，fileNameColor 应切换为 group 语义")
        XCTAssertTrue(source.contains("case .untracked:"), "Unversioned Files 应有单独的颜色分支")
        XCTAssertTrue(source.contains("return NativeTheme.danger"), "Unversioned Files 应渲染为红色")
        XCTAssertTrue(source.contains("default:"), "其余 versioned changes 应统一收口到默认分支")
        XCTAssertTrue(source.contains("return NativeTheme.accent"), "Changes 应渲染为蓝色")
    }

    func testWorkspaceCommitDiffPreviewDefinesStableEmptyErrorAndContentStates() throws {
        let source = try String(contentsOf: diffPreviewSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("viewModel.diffPreview.errorMessage"), "diff preview 应显式处理错误态")
        XCTAssertTrue(source.contains("选择变更以查看 Diff"), "diff preview 应保留空态文案")
        XCTAssertTrue(source.contains("viewModel.diffPreview.content"), "diff preview 在正常态应展示 diff 文本内容")
    }

    func testWorkspaceCommitPanelUsesIdeaLikeMessageAndActionStructure() throws {
        let source = try String(contentsOf: panelSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("Text(\"Commit\")"), "Commit Panel 顶部应保留 Commit 标题，以对齐 IDEA 的主区语义")
        XCTAssertTrue(source.contains("Toggle(\"Amend\""), "Commit Panel 应在主面板顶部提供 Amend 开关")
        XCTAssertTrue(source.contains("TextEditor(text: messageBinding)"), "Commit Panel 应提供可编辑的 message editor")
        XCTAssertTrue(source.contains("\"Commit Message\""), "Commit Panel 的 message editor 应提供类似 IDEA 的 Commit Message 占位文案")
        XCTAssertTrue(source.contains("viewModel.updateCommitMessage"), "Commit Panel 的 message editor 应通过 ViewModel 更新入口驱动状态，避免跳过执行反馈重置逻辑")
        XCTAssertTrue(source.contains("viewModel.executeCommit(action: .commit)"), "Commit Panel 至少应提供 Commit 主动作入口")
        XCTAssertTrue(source.contains("\"Commit and Push...\""), "Commit Panel 应保留类似 IDEA 的 Commit and Push 次级动作")
        XCTAssertTrue(source.contains("Image(systemName: \"gearshape\")"), "Commit Panel 应提供齿轮入口承接更多提交选项")
        XCTAssertTrue(source.contains(".popover("), "Commit Panel 的更多选项应通过弹出层承接，而不是继续平铺在主面板里")
        XCTAssertFalse(source.contains("viewModel.commitStatusLegend"), "对齐 IDEA 时，主面板不应继续直接暴露 status legend 文案")
        XCTAssertFalse(source.contains("Text(\"Commit Options\")"), "对齐 IDEA 时，主面板不应继续保留显式 Commit Options 分区标题")
        XCTAssertTrue(source.contains("case .running"), "Commit Panel 应显式处理 running execution state")
        XCTAssertTrue(source.contains("case .succeeded"), "Commit Panel 应显式处理 succeeded execution state")
        XCTAssertTrue(source.contains("case .failed"), "Commit Panel 应显式处理 failed execution state")
    }

    func testWorkspaceCommitChangesBrowserDoubleClickUsesUnifiedDiffActionsWhileHostKeepsSinglePreviewIdentity() throws {
        let hostSource = try String(contentsOf: commitHostSourceFileURL(), encoding: .utf8)
        let rootSource = try String(contentsOf: sourceFileURL(), encoding: .utf8)
        let changesSource = try String(contentsOf: changesBrowserSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(hostSource.contains("syncActiveWorkspaceCommitDiffPreviewIfNeeded("), "Commit 宿主应继续复用单实例 preview 的同步入口，避免单击每次都新建 diff tab")
        XCTAssertTrue(hostSource.contains("openActiveWorkspaceCommitDiffPreview("), "Commit 宿主应继续通过单实例 preview 入口打开或聚焦 diff")
        XCTAssertTrue(hostSource.contains("allChanges: commitViewModel.changesSnapshot?.changes"), "Commit 宿主应把当前 snapshot 传给 diff 打开链路，以构造 request chain")
        XCTAssertTrue(rootSource.contains("onSyncDiffIfNeeded:"), "WorkspaceCommitRootView 应把统一 diff 同步闭包向 changes browser 传递")
        XCTAssertTrue(rootSource.contains("onOpenDiff:"), "WorkspaceCommitRootView 应把统一 open diff 闭包向 changes browser 传递")
        XCTAssertTrue(changesSource.contains(".onTapGesture(count: 2)"), "Commit changes browser 文件行应支持双击打开独立 diff 标签页")
        XCTAssertTrue(changesSource.contains("onSyncDiffIfNeeded(change)"), "Commit changes browser 单击后应调用统一 diff 同步闭包，而不是继续暴露 preview 命名")
        XCTAssertTrue(changesSource.contains("onOpenDiff(change)"), "Commit changes browser 双击后应调用统一 open diff 闭包，而不是继续停留在 preview 命名心智里")
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

    private func commitHostSourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceCommitSideToolWindowHostView.swift")
    }
}
