import SwiftUI
import DevHavenCore

private struct WorktreeDeleteRequest: Identifiable, Equatable {
    let rootProjectPath: String
    let worktreePath: String

    var id: String { "\(rootProjectPath)|\(worktreePath)" }
}

struct WorkspaceShellView: View {
    @Bindable var viewModel: NativeAppViewModel
    @State private var isProjectPickerPresented = false
    @State private var worktreeDialogProjectPath: String?
    @State private var pendingDeleteRequest: WorktreeDeleteRequest?
    @State private var sidebarWidth: CGFloat = WorkspaceSidebarLayoutPolicy.defaultSidebarWidth
    @State private var codexDisplayRefreshState = CodexAgentDisplayStateRefresher.RuntimeState()
    @StateObject private var terminalStoreRegistry = WorkspaceTerminalStoreRegistry()
    private let codexDisplayRefreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var worktreeDialogProject: Project? {
        guard let worktreeDialogProjectPath else {
            return nil
        }
        return viewModel.snapshot.projects.first(where: { $0.path == worktreeDialogProjectPath })
    }

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            WorkspaceSplitView(
                direction: .horizontal,
                ratio: WorkspaceSidebarLayoutPolicy.sidebarRatio(
                    for: sidebarWidth,
                    totalWidth: totalWidth
                ),
                onRatioChange: { ratio in
                    sidebarWidth = WorkspaceSidebarLayoutPolicy.sidebarWidth(
                        for: ratio,
                        totalWidth: totalWidth
                    )
                },
                onRatioChangeEnded: { ratio in
                    let committedWidth = WorkspaceSidebarLayoutPolicy.sidebarWidth(
                        for: ratio,
                        totalWidth: totalWidth
                    )
                    sidebarWidth = committedWidth
                    persistSidebarWidth(committedWidth)
                },
                onEqualize: {
                    sidebarWidth = WorkspaceSidebarLayoutPolicy.defaultSidebarWidth
                    persistSidebarWidth(WorkspaceSidebarLayoutPolicy.defaultSidebarWidth)
                }
            ) {
                WorkspaceProjectListView(
                    groups: viewModel.workspaceSidebarGroups,
                    canOpenMoreProjects: !viewModel.availableWorkspaceProjects.isEmpty,
                    onSelectProject: viewModel.activateWorkspaceProject,
                    onOpenProjectPicker: { isProjectPickerPresented = true },
                    onRequestCreateWorktree: { projectPath in
                        worktreeDialogProjectPath = projectPath
                    },
                    onRefreshWorktrees: { projectPath in
                        Task {
                            do {
                                try await viewModel.refreshProjectWorktrees(projectPath)
                            } catch {
                                viewModel.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            }
                        }
                    },
                    onOpenWorktree: { rootProjectPath, worktreePath in
                        viewModel.openWorkspaceWorktree(worktreePath, from: rootProjectPath)
                    },
                    onRetryWorktree: { rootProjectPath, worktreePath in
                        Task {
                            do {
                                try await viewModel.retryWorkspaceWorktree(worktreePath, from: rootProjectPath)
                            } catch {
                                viewModel.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            }
                        }
                    },
                    onRequestDeleteWorktree: { rootProjectPath, worktreePath in
                        pendingDeleteRequest = WorktreeDeleteRequest(rootProjectPath: rootProjectPath, worktreePath: worktreePath)
                    },
                    onFocusNotification: viewModel.focusWorkspaceNotification,
                    onCloseProject: viewModel.closeWorkspaceProject,
                    onExit: viewModel.exitWorkspace
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } trailing: {
                workspaceContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NativeTheme.window)
            }
            .onAppear {
                syncSidebarWidth(totalWidth: totalWidth)
            }
            .onChange(of: viewModel.workspaceSidebarWidth) { _, _ in
                syncSidebarWidth(totalWidth: totalWidth)
            }
            .onChange(of: totalWidth) { _, _ in
                syncSidebarWidth(totalWidth: totalWidth)
            }
        }
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
            refreshCodexDisplayStates()
        }
        .onChange(of: viewModel.activeWorkspaceProjectPath) { _, _ in
            warmActiveWorkspace()
            refreshCodexDisplayStates()
        }
        .onChange(of: viewModel.activeWorkspaceLaunchRequest?.paneId) { _, _ in
            warmActiveWorkspace()
            refreshCodexDisplayStates()
        }
        .sheet(isPresented: $isProjectPickerPresented) {
            WorkspaceProjectPickerView(
                projects: viewModel.availableWorkspaceProjects,
                onOpenProject: { path in
                    viewModel.enterWorkspace(path)
                    isProjectPickerPresented = false
                },
                onClose: { isProjectPickerPresented = false }
            )
            .preferredColorScheme(.dark)
        }
        .sheet(item: Binding(
            get: {
                worktreeDialogProject.flatMap { WorkspaceDialogProject(project: $0) }
            },
            set: { newValue in
                worktreeDialogProjectPath = newValue?.project.path
            }
        )) { dialogProject in
            WorkspaceWorktreeDialogView(
                sourceProject: dialogProject.project,
                loadBranches: { try await viewModel.listWorkspaceBranches(for: $0) },
                loadWorktrees: { try await viewModel.listProjectWorktrees(for: $0) },
                managedPathPreview: { try viewModel.managedWorktreePathPreview(for: $0, branch: $1) },
                onCreateWorktree: { branch, createBranch, baseBranch, autoOpen in
                    try viewModel.startCreateWorkspaceWorktree(
                        from: dialogProject.project.path,
                        branch: branch,
                        createBranch: createBranch,
                        baseBranch: baseBranch,
                        autoOpen: autoOpen
                    )
                },
                onAddExistingWorktree: { worktreePath, branch, autoOpen in
                    try viewModel.addExistingWorkspaceWorktree(
                        from: dialogProject.project.path,
                        worktreePath: worktreePath,
                        branch: branch,
                        autoOpen: autoOpen
                    )
                },
                onClose: { worktreeDialogProjectPath = nil }
            )
            .preferredColorScheme(.dark)
        }
        .confirmationDialog(
            "删除 worktree",
            isPresented: Binding(
                get: { pendingDeleteRequest != nil },
                set: { if !$0 { pendingDeleteRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let pendingDeleteRequest else {
                    return
                }
                Task {
                    do {
                        try await viewModel.deleteWorkspaceWorktree(
                            pendingDeleteRequest.worktreePath,
                            from: pendingDeleteRequest.rootProjectPath
                        )
                    } catch {
                        viewModel.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                    self.pendingDeleteRequest = nil
                }
            }
            Button("取消", role: .cancel) {
                pendingDeleteRequest = nil
            }
        } message: {
            if let pendingDeleteRequest {
                Text("将删除 \(pendingDeleteRequest.worktreePath)，并丢弃其中未提交修改与未跟踪文件。若该 worktree 由 DevHaven 创建，还会尝试删除对应本地分支。")
            }
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
        }
    }

    private func syncTerminalStores() {
        terminalStoreRegistry.syncRetainedProjectPaths(Set(viewModel.openWorkspaceProjectPaths))
    }

    private func warmActiveWorkspace() {
        _ = terminalStoreRegistry.warmActiveWorkspaceSession(
            sessions: viewModel.openWorkspaceSessions,
            activeProjectPath: viewModel.activeWorkspaceProjectPath
        )
    }

    private func syncSidebarWidth(totalWidth: CGFloat) {
        sidebarWidth = WorkspaceSidebarLayoutPolicy.clampSidebarWidth(
            CGFloat(viewModel.workspaceSidebarWidth),
            totalWidth: totalWidth
        )
    }

    private func persistSidebarWidth(_ width: CGFloat) {
        let persistedWidth = Double(width.rounded())
        viewModel.updateWorkspaceSidebarWidth(persistedWidth)
    }

    private func refreshCodexDisplayStates() {
        codexDisplayRefreshState = CodexAgentDisplayStateRefresher.refresh(
            viewModel: viewModel,
            runtimeState: codexDisplayRefreshState
        ) { projectPath, paneID in
            terminalStoreRegistry.modelIfLoaded(for: projectPath, paneID: paneID)?.currentVisibleText()
        }
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

private struct WorkspaceDialogProject: Identifiable {
    let project: Project
    var id: String { project.path }
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
