import SwiftUI
import GhosttyKit
import DevHavenCore

struct WorkspaceHostView: View {
    @Bindable var viewModel: NativeAppViewModel
    let project: Project
    let workspace: GhosttyWorkspaceController
    let terminalSessionStore: WorkspaceTerminalSessionStore
    @State private var windowActivity: WindowActivityState = .inactive
    @State private var isRunConfigurationSheetPresented = false
    @State private var runConsoleResizeStartHeight: CGFloat?

    var body: some View {
        let chromePolicy = WorkspaceChromePolicy.workspaceMinimal
        let presentedTabs = viewModel.workspacePresentedTabs(for: project.path)
        let selectedPresentedTab = viewModel.workspaceSelectedPresentedTab(for: project.path)
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
                        let tab = workspace.createTab()
                        viewModel.selectWorkspacePresentedTab(.terminal(tab.id), in: project.path)
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
            terminalSessionStore.syncRetainedPaneIDs(retainedPaneIDs)
            WorkspaceLaunchDiagnostics.shared.recordHostMounted(
                workspace: workspace.sessionState,
                isActive: project.path == viewModel.activeWorkspaceProjectPath
            )
        }
        .onChange(of: retainedPaneIDs) { _, paneIDs in
            terminalSessionStore.syncRetainedPaneIDs(paneIDs)
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

    private var retainedPaneIDs: Set<String> {
        Set(workspace.tabs.flatMap(\.leaves).map(\.id))
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
                WorkspaceDiffTabView(viewModel: diffViewModel)
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

    private var terminalTabContent: some View {
        let terminalTabs = workspace.tabs
        return ZStack {
            ForEach(terminalTabs) { tab in
                WorkspaceSplitTreeView(
                    tab: tab,
                    isTabSelected: tab.id == workspace.selectedTabId,
                    surfaceModelForPane: surfaceModel,
                    surfaceActivityForPane: surfaceActivity,
                    onFocusPane: { workspace.focusPane($0) },
                    onClosePane: { workspace.closePane($0) },
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
                        workspace.updateTitle(for: tab.id, title: title)
                    },
                    onNewTab: {
                        let newTab = workspace.createTab()
                        viewModel.selectWorkspacePresentedTab(.terminal(newTab.id), in: project.path)
                        return true
                    },
                    onCloseTabAction: { mode in
                        handleCloseTab(mode, tabID: tab.id)
                    },
                    onGotoTabAction: handleGotoTab,
                    onMoveTabAction: { move in
                        handleMoveTab(move, tabID: tab.id)
                    },
                    onSetSplitRatio: { path, ratio in
                        guard tab.id == workspace.selectedTabId else {
                            return
                        }
                        workspace.setSelectedTabSplitRatio(at: path, ratio: ratio)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(tab.id == workspace.selectedTabId ? 1 : 0)
                .allowsHitTesting(tab.id == workspace.selectedTabId)
                .accessibilityHidden(tab.id != workspace.selectedTabId)
            }
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

    private func surfaceModel(for pane: WorkspacePaneState) -> GhosttySurfaceHostModel {
        terminalSessionStore.model(
            for: pane,
            onFocusChange: { focused in
                guard focused else { return }
                workspace.focusPane(pane.id)
                viewModel.markWorkspaceNotificationsRead(projectPath: pane.request.projectPath, paneID: pane.id)
            },
            onSurfaceExit: {
                workspace.closePane(pane.id)
            },
            onTabTitleChange: { title in
                workspace.updateTitle(for: pane.request.tabId, title: title)
            },
            onNotificationEvent: { title, body in
                viewModel.recordWorkspaceNotification(
                    projectPath: pane.request.projectPath,
                    tabID: pane.request.tabId,
                    paneID: pane.id,
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
                viewModel.updateWorkspaceTaskStatus(
                    projectPath: pane.request.projectPath,
                    paneID: pane.id,
                    status: status
                )
            },
            onNewTab: {
                _ = workspace.createTab()
                return true
            },
            onCloseTab: { mode in
                self.handleCloseTab(mode, tabID: pane.request.tabId)
            },
            onGotoTab: { target in
                self.handleGotoTab(target)
            },
            onMoveTab: { move in
                self.handleMoveTab(move, tabID: pane.request.tabId)
            },
            onSplitAction: { action in
                workspace.focusPane(pane.id)
                return self.handleSplitAction(action, paneID: pane.id)
            }
        )
    }

    private func surfaceActivity(for pane: WorkspacePaneState) -> WorkspaceSurfaceActivity {
        WorkspaceSurfaceActivityPolicy.activity(
            isWorkspaceVisible: isWorkspaceVisible,
            isSelectedTab: pane.request.tabId == workspace.selectedTabId,
            windowIsVisible: windowActivity.isVisible,
            windowIsKey: windowActivity.isKeyWindow,
            focusedPaneID: workspace.tabs.first(where: { $0.id == pane.request.tabId })?.focusedPaneId,
            paneID: pane.id
        )
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
            workspace.closeTab(tabID)
            return true
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_OTHER:
            workspace.closeOtherTabs(keeping: tabID)
            return true
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_RIGHT:
            workspace.closeTabsToRight(of: tabID)
            return true
        default:
            return false
        }
    }

    private func closePresentedTab(_ selection: WorkspacePresentedTabSelection) {
        switch selection {
        case let .terminal(tabID):
            workspace.closeTab(tabID)
        case let .editor(editorTabID):
            viewModel.closeWorkspaceEditorTab(editorTabID, in: project.path)
        case let .diff(diffTabID):
            viewModel.closeWorkspaceDiffTab(diffTabID, in: project.path)
        }
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
