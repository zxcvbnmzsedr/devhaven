import SwiftUI
import DevHavenCore

struct WorkspaceShellView: View {
    @Bindable var viewModel: NativeAppViewModel
    @State private var codexDisplayRefreshState = CodexAgentDisplayStateRefresher.RuntimeState()
    @StateObject private var terminalStoreRegistry = WorkspaceTerminalStoreRegistry()
    private let codexDisplayRefreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        workspaceContent
            .background(NativeTheme.window)
            .focusedSceneValue(\.startTerminalSearchAction, startTerminalSearchAction)
            .focusedSceneValue(\.searchSelectionAction, searchSelectionAction)
            .focusedSceneValue(\.navigateTerminalSearchNextAction, navigateTerminalSearchNextAction)
            .focusedSceneValue(\.navigateTerminalSearchPreviousAction, navigateTerminalSearchPreviousAction)
            .focusedSceneValue(\.endTerminalSearchAction, endTerminalSearchAction)
            .onReceive(codexDisplayRefreshTimer) { _ in
                refreshCodexDisplayStates()
            }
            .onAppear {
                viewModel.setWorkspacePaneSnapshotProvider(workspacePaneSnapshotProvider)
                viewModel.startWorkspaceAgentSignalObservation()
                syncTerminalStores()
                warmActiveWorkspace()
                viewModel.syncActiveWorkspaceToolWindowContext()
                refreshCodexDisplayStates()
                WorkspaceLaunchDiagnostics.shared.recordShellMounted(
                    activeProjectPath: viewModel.activeWorkspaceProjectPath,
                    openSessionCount: viewModel.openWorkspaceSessions.count
                )
            }
            .onDisappear {
                viewModel.stopWorkspaceAgentSignalObservation()
                viewModel.setWorkspacePaneSnapshotProvider(nil)
            }
            .onChange(of: viewModel.openWorkspaceProjectPaths) { _, _ in
                syncTerminalStores()
                viewModel.refreshWorkspaceAgentSignals()
                warmActiveWorkspace()
                viewModel.syncActiveWorkspaceToolWindowContext()
                refreshCodexDisplayStates()
            }
            .onChange(of: viewModel.activeWorkspaceProjectPath) { _, _ in
                warmActiveWorkspace()
                viewModel.syncActiveWorkspaceToolWindowContext()
                refreshCodexDisplayStates()
            }
            .onChange(of: viewModel.workspaceBottomToolWindowState.activeKind) { _, _ in
                viewModel.syncActiveWorkspaceToolWindowContext()
            }
            .onChange(of: viewModel.workspaceBottomToolWindowState.isVisible) { _, _ in
                viewModel.syncActiveWorkspaceToolWindowContext()
            }
            .onChange(of: viewModel.workspaceSideToolWindowState.activeKind) { _, _ in
                viewModel.syncActiveWorkspaceToolWindowContext()
            }
            .onChange(of: viewModel.workspaceSideToolWindowState.isVisible) { _, _ in
                viewModel.syncActiveWorkspaceToolWindowContext()
            }
            .onChange(of: viewModel.activeWorkspaceLaunchRequest?.paneId) { _, _ in
                warmActiveWorkspace()
                refreshCodexDisplayStates()
            }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        if viewModel.openWorkspaceSessions.isEmpty {
            ContentUnavailableView(
                "没有已打开项目",
                systemImage: "terminal",
                description: Text("当前 workspace 中没有可展示的项目。")
            )
            .foregroundStyle(NativeTheme.textSecondary)
        } else {
            GeometryReader { geometry in
                bottomToolWindowHost(totalSize: geometry.size)
            }
        }
    }

    private var terminalModeContent: some View {
        ZStack {
            ForEach(viewModel.openWorkspaceSessions) { session in
                let project: Project? = session.isQuickTerminal
                    ? .quickTerminal(at: session.projectPath)
                    : viewModel.openWorkspaceProjects.first(where: { $0.path == session.projectPath })
                if let project {
                    WorkspaceHostView(
                        viewModel: viewModel,
                        project: project,
                        workspace: session.controller,
                        terminalSessionStore: terminalStoreRegistry.store(for: session.projectPath)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(session.projectPath == viewModel.activeWorkspaceProjectPath ? 1 : 0)
                    .allowsHitTesting(session.projectPath == viewModel.activeWorkspaceProjectPath)
                    .accessibilityHidden(session.projectPath != viewModel.activeWorkspaceProjectPath)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.setWorkspaceFocusedArea(.terminal)
        }
    }

    @ViewBuilder
    private var gitToolWindowContent: some View {
        if isActiveQuickTerminalSession {
            gitModeEmptyState(
                title: "快速终端暂不支持 Git 模式",
                systemImage: "bolt.horizontal.circle",
                description: "请先打开一个 Git 项目或 worktree，再使用 Git 管理面板。"
            )
        } else if viewModel.activeWorkspaceGitRepositoryContext == nil {
            gitModeEmptyState(
                title: "当前项目不是 Git 仓库",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: "Git 面板只会对当前 active project 所属的 root repository 生效。"
            )
        } else if let gitViewModel = viewModel.activeWorkspaceGitViewModel {
            WorkspaceGitRootView(
                viewModel: gitViewModel,
                onOpenDiff: { file in
                    openGitLogDiffTab(logViewModel: gitViewModel.logViewModel, file: file)
                }
            )
        } else {
            gitModeEmptyState(
                title: "Git 面板尚未就绪",
                systemImage: "tray",
                description: "请重新选择当前项目，或稍后再试。"
            )
        }
    }

    @ViewBuilder
    private func topWorkspaceContent(totalWidth: CGFloat) -> some View {
        if viewModel.workspaceSideToolWindowState.isVisible,
           viewModel.workspaceSideToolWindowState.activeKind == .commit {
            WorkspaceSplitView(
                direction: .horizontal,
                ratio: sideToolWindowSplitRatio(totalWidth: totalWidth),
                onRatioChange: { ratio in
                    let nextWidth = sideToolWindowWidth(for: ratio, totalWidth: totalWidth)
                    viewModel.updateWorkspaceSideToolWindowWidth(nextWidth)
                },
                onEqualize: {
                    viewModel.updateWorkspaceSideToolWindowWidth(WorkspaceSideToolWindowState.defaultWidth)
                }
            ) {
                WorkspaceCommitSideToolWindowHostView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } trailing: {
                terminalModeContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            terminalModeContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func bottomToolWindowHost(totalSize: CGSize) -> some View {
        let totalHeight = totalSize.height
        let totalWidth = totalSize.width
        if viewModel.workspaceBottomToolWindowState.isVisible {
            WorkspaceSplitView(
                direction: .vertical,
                ratio: toolWindowSplitRatio(totalHeight: totalHeight),
                onRatioChange: { ratio in
                    let nextHeight = toolWindowHeight(for: ratio, totalHeight: totalHeight)
                    viewModel.updateWorkspaceBottomToolWindowHeight(nextHeight)
                },
                onEqualize: {
                    viewModel.updateWorkspaceBottomToolWindowHeight(WorkspaceBottomToolWindowState.defaultHeight)
                }
            ) {
                topWorkspaceContent(totalWidth: totalWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } trailing: {
                Group {
                    if viewModel.workspaceBottomToolWindowState.activeKind == .git {
                        gitToolWindowContent
                    } else {
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    if viewModel.workspaceBottomToolWindowState.activeKind == .git {
                        viewModel.setWorkspaceFocusedArea(.bottomToolWindow(.git))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            topWorkspaceContent(totalWidth: totalWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func sideToolWindowSplitRatio(totalWidth: CGFloat) -> Double {
        guard totalWidth > 0 else {
            return 0.5
        }
        let sideWidth = clampedSideToolWindowWidth(
            CGFloat(viewModel.workspaceSideToolWindowState.width),
            totalWidth: totalWidth
        )
        return Double(sideWidth / totalWidth)
    }

    private func sideToolWindowWidth(for ratio: Double, totalWidth: CGFloat) -> Double {
        guard totalWidth > 0 else {
            return viewModel.workspaceSideToolWindowState.width
        }
        let desiredWidth = CGFloat(ratio) * totalWidth
        let clampedWidth = clampedSideToolWindowWidth(desiredWidth, totalWidth: totalWidth)
        return Double(clampedWidth.rounded())
    }

    private func clampedSideToolWindowWidth(_ proposedWidth: CGFloat, totalWidth: CGFloat) -> CGFloat {
        let upperBound = max(220, totalWidth - 10)
        return min(max(220, proposedWidth), upperBound)
    }

    private func toolWindowSplitRatio(totalHeight: CGFloat) -> Double {
        guard totalHeight > 0 else {
            return 1
        }
        let toolWindowHeight = clampedToolWindowHeight(
            CGFloat(viewModel.workspaceBottomToolWindowState.height),
            totalHeight: totalHeight
        )
        return Double((totalHeight - toolWindowHeight) / totalHeight)
    }

    private func toolWindowHeight(for ratio: Double, totalHeight: CGFloat) -> Double {
        guard totalHeight > 0 else {
            return viewModel.workspaceBottomToolWindowState.height
        }
        let leadingHeight = CGFloat(ratio) * totalHeight
        let desiredHeight = totalHeight - leadingHeight
        let clampedHeight = clampedToolWindowHeight(desiredHeight, totalHeight: totalHeight)
        return Double(clampedHeight.rounded())
    }

    private func clampedToolWindowHeight(_ proposedHeight: CGFloat, totalHeight: CGFloat) -> CGFloat {
        let upperBound = max(10, totalHeight - 10)
        return min(max(10, proposedHeight), upperBound)
    }

    private func openGitLogDiffTab(
        logViewModel: WorkspaceGitLogViewModel,
        file: WorkspaceGitCommitFileChange
    ) {
        guard let selectedCommitHash = logViewModel.selectedCommitHash else {
            return
        }

        viewModel.openActiveWorkspaceDiffTab(
            source: .gitLogCommitFile(
                repositoryPath: logViewModel.repositoryContext.repositoryPath,
                commitHash: selectedCommitHash,
                filePath: file.path
            ),
            preferredTitle: "Commit: \(gitLogDiffTitle(for: file))"
        )
    }

    private func gitLogDiffTitle(for file: WorkspaceGitCommitFileChange) -> String {
        let fileName = (file.path as NSString).lastPathComponent
        return fileName.isEmpty ? file.path : fileName
    }

    private func syncTerminalStores() {
        terminalStoreRegistry.syncRetainedProjectPaths(Set(viewModel.openWorkspaceProjectPaths))
    }

    private var isActiveQuickTerminalSession: Bool {
        guard let activePath = viewModel.activeWorkspaceProjectPath else {
            return false
        }
        return viewModel.openWorkspaceSessions.first(where: { $0.projectPath == activePath })?.isQuickTerminal ?? false
    }

    private func warmActiveWorkspace() {
        _ = terminalStoreRegistry.warmActiveWorkspaceSession(
            sessions: viewModel.openWorkspaceSessions,
            activeProjectPath: viewModel.activeWorkspaceProjectPath
        )
    }

    private func refreshCodexDisplayStates() {
        syncCodexDisplayTracking()
        codexDisplayRefreshState = CodexAgentDisplayStateRefresher.refresh(
            viewModel: viewModel,
            runtimeState: codexDisplayRefreshState
        ) { projectPath, paneID in
            terminalStoreRegistry.modelIfLoaded(for: projectPath, paneID: paneID)?.codexDisplaySnapshot()
        }
    }

    private func syncCodexDisplayTracking() {
        let trackedPaneIDsByProjectPath = Dictionary(
            grouping: viewModel.codexDisplayCandidates(),
            by: \.projectPath
        ).mapValues { candidates in
            Set(candidates.map(\.paneID))
        }
        terminalStoreRegistry.syncCodexDisplayTracking(trackedPaneIDsByProjectPath)
    }

    private var workspacePaneSnapshotProvider: WorkspacePaneSnapshotProvider {
        { projectPath, paneID in
            terminalStoreRegistry
                .modelIfLoaded(for: projectPath, paneID: paneID)?
                .snapshotContext()
                .restoreContext
        }
    }

    private var startTerminalSearchAction: (() -> Void)? {
        terminalSearchAction { $0.startSearch() }
    }

    private var searchSelectionAction: (() -> Void)? {
        terminalSearchAction { $0.searchSelection() }
    }

    private var navigateTerminalSearchNextAction: (() -> Void)? {
        terminalSearchAction { $0.navigateSearchNext() }
    }

    private var navigateTerminalSearchPreviousAction: (() -> Void)? {
        terminalSearchAction { $0.navigateSearchPrevious() }
    }

    private var endTerminalSearchAction: (() -> Void)? {
        terminalSearchAction { $0.endSearch() }
    }

    private func terminalSearchAction(
        _ perform: @escaping (GhosttySurfaceHostModel) -> Void
    ) -> (() -> Void)? {
        guard viewModel.workspaceFocusedArea == .terminal else {
            return nil
        }
        guard viewModel.activeWorkspaceController?.selectedPane != nil else {
            return nil
        }
        return {
            guard let model = resolvedActiveTerminalSearchModel() else {
                return
            }
            perform(model)
        }
    }

    private func resolvedActiveTerminalSearchModel() -> GhosttySurfaceHostModel? {
        guard let activeProjectPath = viewModel.activeWorkspaceProjectPath,
              let controller = viewModel.activeWorkspaceController,
              let selectedPane = controller.selectedPane
        else {
            return nil
        }
        return terminalStoreRegistry.store(for: activeProjectPath).model(for: selectedPane)
    }

    private func gitModeEmptyState(title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .foregroundStyle(NativeTheme.textSecondary)
    }
}

private extension GhosttySurfaceHostModel.SnapshotContext {
    var restoreContext: WorkspaceTerminalRestoreContext {
        WorkspaceTerminalRestoreContext(
            workingDirectory: workingDirectory,
            title: title,
            snapshotText: visibleText,
            agentSummary: agentSummary
        )
    }
}

enum WorkspaceSidebarLayoutPolicy {
    static let defaultSidebarWidth: CGFloat = 280
    private static let minSidebarWidth: CGFloat = 220
    private static let maxSidebarWidth: CGFloat = 420
    private static let minWorkspaceContentWidth: CGFloat = 520

    static func sidebarRatio(for width: CGFloat, totalWidth: CGFloat) -> Double {
        guard totalWidth > 0 else {
            return 0.5
        }
        return Double(clampSidebarWidth(width, totalWidth: totalWidth) / totalWidth)
    }

    static func sidebarWidth(for ratio: Double, totalWidth: CGFloat) -> CGFloat {
        guard totalWidth > 0 else {
            return defaultSidebarWidth
        }
        let proposedWidth = totalWidth * CGFloat(ratio)
        return clampSidebarWidth(proposedWidth, totalWidth: totalWidth)
    }

    static func clampSidebarWidth(_ width: CGFloat, totalWidth: CGFloat) -> CGFloat {
        let range = allowedSidebarWidthRange(totalWidth: totalWidth)
        return min(max(width, range.lowerBound), range.upperBound)
    }

    private static func allowedSidebarWidthRange(totalWidth: CGFloat) -> ClosedRange<CGFloat> {
        let lowerBound = min(minSidebarWidth, totalWidth)
        let contentSafeUpperBound = max(totalWidth - minWorkspaceContentWidth, lowerBound)
        let upperBound = min(maxSidebarWidth, contentSafeUpperBound)
        return lowerBound...max(lowerBound, upperBound)
    }
}
