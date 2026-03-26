import SwiftUI
import GhosttyKit
import DevHavenCore

struct WorkspaceHostView: View {
    @Bindable var viewModel: NativeAppViewModel
    let project: Project
    let workspace: GhosttyWorkspaceController
    let terminalSessionStore: WorkspaceTerminalSessionStore
    @State private var windowActivity: WindowActivityState = .inactive

    var body: some View {
        let chromePolicy = WorkspaceChromePolicy.workspaceMinimal
        let presentedTabs = viewModel.workspacePresentedTabs(for: project.path)
        let selectedPresentedTab = viewModel.workspaceSelectedPresentedTab(for: project.path)

        VStack(alignment: .leading, spacing: chromePolicy.showsWorkspaceHeader ? 16 : 0) {
            if chromePolicy.showsWorkspaceHeader {
                header
            }

            WorkspaceTabBarView(
                tabs: presentedTabs,
                canSplit: canSplit(for: selectedPresentedTab),
                onSelectTab: { selection in
                    viewModel.selectWorkspacePresentedTab(selection, in: project.path)
                },
                onCloseTab: { selection in
                    closePresentedTab(selection)
                },
                onCreateTab: {
                    let tab = workspace.createTab()
                    viewModel.selectWorkspacePresentedTab(.terminal(tab.id), in: project.path)
                },
                onSplitHorizontally: {
                    _ = workspace.splitFocusedPane(direction: .down)
                },
                onSplitVertically: {
                    _ = workspace.splitFocusedPane(direction: .right)
                }
            )
            workspacePresentedContent(selectedPresentedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NativeTheme.window)
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
                actionButton(
                    title: "查看详情",
                    systemImage: "sidebar.right",
                    action: {
                        viewModel.selectProject(project.path)
                    }
                )
                statChip(
                    title: project.gitCommits > 0
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

    private func canSplit(for selection: WorkspacePresentedTabSelection?) -> Bool {
        guard case .terminal = selection else {
            return false
        }
        return workspace.selectedPane != nil
    }

    @ViewBuilder
    private func workspacePresentedContent(_ selection: WorkspacePresentedTabSelection?) -> some View {
        switch selection {
        case let .diff(diffTabID):
            if let diffViewModel = viewModel.workspaceDiffTabViewModel(for: project.path, tabID: diffTabID) {
                WorkspaceDiffTabView(viewModel: diffViewModel)
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

    private func surfaceModel(for pane: WorkspacePaneState) -> GhosttySurfaceHostModel {
        let model = terminalSessionStore.model(
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
        let activity = WorkspaceSurfaceActivityPolicy.activity(
            isWorkspaceVisible: isWorkspaceVisible,
            isSelectedTab: pane.request.tabId == workspace.selectedTabId,
            windowIsVisible: windowActivity.isVisible,
            windowIsKey: windowActivity.isKeyWindow,
            focusedPaneID: workspace.tabs.first(where: { $0.id == pane.request.tabId })?.focusedPaneId,
            paneID: pane.id
        )
        model.syncSurfaceActivity(isVisible: activity.isVisible, isFocused: activity.isFocused)
        if activity.isFocused {
            model.restoreWindowResponderIfNeeded()
        }
        return model
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
