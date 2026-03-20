import SwiftUI
import GhosttyKit
import DevHavenCore

struct WorkspaceHostView: View {
    @Bindable var viewModel: NativeAppViewModel
    let project: Project
    let workspace: WorkspaceSessionState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            WorkspaceTabBarView(
                tabs: workspace.tabs,
                selectedTabID: workspace.selectedTabId,
                canSplit: workspace.selectedPane != nil,
                onSelectTab: { viewModel.selectWorkspaceTab($0, in: project.path) },
                onCloseTab: { viewModel.closeWorkspaceTab($0, in: project.path) },
                onCreateTab: { viewModel.createWorkspaceTab(in: project.path) },
                onSplitHorizontally: {
                    viewModel.splitWorkspaceFocusedPane(direction: .down, in: project.path)
                },
                onSplitVertically: {
                    viewModel.splitWorkspaceFocusedPane(direction: .right, in: project.path)
                }
            )
            ZStack {
                ForEach(workspace.tabs) { tab in
                    WorkspaceSplitTreeView(
                        tab: tab,
                        isTabSelected: tab.id == workspace.selectedTabId,
                        onFocusPane: { viewModel.focusWorkspacePane($0, in: project.path) },
                        onClosePane: { viewModel.closeWorkspacePane($0, in: project.path) },
                        onSplitPane: { paneID, direction in
                            viewModel.focusWorkspacePane(paneID, in: project.path)
                            viewModel.splitWorkspaceFocusedPane(direction: direction, in: project.path)
                        },
                        onFocusDirection: { paneID, direction in
                            viewModel.focusWorkspacePane(paneID, in: project.path)
                            viewModel.focusWorkspacePane(direction: direction, in: project.path)
                        },
                        onResizePane: { paneID, direction, amount in
                            viewModel.focusWorkspacePane(paneID, in: project.path)
                            viewModel.resizeWorkspaceFocusedPane(direction: direction, amount: amount, in: project.path)
                        },
                        onEqualize: { paneID in
                            viewModel.focusWorkspacePane(paneID, in: project.path)
                            viewModel.equalizeWorkspaceSplits(in: project.path)
                        },
                        onToggleZoom: { paneID in
                            viewModel.focusWorkspacePane(paneID, in: project.path)
                            viewModel.toggleWorkspaceFocusedPaneZoom(in: project.path)
                        },
                        onSurfaceExit: { viewModel.closeWorkspacePane($0, in: project.path) },
                        onUpdateTabTitle: { title in
                            viewModel.updateWorkspaceTabTitle(title, for: tab.id, in: project.path)
                        },
                        onNewTab: {
                            viewModel.createWorkspaceTab(in: project.path)
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
                            viewModel.setWorkspaceSelectedTabSplitRatio(at: path, ratio: ratio, in: project.path)
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
        .padding(20)
        .background(NativeTheme.window)
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

    private func handleCloseTab(_ mode: ghostty_action_close_tab_mode_e, tabID: String) -> Bool {
        switch mode {
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_THIS:
            viewModel.closeWorkspaceTab(tabID, in: project.path)
            return true
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_OTHER:
            viewModel.closeWorkspaceOtherTabs(keeping: tabID, in: project.path)
            return true
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_RIGHT:
            viewModel.closeWorkspaceTabsToRight(of: tabID, in: project.path)
            return true
        default:
            return false
        }
    }

    private func handleGotoTab(_ target: ghostty_action_goto_tab_e) -> Bool {
        let raw = Int(target.rawValue)
        if raw > 0 {
            viewModel.gotoWorkspaceTab(at: raw, in: project.path)
            return true
        }

        switch raw {
        case Int(GHOSTTY_GOTO_TAB_PREVIOUS.rawValue):
            viewModel.gotoPreviousWorkspaceTab(in: project.path)
            return true
        case Int(GHOSTTY_GOTO_TAB_NEXT.rawValue):
            viewModel.gotoNextWorkspaceTab(in: project.path)
            return true
        case Int(GHOSTTY_GOTO_TAB_LAST.rawValue):
            viewModel.gotoLastWorkspaceTab(in: project.path)
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
        viewModel.moveWorkspaceTab(tabID, by: amount, in: project.path)
        return true
    }
}
