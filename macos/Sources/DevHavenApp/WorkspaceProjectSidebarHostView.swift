import SwiftUI
import DevHavenCore

private struct WorktreeDeleteRequest: Identifiable, Equatable {
    let rootProjectPath: String
    let worktreePath: String

    var id: String { "\(rootProjectPath)|\(worktreePath)" }
}

private struct WorkspaceDialogProject: Identifiable {
    let project: Project
    var id: String { project.path }
}

struct WorkspaceProjectSidebarHostView: View {
    @Bindable var viewModel: NativeAppViewModel
    @State private var isProjectPickerPresented = false
    @State private var worktreeDialogProjectPath: String?
    @State private var pendingDeleteRequest: WorktreeDeleteRequest?

    private var worktreeDialogProject: Project? {
        guard let worktreeDialogProjectPath else {
            return nil
        }
        return viewModel.snapshot.projects.first(where: { $0.path == worktreeDialogProjectPath })
    }

    var body: some View {
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
        .focusedSceneValue(\.openWorkspaceProjectPickerAction, openWorkspaceProjectPickerAction)
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

    private var openWorkspaceProjectPickerAction: (() -> Void)? {
        guard !viewModel.availableWorkspaceProjects.isEmpty else {
            return nil
        }
        return {
            isProjectPickerPresented = true
        }
    }
}
