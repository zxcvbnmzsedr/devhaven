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

private struct WorkspaceAlignmentEditorContext: Identifiable {
    let id: String
    let title: String
    let mode: WorkspaceAlignmentEditorSheetMode
    let initialData: WorkspaceAlignmentEditorFormData
}

private struct WorkspaceAlignmentAddProjectsContext: Identifiable {
    let id: String
    let workspaceID: String
    let workspaceName: String
    let excludedProjectPaths: Set<String>
}

private struct WorkspaceAlignmentDeleteRequest: Identifiable {
    let id: String
    let name: String
}

struct WorkspaceProjectSidebarHostView: View {
    @Bindable var viewModel: NativeAppViewModel
    @StateObject private var sidebarProjectionStore = WorkspaceSidebarProjectionStore()
    @State private var isProjectPickerPresented = false
    @State private var worktreeDialogProjectPath: String?
    @State private var pendingDeleteRequest: WorktreeDeleteRequest?
    @State private var alignmentEditorContext: WorkspaceAlignmentEditorContext?
    @State private var alignmentAddProjectsContext: WorkspaceAlignmentAddProjectsContext?
    @State private var pendingDeleteWorkspaceAlignment: WorkspaceAlignmentDeleteRequest?

    private var worktreeDialogProject: Project? {
        guard let worktreeDialogProjectPath else {
            return nil
        }
        return viewModel.snapshot.projects.first(where: { $0.path == worktreeDialogProjectPath })
    }

    private func openOrActivateProject(_ member: WorkspaceAlignmentMemberProjection) {
        switch member.openTarget {
        case let .project(projectPath):
            if viewModel.openWorkspaceProjectPaths.contains(projectPath) {
                viewModel.activateWorkspaceProject(projectPath)
            } else {
                viewModel.enterWorkspace(projectPath)
            }
        case let .worktree(rootProjectPath, worktreePath):
            if viewModel.openWorkspaceProjectPaths.contains(worktreePath) {
                viewModel.activateWorkspaceProject(worktreePath)
                return
            }
            if !viewModel.openWorkspaceProjectPaths.contains(rootProjectPath) {
                viewModel.enterWorkspace(rootProjectPath)
            }
            viewModel.openWorkspaceWorktree(worktreePath, from: rootProjectPath)
        }
    }

    var body: some View {
        WorkspaceProjectListView(
            groups: sidebarProjectionStore.projection.groups,
            canOpenMoreProjects: !sidebarProjectionStore.projection.availableProjects.isEmpty,
            workspaceAlignmentGroups: sidebarProjectionStore.projection.workspaceAlignmentGroups,
            workspaceAlignmentProjectOptions: sidebarProjectionStore.projection.workspaceAlignmentProjectOptions,
            onSelectProject: viewModel.activateWorkspaceProject,
            onOpenWorkspaceAlignmentProject: openOrActivateProject,
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
            onRequestCreateWorkspaceAlignment: { projectPath in
                presentCreateWorkspaceAlignmentSheet(prefilledProjectPath: projectPath)
            },
            onRequestEditWorkspaceAlignment: presentEditWorkspaceAlignmentSheet,
            onRequestAddProjectsToWorkspaceAlignment: presentAddProjectsSheet,
            onRequestRecheckWorkspaceAlignment: { workspaceID in
                Task {
                    do {
                        try await viewModel.recheckWorkspaceAlignmentGroup(workspaceID)
                    } catch {
                        viewModel.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }
            },
            onRequestApplyWorkspaceAlignment: { workspaceID in
                Task {
                    do {
                        try await viewModel.applyWorkspaceAlignmentGroup(workspaceID)
                    } catch {
                        viewModel.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }
            },
            onRequestDeleteWorkspaceAlignment: { workspaceID in
                if let group = sidebarProjectionStore.projection.workspaceAlignmentGroups.first(where: { $0.id == workspaceID }) {
                    pendingDeleteWorkspaceAlignment = WorkspaceAlignmentDeleteRequest(id: group.id, name: group.definition.name)
                }
            },
            onRequestApplyWorkspaceAlignmentProject: { workspaceID, projectPath in
                Task {
                    do {
                        try await viewModel.applyWorkspaceAlignmentRule(for: projectPath, inWorkspaceAlignmentGroup: workspaceID)
                    } catch {
                        viewModel.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }
            },
            onRequestRemoveWorkspaceAlignmentProject: { workspaceID, projectPath in
                do {
                    try viewModel.removeProject(projectPath, fromWorkspaceAlignmentGroup: workspaceID)
                } catch {
                    viewModel.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            },
            onAddProjectToWorkspaceAlignment: { projectPath, workspaceID in
                Task {
                    do {
                        try await viewModel.addProjects([projectPath], toWorkspaceAlignmentGroup: workspaceID, applyRules: true)
                    } catch {
                        viewModel.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }
            },
            onExit: viewModel.exitWorkspace
        )
        .onAppear {
            syncSidebarProjection()
            Task {
                await refreshWorkspaceAlignmentGroupsIfNeeded()
            }
        }
        .onChange(of: viewModel.workspaceSidebarProjectionRevision) { _, _ in
            syncSidebarProjection()
        }
        .focusedSceneValue(\.openWorkspaceProjectPickerAction, openWorkspaceProjectPickerAction)
        .sheet(isPresented: $isProjectPickerPresented) {
            WorkspaceProjectPickerView(
                projects: sidebarProjectionStore.projection.availableProjects,
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
        .sheet(item: $alignmentEditorContext) { context in
            WorkspaceAlignmentEditorSheet(
                title: context.title,
                mode: context.mode,
                availableProjects: sidebarProjectionStore.projection.workspaceAlignmentProjectOptions,
                initialData: context.initialData,
                onSubmit: { formData in
                    submitWorkspaceAlignmentEditor(context: context, formData: formData)
                },
                onClose: { alignmentEditorContext = nil }
            )
            .preferredColorScheme(.dark)
        }
        .sheet(item: $alignmentAddProjectsContext) { context in
            WorkspaceAlignmentAddProjectsSheet(
                workspaceName: context.workspaceName,
                availableProjects: sidebarProjectionStore.projection.workspaceAlignmentProjectOptions.filter {
                    !context.excludedProjectPaths.contains($0.path)
                },
                onSubmit: { selectedPaths, applyRules in
                    submitAddProjects(to: context.workspaceID, selectedPaths: selectedPaths, applyRules: applyRules)
                },
                onClose: { alignmentAddProjectsContext = nil }
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
        .alert(
            "删除工作区",
            isPresented: Binding(
                get: { pendingDeleteWorkspaceAlignment != nil },
                set: { if !$0 { pendingDeleteWorkspaceAlignment = nil } }
            ),
            presenting: pendingDeleteWorkspaceAlignment
        ) { request in
            Button("删除工作区", role: .destructive) {
                do {
                    try viewModel.deleteWorkspaceAlignmentGroup(request.id)
                } catch {
                    viewModel.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
                pendingDeleteWorkspaceAlignment = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteWorkspaceAlignment = nil
            }
        } message: { request in
            Text("将删除工作区「\(request.name)」。不会删除项目本体，也不会删除已有仓库或 worktree。")
        }
    }

    private var openWorkspaceProjectPickerAction: (() -> Void)? {
        guard !sidebarProjectionStore.projection.availableProjects.isEmpty else {
            return nil
        }
        return {
            isProjectPickerPresented = true
        }
    }

    private func syncSidebarProjection() {
        sidebarProjectionStore.sync(from: viewModel)
    }

    private func presentCreateWorkspaceAlignmentSheet(prefilledProjectPath: String?) {
        var selectedProjectPaths = Set<String>()
        if let prefilledProjectPath {
            selectedProjectPaths.insert(prefilledProjectPath)
        }
        alignmentEditorContext = WorkspaceAlignmentEditorContext(
            id: UUID().uuidString,
            title: "新建工作区",
            mode: .create,
            initialData: WorkspaceAlignmentEditorFormData(
                name: "",
                targetBranch: "",
                baseBranchMode: .autoDetect,
                specifiedBaseBranch: "",
                selectedProjectPaths: selectedProjectPaths,
                applyRulesAfterSave: prefilledProjectPath != nil
            )
        )
    }

    private func presentEditWorkspaceAlignmentSheet(_ workspaceID: String) {
        guard let group = sidebarProjectionStore.projection.workspaceAlignmentGroups.first(where: { $0.id == workspaceID }) else {
            return
        }
        alignmentEditorContext = WorkspaceAlignmentEditorContext(
            id: group.id,
            title: "编辑工作区",
            mode: .edit(currentProjectPaths: group.definition.projectPaths),
            initialData: WorkspaceAlignmentEditorFormData(
                name: group.definition.name,
                targetBranch: group.definition.targetBranch,
                baseBranchMode: group.definition.baseBranchMode,
                specifiedBaseBranch: group.definition.specifiedBaseBranch ?? "",
                selectedProjectPaths: Set(group.definition.projectPaths),
                applyRulesAfterSave: false
            )
        )
    }

    private func presentAddProjectsSheet(_ workspaceID: String) {
        guard let group = sidebarProjectionStore.projection.workspaceAlignmentGroups.first(where: { $0.id == workspaceID }) else {
            return
        }
        alignmentAddProjectsContext = WorkspaceAlignmentAddProjectsContext(
            id: group.id,
            workspaceID: group.id,
            workspaceName: group.definition.name,
            excludedProjectPaths: Set(group.definition.projectPaths)
        )
    }

    private func submitWorkspaceAlignmentEditor(
        context: WorkspaceAlignmentEditorContext,
        formData: WorkspaceAlignmentEditorFormData
    ) {
        let shouldDismissImmediately = formData.applyRulesAfterSave
        if shouldDismissImmediately {
            alignmentEditorContext = nil
        }
        Task {
            do {
                switch context.mode {
                case .create:
                    try await viewModel.createWorkspaceAlignmentGroup(
                        name: formData.name,
                        targetBranch: formData.targetBranch,
                        baseBranchMode: formData.baseBranchMode,
                        specifiedBaseBranch: formData.specifiedBaseBranch,
                        projectPaths: Array(formData.selectedProjectPaths),
                        applyRules: formData.applyRulesAfterSave
                    )
                case .edit:
                    try await viewModel.updateWorkspaceAlignmentGroup(
                        id: context.id,
                        name: formData.name,
                        targetBranch: formData.targetBranch,
                        baseBranchMode: formData.baseBranchMode,
                        specifiedBaseBranch: formData.specifiedBaseBranch,
                        applyRules: formData.applyRulesAfterSave
                    )
                }
                if !shouldDismissImmediately {
                    alignmentEditorContext = nil
                }
            } catch {
                viewModel.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func submitAddProjects(
        to workspaceID: String,
        selectedPaths: Set<String>,
        applyRules: Bool
    ) {
        if applyRules {
            alignmentAddProjectsContext = nil
        }
        Task {
            do {
                try await viewModel.addProjects(Array(selectedPaths), toWorkspaceAlignmentGroup: workspaceID, applyRules: applyRules)
                if !applyRules {
                    alignmentAddProjectsContext = nil
                }
            } catch {
                viewModel.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func refreshWorkspaceAlignmentGroupsIfNeeded() async {
        for group in sidebarProjectionStore.projection.workspaceAlignmentGroups where group.members.contains(where: { $0.status == .checking }) {
            do {
                try await viewModel.recheckWorkspaceAlignmentGroup(group.id)
            } catch {
                viewModel.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
