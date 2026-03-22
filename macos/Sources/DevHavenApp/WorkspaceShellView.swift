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
    @StateObject private var terminalStoreRegistry = WorkspaceTerminalStoreRegistry()

    private var worktreeDialogProject: Project? {
        guard let worktreeDialogProjectPath else {
            return nil
        }
        return viewModel.snapshot.projects.first(where: { $0.path == worktreeDialogProjectPath })
    }

    var body: some View {
        HStack(spacing: 0) {
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
            .frame(width: 280)

            workspaceContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NativeTheme.window)
        }
        .background(NativeTheme.window)
        .onAppear {
            syncTerminalStores()
            warmActiveWorkspace()
            WorkspaceLaunchDiagnostics.shared.recordShellMounted(
                activeProjectPath: viewModel.activeWorkspaceProjectPath,
                openSessionCount: viewModel.openWorkspaceSessions.count
            )
        }
        .onChange(of: viewModel.openWorkspaceProjectPaths) { _, _ in
            syncTerminalStores()
            warmActiveWorkspace()
        }
        .onChange(of: viewModel.activeWorkspaceProjectPath) { _, _ in
            warmActiveWorkspace()
        }
        .onChange(of: viewModel.activeWorkspaceLaunchRequest?.paneId) { _, _ in
            warmActiveWorkspace()
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
                    try await viewModel.createWorkspaceWorktree(
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
}

private struct WorkspaceDialogProject: Identifiable {
    let project: Project
    var id: String { project.path }
}
