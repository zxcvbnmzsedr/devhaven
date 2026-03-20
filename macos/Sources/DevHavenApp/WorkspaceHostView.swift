import SwiftUI
import GhosttyKit
import DevHavenCore

struct WorkspaceHostView: View {
    @Bindable var viewModel: NativeAppViewModel
    let project: Project
    let workspace: GhosttyWorkspaceController
    @StateObject private var surfaceRegistry = WorkspaceSurfaceRegistry()

    var body: some View {
        let chromePolicy = WorkspaceChromePolicy.workspaceMinimal

        VStack(alignment: .leading, spacing: chromePolicy.showsWorkspaceHeader ? 16 : 0) {
            if chromePolicy.showsWorkspaceHeader {
                header
            }

            WorkspaceTabBarView(
                tabs: workspace.tabs,
                selectedTabID: workspace.selectedTabId,
                canSplit: workspace.selectedPane != nil,
                onSelectTab: { workspace.selectTab($0) },
                onCloseTab: { workspace.closeTab($0) },
                onCreateTab: { _ = workspace.createTab() },
                onSplitHorizontally: {
                    _ = workspace.splitFocusedPane(direction: .down)
                },
                onSplitVertically: {
                    _ = workspace.splitFocusedPane(direction: .right)
                }
            )
            ZStack {
                ForEach(workspace.tabs) { tab in
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
                            _ = workspace.createTab()
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NativeTheme.window)
        .onAppear {
            surfaceRegistry.syncRetainedPaneIDs(retainedPaneIDs)
            WorkspaceLaunchDiagnostics.shared.recordHostMounted(
                workspace: workspace.sessionState,
                isActive: project.path == viewModel.activeWorkspaceProjectPath
            )
        }
        .onChange(of: retainedPaneIDs) { _, paneIDs in
            surfaceRegistry.syncRetainedPaneIDs(paneIDs)
        }
        .onDisappear {
            surfaceRegistry.releaseAll()
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
                    title: "\(project.gitCommits) 次提交",
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

    private func surfaceModel(for pane: WorkspacePaneState) -> GhosttySurfaceHostModel {
        surfaceRegistry.model(
            for: pane,
            onFocusChange: { focused in
                guard focused else { return }
                workspace.focusPane(pane.id)
            },
            onSurfaceExit: {
                workspace.closePane(pane.id)
            },
            onTabTitleChange: { title in
                workspace.updateTitle(for: pane.request.tabId, title: title)
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
