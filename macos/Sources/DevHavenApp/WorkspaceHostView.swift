import SwiftUI
import GhosttyKit
import DevHavenCore

struct WorkspaceHostView: View {
    @Bindable var viewModel: NativeAppViewModel
    let project: Project
    let workspace: GhosttyWorkspaceController
    let terminalSessionStore: WorkspaceTerminalSessionStore
    @StateObject private var browserSessionStore = WorkspaceBrowserSessionStore()
    @State private var windowActivity: WindowActivityState = .inactive
    @State private var isRunConfigurationSheetPresented = false
    @State private var runConsoleResizeStartHeight: CGFloat?

    var body: some View {
        let chromePolicy = WorkspaceChromePolicy.workspaceMinimal
        let presentedTabSnapshot = viewModel.workspacePresentedTabSnapshot(for: project.path)
        let presentedTabs = presentedTabSnapshot.items
        let selectedPresentedTab = presentedTabSnapshot.selection
        let runToolbarState = viewModel.workspaceRunToolbarState(for: project.path)

        VStack(alignment: .leading, spacing: chromePolicy.showsWorkspaceHeader ? 16 : 0) {
            if chromePolicy.showsWorkspaceHeader {
                header
            }

            HStack(alignment: .center, spacing: 12) {
                WorkspaceTabBarView(
                    tabs: presentedTabs,
                    canSplit: canSplit(for: selectedPresentedTab),
                    onSelectTab: { selection in
                        viewModel.selectWorkspacePresentedTab(selection, in: project.path)
                    },
                    onCloseTab: { selection in
                        closePresentedTab(selection)
                    },
                    onPromoteEditorPreview: { tabID in
                        viewModel.promoteWorkspaceEditorTabToRegular(tabID, in: project.path)
                    },
                    onSetEditorPinned: { tabID, isPinned in
                        viewModel.setWorkspaceEditorTabPinned(isPinned, tabID: tabID, in: project.path)
                    },
                    onCloseOtherEditorTabs: { tabID in
                        viewModel.closeOtherWorkspaceEditorTabs(keeping: tabID, in: project.path)
                    },
                    onCloseEditorTabsToRight: { tabID in
                        viewModel.closeWorkspaceEditorTabsToRight(of: tabID, in: project.path)
                    },
                    onCreateTab: {
                        _ = viewModel.createWorkspaceTerminalTab(in: project.path)
                    },
                    onSplitHorizontally: {
                        if case .editor = selectedPresentedTab {
                            viewModel.splitWorkspaceEditorActiveGroup(axis: .vertical, in: project.path)
                        } else {
                            _ = workspace.splitFocusedPane(direction: .down)
                        }
                    },
                    onSplitVertically: {
                        if case .editor = selectedPresentedTab {
                            viewModel.splitWorkspaceEditorActiveGroup(axis: .horizontal, in: project.path)
                        } else {
                            _ = workspace.splitFocusedPane(direction: .right)
                        }
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                WorkspaceRunToolbarView(
                    configurations: runToolbarState.configurations,
                    selectedConfigurationID: runToolbarState.selectedConfigurationID,
                    canRun: runToolbarState.canRun,
                    canStop: runToolbarState.canStop,
                    hasSessions: runToolbarState.hasSessions,
                    isLogsVisible: runToolbarState.isLogsVisible,
                    onSelectConfiguration: { viewModel.selectWorkspaceRunConfiguration($0, in: project.path) },
                    onRun: {
                        do {
                            try viewModel.runSelectedWorkspaceConfiguration(in: project.path)
                        } catch {
                            // 错误已由 ViewModel 收口
                        }
                    },
                    onStop: { viewModel.stopSelectedWorkspaceRunSession(in: project.path) },
                    onToggleLogs: { viewModel.toggleWorkspaceRunConsole(in: project.path) },
                    onConfigure: { isRunConfigurationSheetPresented = true }
                )
            }

            workspacePresentedContent(selectedPresentedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let runConsoleState = viewModel.workspaceRunConsoleState(for: project.path),
               runConsoleState.isVisible,
               !runConsoleState.sessions.isEmpty {
                runConsoleSection(runConsoleState: runConsoleState)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NativeTheme.window)
        .sheet(isPresented: $isRunConfigurationSheetPresented) {
            WorkspaceRunConfigurationSheet(
                viewModel: viewModel,
                project: project
            )
        }
        .alert(item: pendingEditorCloseRequestBinding) { request in
            Alert(
                title: Text("关闭未保存文件？"),
                message: Text(editorCloseRequestMessage(request)),
                primaryButton: .destructive(Text("直接关闭")) {
                    viewModel.confirmWorkspaceEditorCloseRequest()
                },
                secondaryButton: .cancel {
                    viewModel.dismissWorkspaceEditorCloseRequest()
                }
            )
        }
        .background {
            WindowFocusObserverView { activity in
                windowActivity = activity
            }
            .frame(width: 0, height: 0)
        }
        .onAppear {
            terminalSessionStore.syncSelectedItemIDs(selectedItemIDsByPane)
            terminalSessionStore.syncRetainedItemIDs(retainedItemIDs)
            browserSessionStore.syncRetainedItemIDs(retainedItemIDs)
            WorkspaceLaunchDiagnostics.shared.recordHostMounted(
                workspace: workspace.sessionState,
                isActive: project.path == viewModel.activeWorkspaceProjectPath
            )
        }
        .onChange(of: selectedItemIDsByPane) { _, selectedItemIDs in
            terminalSessionStore.syncSelectedItemIDs(selectedItemIDs)
        }
        .onChange(of: retainedItemIDs) { _, itemIDs in
            terminalSessionStore.syncRetainedItemIDs(itemIDs)
            browserSessionStore.syncRetainedItemIDs(itemIDs)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(NativeTheme.textPrimary)
                    Text(project.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(NativeTheme.textSecondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                actionButton(
                    title: "系统终端",
                    systemImage: "arrow.up.right.square",
                    action: {
                        do {
                            try viewModel.openWorkspaceInTerminal(project.path)
                        } catch {
                            // 错误已由 ViewModel 收口
                        }
                    }
                )
                if !project.isTransientWorkspaceProject {
                    actionButton(
                        title: "查看详情",
                        systemImage: "sidebar.right",
                        action: {
                            viewModel.selectProject(project.path)
                        }
                    )
                }
                statChip(
                    title: project.isWorkspaceRoot
                        ? "工作区根目录"
                        : project.gitCommits > 0
                            ? "\(project.gitCommits) 次提交"
                            : (project.isGitRepository ? "Git 项目" : "非 Git 项目"),
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                statChip(
                    title: workspace.selectedPane?.request.terminalRuntime ?? "ghostty",
                    systemImage: "terminal"
                )
                Spacer(minLength: 0)
            }
        }
    }

    private func runConsoleSection(
        runConsoleState: WorkspaceRunConsoleState
    ) -> some View {
        let panelHeight = WorkspaceRunConsoleLayoutPolicy.clampPanelHeight(CGFloat(runConsoleState.panelHeight))

        return VStack(spacing: 0) {
            WorkspaceRunConsoleResizeHandle(
                onDragChanged: { translation in
                    resizeRunConsole(translation: translation, currentHeight: panelHeight)
                },
                onDragEnded: { translation in
                    resizeRunConsole(translation: translation, currentHeight: panelHeight)
                    runConsoleResizeStartHeight = nil
                },
                onReset: {
                    let resetHeight = WorkspaceRunConsoleLayoutPolicy.clampPanelHeight(
                        WorkspaceRunConsoleLayoutPolicy.defaultPanelHeight
                    )
                    runConsoleResizeStartHeight = nil
                    viewModel.updateWorkspaceRunConsolePanelHeight(Double(resetHeight), in: project.path)
                }
            )

            WorkspaceRunConsolePanel(
                consoleState: runConsoleState,
                height: panelHeight,
                onSelectSession: { viewModel.selectWorkspaceRunSession($0, in: project.path) },
                onClear: { viewModel.clearSelectedWorkspaceRunConsoleBuffer(in: project.path) },
                onOpenLog: {
                    do {
                        try viewModel.openSelectedWorkspaceRunLog(in: project.path)
                    } catch {
                        // 错误已由 ViewModel 收口
                    }
                },
                onHide: {
                    runConsoleResizeStartHeight = nil
                    viewModel.toggleWorkspaceRunConsole(in: project.path)
                }
            )
        }
    }

    private func resizeRunConsole(
        translation: CGSize,
        currentHeight: CGFloat
    ) {
        let startHeight = runConsoleResizeStartHeight ?? currentHeight
        if runConsoleResizeStartHeight == nil {
            runConsoleResizeStartHeight = currentHeight
        }
        let proposedHeight = startHeight - translation.height
        let clampedHeight = WorkspaceRunConsoleLayoutPolicy.clampPanelHeight(proposedHeight)
        viewModel.updateWorkspaceRunConsolePanelHeight(Double(clampedHeight), in: project.path)
    }

    private func actionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(NativeTheme.elevated)
                .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func statChip(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.caption)
        .foregroundStyle(NativeTheme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(NativeTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
    }

    private var retainedItemIDs: Set<String> {
        Set(
            workspace.tabs
                .flatMap(\.leaves)
                .flatMap(\.items)
                .map(\.id)
        )
    }

    private var selectedItemIDsByPane: [String: String] {
        Dictionary(
            uniqueKeysWithValues: workspace.tabs
                .flatMap(\.leaves)
                .compactMap { pane in
                    pane.selectedItem.map { (pane.id, $0.id) }
                }
        )
    }

    private var pendingEditorCloseRequestBinding: Binding<WorkspaceEditorCloseRequest?> {
        Binding(
            get: {
                guard let request = viewModel.workspacePendingEditorCloseRequest,
                      request.projectPath == project.path
                else {
                    return nil
                }
                return request
            },
            set: { nextValue in
                if nextValue == nil {
                    viewModel.dismissWorkspaceEditorCloseRequest()
                }
            }
        )
    }

    private func canSplit(for selection: WorkspacePresentedTabSelection?) -> Bool {
        switch selection {
        case .terminal:
            return workspace.selectedPane != nil
        case .editor:
            return true
        case .diff, .none:
            return false
        }
    }

    private func editorCloseRequestMessage(_ request: WorkspaceEditorCloseRequest) -> String {
        var message = "文件“\(request.title)”还有未保存修改。直接关闭会丢失当前编辑内容。"
        if request.externalChangeState == .modifiedOnDisk {
            message += "\n\n磁盘上的原文件也已经发生变化。"
        } else if request.externalChangeState == .removedOnDisk {
            message += "\n\n磁盘上的原文件已经被删除。"
        }
        return message
    }

    @ViewBuilder
    private func workspacePresentedContent(_ selection: WorkspacePresentedTabSelection?) -> some View {
        switch selection {
        case let .editor(editorTabID):
            if let presentation = viewModel.workspaceEditorPresentationState(for: project.path),
               presentation.groups.count > 1 {
                WorkspaceEditorSplitContentView(
                    viewModel: viewModel,
                    projectPath: project.path,
                    presentation: presentation
                )
            } else if viewModel.workspaceEditorTabState(for: project.path, tabID: editorTabID) != nil {
                WorkspaceEditorTabView(
                    viewModel: viewModel,
                    projectPath: project.path,
                    tabID: editorTabID
                )
                .id(editorTabID)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        viewModel.setWorkspaceFocusedArea(.editorTab(editorTabID))
                    }
                )
            } else {
                editorTabUnavailableContent
            }
        case let .diff(diffTabID):
            if let diffViewModel = viewModel.workspaceDiffTabViewModel(for: project.path, tabID: diffTabID) {
                WorkspaceDiffTabView(
                    viewModel: diffViewModel,
                    displayOptions: viewModel.workspaceEditorDisplayOptions
                )
                    .id(diffTabID)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            viewModel.setWorkspaceFocusedArea(.diffTab(diffTabID))
                        }
                    )
            } else {
                diffTabUnavailableContent
            }
        case .terminal, .none:
            terminalTabContent
        }
    }

    @ViewBuilder
    private var terminalTabContent: some View {
        if let selectedTab = workspace.selectedTab {
            let isSelectedTab = isWorkspaceVisible
            // 只挂载当前选中的 terminal tab，避免隐藏 tab 继续参与
            // SwiftUI/AppKit 布局与 Ghostty surface 更新，造成主线程持续高负载。
            WorkspaceSplitTreeView(
                tab: selectedTab,
                isTabSelected: isSelectedTab,
                surfaceModelForPaneItem: { pane, item in
                    surfaceModel(for: pane, item: item)
                },
                browserModelForPaneItem: { pane, item in
                    browserModel(for: pane, item: item)
                },
                surfaceActivityForPaneItem: { pane, item in
                    surfaceActivity(for: pane, item: item)
                },
                onFocusPane: { workspace.focusPane($0) },
                onSelectPaneItem: { paneID, itemID in
                    workspace.focusPane(paneID)
                    workspace.selectPaneItem(inPane: paneID, itemID: itemID)
                    if let item = workspace.sessionState.selectedPane?.selectedItem, item.isBrowser {
                        viewModel.setWorkspaceFocusedArea(.browserPaneItem(item.id))
                    } else {
                        viewModel.setWorkspaceFocusedArea(.terminal)
                    }
                },
                onCreatePaneItem: { paneID in
                    workspace.focusPane(paneID)
                    _ = workspace.createTerminalItem(inPane: paneID)
                    viewModel.setWorkspaceFocusedArea(.terminal)
                },
                onCreateBrowserItem: { paneID in
                    workspace.focusPane(paneID)
                    if let item = workspace.createBrowserItem(inPane: paneID) {
                        viewModel.setWorkspaceFocusedArea(.browserPaneItem(item.id))
                    }
                },
                onClosePaneItem: { paneID, itemID in
                    workspace.focusPane(paneID)
                    requestClosePaneItem(paneID: paneID, itemID: itemID)
                },
                onClosePane: { requestClosePane($0) },
                onSplitPane: { paneID, direction in
                    workspace.focusPane(paneID)
                    _ = workspace.splitFocusedPane(direction: direction)
                },
                onFocusDirection: { paneID, direction in
                    workspace.focusPane(paneID)
                    workspace.focusPane(direction: direction)
                },
                onResizePane: { paneID, direction, amount in
                    workspace.focusPane(paneID)
                    workspace.resizeFocusedPane(direction: direction, amount: amount)
                },
                onEqualize: { paneID in
                    workspace.focusPane(paneID)
                    workspace.equalizeSelectedTabSplits()
                },
                onToggleZoom: { paneID in
                    workspace.focusPane(paneID)
                    workspace.toggleZoomOnFocusedPane()
                },
                onSurfaceExit: { workspace.closePane($0) },
                onUpdateTabTitle: { title in
                    workspace.updateTitle(for: selectedTab.id, title: title)
                },
                onNewTab: {
                    let newTab = workspace.createTab()
                    viewModel.selectWorkspacePresentedTab(.terminal(newTab.id), in: project.path)
                    return true
                },
                onCloseTabAction: { mode in
                    handleCloseTab(mode, tabID: selectedTab.id)
                },
                onGotoTabAction: handleGotoTab,
                onMoveTabAction: { move in
                    handleMoveTab(move, tabID: selectedTab.id)
                },
                onMovePaneItem: { sourcePaneID, itemID, targetPaneID, targetIndex in
                    workspace.focusPane(sourcePaneID)
                    _ = workspace.movePaneItem(
                        itemID,
                        from: sourcePaneID,
                        to: targetPaneID,
                        at: targetIndex
                    )
                },
                onSplitPaneItem: { sourcePaneID, itemID, targetPaneID, direction in
                    workspace.focusPane(sourcePaneID)
                    _ = workspace.splitPaneItem(
                        itemID,
                        from: sourcePaneID,
                        beside: targetPaneID,
                        direction: direction
                    )
                },
                onSetSplitRatio: { path, ratio in
                    workspace.setSelectedTabSplitRatio(at: path, ratio: ratio)
                },
                onMovePane: { sourcePaneID, targetPaneID, direction in
                    workspace.movePane(sourcePaneID, beside: targetPaneID, direction: direction)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyView()
        }
    }

    private var diffTabUnavailableContent: some View {
        ContentUnavailableView(
            "Diff 标签页不可用",
            systemImage: "square.split.2x1",
            description: Text("当前 diff 标签页状态已失效，请重新从 changes browser 打开。")
        )
        .foregroundStyle(NativeTheme.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorTabUnavailableContent: some View {
        ContentUnavailableView(
            "编辑器标签页不可用",
            systemImage: "doc.text",
            description: Text("当前编辑器标签页状态已失效，请重新从 Project 树打开。")
        )
        .foregroundStyle(NativeTheme.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func surfaceModel(
        for pane: WorkspacePaneState,
        item: WorkspacePaneItemState
    ) -> GhosttySurfaceHostModel {
        let itemID = item.id
        return terminalSessionStore.model(
            for: item,
            in: pane,
            onFocusChange: { focused in
                guard focused else { return }
                guard let context = self.currentPaneItemContext(for: itemID) else {
                    return
                }
                workspace.focusPane(context.pane.id)
                workspace.selectPaneItem(inPane: context.pane.id, itemID: context.item.id)
                viewModel.markWorkspaceNotificationsRead(
                    projectPath: context.item.request.projectPath,
                    paneID: context.pane.id
                )
            },
            onSurfaceExit: {
                guard let context = self.currentPaneItemContext(for: itemID) else {
                    return
                }
                workspace.closePaneItem(inPane: context.pane.id, itemID: context.item.id)
            },
            onNotificationEvent: { title, body in
                guard let context = self.currentPaneItemContext(for: itemID) else {
                    return
                }
                viewModel.recordWorkspaceNotification(
                    projectPath: context.item.request.projectPath,
                    tabID: context.item.request.tabId,
                    paneID: context.pane.id,
                    title: title,
                    body: body
                )
                WorkspaceNotificationPresenter.presentIfNeeded(
                    title: title,
                    body: body,
                    settings: viewModel.snapshot.appState.settings
                )
            },
            onTaskStatusChange: { status in
                guard let context = self.currentPaneItemContext(for: itemID) else {
                    return
                }
                viewModel.updateWorkspaceTaskStatus(
                    projectPath: context.item.request.projectPath,
                    paneID: context.pane.id,
                    status: status
                )
            },
            onNewTab: {
                guard let context = self.currentPaneItemContext(for: itemID) else {
                    return false
                }
                workspace.focusPane(context.pane.id)
                if let newItem = workspace.createTerminalItem(inPane: context.pane.id),
                   let updatedPane = workspace.sessionState.selectedPane {
                    _ = self.surfaceModel(for: updatedPane, item: newItem)
                }
                return true
            },
            onCloseTab: { mode in
                guard let context = self.currentPaneItemContext(for: itemID) else {
                    return false
                }
                return self.handlePaneItemCloseTab(mode, paneID: context.pane.id, itemID: context.item.id)
            },
            onGotoTab: { target in
                guard let context = self.currentPaneItemContext(for: itemID) else {
                    return false
                }
                return self.handlePaneItemGotoTab(target, paneID: context.pane.id)
            },
            onMoveTab: { move in
                guard let context = self.currentPaneItemContext(for: itemID) else {
                    return false
                }
                return self.handlePaneItemMoveTab(move, paneID: context.pane.id, itemID: context.item.id)
            },
            onSplitAction: { action in
                guard let context = self.currentPaneItemContext(for: itemID) else {
                    return false
                }
                workspace.focusPane(context.pane.id)
                return self.handleSplitAction(action, paneID: context.pane.id)
            }
        )
    }

    private func browserModel(
        for pane: WorkspacePaneState,
        item: WorkspacePaneItemState
    ) -> WorkspaceBrowserHostModel? {
        guard item.isBrowser,
              let state = item.browserState
        else {
            return nil
        }

        let itemID = item.id
        return browserSessionStore.model(
            for: state,
            onStateChange: { snapshot in
                guard let context = self.currentPaneItemContext(for: itemID),
                      context.item.isBrowser
                else {
                    return
                }
                let projectionUpdate = WorkspaceBrowserProjectionPolicy.resolve(
                    existing: context.item.browserState,
                    runtime: snapshot
                )
                WorkspaceBrowserDiagnostics.recordProjectionUpdate(
                    surfaceId: context.item.id,
                    tabId: context.item.request.tabId,
                    paneId: context.pane.id,
                    runtime: snapshot,
                    projected: projectionUpdate
                )
                _ = workspace.updateBrowserState(
                    inPane: context.pane.id,
                    itemID: context.item.id,
                    title: projectionUpdate.title,
                    urlString: projectionUpdate.urlString,
                    isLoading: projectionUpdate.isLoading
                )
            }
        )
    }

    private func surfaceActivity(
        for pane: WorkspacePaneState,
        item: WorkspacePaneItemState
    ) -> WorkspaceSurfaceActivity {
        WorkspaceSurfaceActivityPolicy.activity(
            isWorkspaceVisible: isWorkspaceVisible,
            isSelectedTab: item.request.tabId == workspace.selectedTabId,
            windowIsVisible: windowActivity.isVisible,
            windowIsKey: windowActivity.isKeyWindow,
            focusedPaneID: workspace.tabs.first(where: { $0.id == item.request.tabId })?.focusedPaneId,
            paneID: pane.id
        )
    }

    private func currentPaneItemContext(
        for itemID: String
    ) -> (pane: WorkspacePaneState, item: WorkspacePaneItemState)? {
        for tab in workspace.tabs {
            for pane in tab.leaves {
                if let item = pane.items.first(where: { $0.id == itemID }) {
                    return (pane, item)
                }
            }
        }
        return nil
    }

    private var isWorkspaceVisible: Bool {
        viewModel.isWorkspacePresented && project.path == viewModel.activeWorkspaceProjectPath
    }

    private func handleSplitAction(_ action: GhosttySplitAction, paneID: String) -> Bool {
        switch action {
        case let .newSplit(direction):
            workspace.focusPane(paneID)
            _ = workspace.splitFocusedPane(direction: direction)
            return true
        case let .gotoSplit(direction):
            workspace.focusPane(paneID)
            workspace.focusPane(direction: direction)
            return true
        case let .resizeSplit(direction, amount):
            workspace.focusPane(paneID)
            workspace.resizeFocusedPane(direction: direction, amount: amount)
            return true
        case .equalizeSplits:
            workspace.focusPane(paneID)
            workspace.equalizeSelectedTabSplits()
            return true
        case .toggleSplitZoom:
            workspace.focusPane(paneID)
            workspace.toggleZoomOnFocusedPane()
            return true
        }
    }

    private func handleCloseTab(_ mode: ghostty_action_close_tab_mode_e, tabID: String) -> Bool {
        switch mode {
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_THIS:
            closeTerminalTab(tabID)
            return true
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_OTHER:
            let affectedTabIDs = workspace.tabs
                .map(\.id)
                .filter { $0 != tabID }
            confirmCloseTabs(
                affectedTabIDs,
                actionDescription: "关闭其他标签页"
            ) {
                workspace.closeOtherTabs(keeping: tabID)
            }
            return true
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_RIGHT:
            let affectedTabIDs = terminalTabIDsToRight(of: tabID)
            confirmCloseTabs(
                affectedTabIDs,
                actionDescription: "关闭右侧标签页"
            ) {
                workspace.closeTabsToRight(of: tabID)
            }
            return true
        default:
            return false
        }
    }

    private func closePresentedTab(_ selection: WorkspacePresentedTabSelection) {
        switch selection {
        case let .terminal(tabID):
            closeTerminalTab(tabID)
        case let .editor(editorTabID):
            viewModel.closeWorkspaceEditorTab(editorTabID, in: project.path)
        case let .diff(diffTabID):
            viewModel.closeWorkspaceDiffTab(diffTabID, in: project.path)
        }
    }

    private func closeTerminalTab(_ tabID: String) {
        confirmCloseTabs([tabID], actionDescription: "关闭整个标签页") {
            closeTerminalTabNow(tabID)
        }
    }

    private func closeTerminalTabNow(_ tabID: String) {
        if shouldCloseTransientWorkspace(for: .tab) {
            viewModel.closeWorkspaceProjectWithFeedback(project.path)
            return
        }
        if workspace.tabs.count == 1,
           let fallbackSelection = fallbackPresentedSelectionAfterClosingLastTerminalTab() {
            viewModel.selectWorkspacePresentedTab(fallbackSelection, in: project.path)
            workspace.closeTabAllowingEmpty(tabID)
            return
        }
        if workspace.tabs.count == 1 {
            viewModel.closeWorkspaceSessionWithFeedback(project.path)
            return
        }
        workspace.closeTab(tabID)
    }

    private func shouldCloseTransientWorkspace(
        for action: WorkspaceTransientTerminalCloseAction
    ) -> Bool {
        let snapshot = viewModel.workspacePresentedTabSnapshot(for: project.path)
        let hasEditorTabs = snapshot.items.contains { item in
            if case .editor = item.selection {
                return true
            }
            return false
        }
        let hasDiffTabs = snapshot.items.contains { item in
            if case .diff = item.selection {
                return true
            }
            return false
        }
        return WorkspaceTransientClosePolicy.shouldCloseWorkspace(
            for: action,
            project: project,
            terminalTabCount: workspace.tabs.count,
            hasEditorTabs: hasEditorTabs,
            hasDiffTabs: hasDiffTabs
        )
    }

    private func fallbackPresentedSelectionAfterClosingLastTerminalTab() -> WorkspacePresentedTabSelection? {
        let snapshot = viewModel.workspacePresentedTabSnapshot(for: project.path)
        if let editor = snapshot.items.last(where: { item in
            if case .editor = item.selection {
                return true
            }
            return false
        }) {
            return editor.selection
        }
        if let diff = snapshot.items.last(where: { item in
            if case .diff = item.selection {
                return true
            }
            return false
        }) {
            return diff.selection
        }
        return nil
    }

    private func handleGotoTab(_ target: ghostty_action_goto_tab_e) -> Bool {
        let raw = Int(target.rawValue)
        if raw > 0 {
            workspace.gotoTab(at: raw)
            return true
        }

        switch raw {
        case Int(GHOSTTY_GOTO_TAB_PREVIOUS.rawValue):
            workspace.gotoPreviousTab()
            return true
        case Int(GHOSTTY_GOTO_TAB_NEXT.rawValue):
            workspace.gotoNextTab()
            return true
        case Int(GHOSTTY_GOTO_TAB_LAST.rawValue):
            workspace.gotoLastTab()
            return true
        default:
            return false
        }
    }

    private func handleMoveTab(_ move: ghostty_action_move_tab_s, tabID: String) -> Bool {
        let amount = Int(move.amount)
        guard amount != 0 else {
            return false
        }
        workspace.moveTab(id: tabID, by: amount)
        return true
    }

    private func handlePaneItemCloseTab(
        _ mode: ghostty_action_close_tab_mode_e,
        paneID: String,
        itemID: String
    ) -> Bool {
        switch mode {
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_THIS:
            requestClosePaneItem(paneID: paneID, itemID: itemID)
            return true
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_OTHER:
            let affectedItemIDs = paneState(for: paneID)?
                .items
                .map(\.id)
                .filter { $0 != itemID } ?? []
            confirmClosePaneItems(
                affectedItemIDs,
                actionDescription: "关闭其他终端标签"
            ) {
                workspace.closeOtherPaneItems(inPane: paneID, keeping: itemID)
            }
            return true
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_RIGHT:
            let affectedItemIDs = paneItemIDsToRight(inPane: paneID, of: itemID)
            confirmClosePaneItems(
                affectedItemIDs,
                actionDescription: "关闭右侧终端标签"
            ) {
                workspace.closePaneItemsToRight(inPane: paneID, of: itemID)
            }
            return true
        default:
            return false
        }
    }

    private func requestClosePane(_ paneID: String) {
        confirmClosePaneItems(
            terminalItemIDs(inPane: paneID),
            actionDescription: "关闭整个窗格"
        ) {
            workspace.closePane(paneID)
        }
    }

    private func requestClosePaneItem(
        paneID: String,
        itemID: String
    ) {
        guard let pane = paneState(for: paneID),
              let item = pane.items.first(where: { $0.id == itemID })
        else {
            return
        }

        let performClose = {
            workspace.closePaneItem(inPane: paneID, itemID: itemID)
            if let selectedBrowser = workspace.selectedPane?.selectedBrowserState {
                viewModel.setWorkspaceFocusedArea(.browserPaneItem(selectedBrowser.id))
            } else {
                viewModel.setWorkspaceFocusedArea(.terminal)
            }
        }

        guard item.isTerminal else {
            performClose()
            return
        }

        confirmClosePaneItems(
            [itemID],
            actionDescription: "关闭终端标签",
            performClose: performClose
        )
    }

    private func confirmCloseTabs(
        _ tabIDs: [String],
        actionDescription: String,
        performClose: @escaping () -> Void
    ) {
        let itemIDs = tabIDs.flatMap { terminalItemIDs(inTab: $0) }
        confirmClosePaneItems(
            itemIDs,
            actionDescription: actionDescription,
            performClose: performClose
        )
    }

    private func confirmClosePaneItems(
        _ itemIDs: [String],
        actionDescription: String,
        performClose: @escaping () -> Void
    ) {
        let evaluators: [any WorkspaceTerminalCloseRequirementEvaluating] = itemIDs.compactMap { itemID in
            terminalSessionStore.modelIfLoaded(forItemID: itemID).map { $0 as any WorkspaceTerminalCloseRequirementEvaluating }
        }
        WorkspaceTerminalCloseCoordinator.confirmIfNeeded(
            evaluators: evaluators,
            actionDescription: actionDescription,
            performClose: performClose
        )
    }

    private func paneState(for paneID: String) -> WorkspacePaneState? {
        workspace.tabs
            .flatMap(\.leaves)
            .first(where: { $0.id == paneID })
    }

    private func tabState(for tabID: String) -> WorkspaceTabState? {
        workspace.tabs.first(where: { $0.id == tabID })
    }

    private func terminalItemIDs(inPane paneID: String) -> [String] {
        paneState(for: paneID)?
            .items
            .filter(\.isTerminal)
            .map(\.id) ?? []
    }

    private func terminalItemIDs(inTab tabID: String) -> [String] {
        tabState(for: tabID)?
            .leaves
            .flatMap { pane in
                pane.items.filter(\.isTerminal).map(\.id)
            } ?? []
    }

    private func terminalTabIDsToRight(of tabID: String) -> [String] {
        guard let index = workspace.tabs.firstIndex(where: { $0.id == tabID }) else {
            return []
        }
        return Array(workspace.tabs.dropFirst(index + 1)).map(\.id)
    }

    private func paneItemIDsToRight(
        inPane paneID: String,
        of itemID: String
    ) -> [String] {
        guard let pane = paneState(for: paneID),
              let index = pane.items.firstIndex(where: { $0.id == itemID })
        else {
            return []
        }
        return Array(pane.items.dropFirst(index + 1)).map(\.id)
    }

    private func handlePaneItemGotoTab(
        _ target: ghostty_action_goto_tab_e,
        paneID: String
    ) -> Bool {
        let raw = Int(target.rawValue)
        if raw > 0 {
            workspace.gotoPaneItem(at: raw, inPane: paneID)
            return true
        }

        switch raw {
        case Int(GHOSTTY_GOTO_TAB_PREVIOUS.rawValue):
            workspace.gotoPreviousPaneItem(inPane: paneID)
            return true
        case Int(GHOSTTY_GOTO_TAB_NEXT.rawValue):
            workspace.gotoNextPaneItem(inPane: paneID)
            return true
        case Int(GHOSTTY_GOTO_TAB_LAST.rawValue):
            workspace.gotoLastPaneItem(inPane: paneID)
            return true
        default:
            return false
        }
    }

    private func handlePaneItemMoveTab(
        _ move: ghostty_action_move_tab_s,
        paneID: String,
        itemID: String
    ) -> Bool {
        let amount = Int(move.amount)
        guard amount != 0 else {
            return false
        }
        workspace.movePaneItem(inPane: paneID, itemID: itemID, by: amount)
        return true
    }
}

private struct WorkspaceRunConsoleResizeHandle: View {
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void
    let onReset: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(NativeTheme.border.opacity(0.9))
                .frame(height: 1)

            Capsule()
                .fill(NativeTheme.textSecondary.opacity(0.7))
                .frame(width: 40, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 12)
        .background(NativeTheme.window)
        .contentShape(.rect)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    onDragChanged(gesture.translation)
                }
                .onEnded { gesture in
                    onDragEnded(gesture.translation)
                }
        )
        .onTapGesture(count: 2, perform: onReset)
    }
}

private enum WorkspaceRunConsoleLayoutPolicy {
    static let defaultPanelHeight = CGFloat(WorkspaceRunConsoleState.defaultPanelHeight)
    private static let minPanelHeight: CGFloat = 140
    private static let maxPanelHeight: CGFloat = 420

    static func clampPanelHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, minPanelHeight), maxPanelHeight)
    }
}
