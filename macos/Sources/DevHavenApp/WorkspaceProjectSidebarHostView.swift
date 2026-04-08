import SwiftUI
import DevHavenCore

private struct WorktreeDeleteRequest: Identifiable, Equatable {
    let presentation: WorkspaceWorktreeDeletePresentation

    var rootProjectPath: String { presentation.rootProjectPath }
    var worktreePath: String { presentation.worktreePath }
    var id: String { presentation.id }
}

private struct WorkspaceDialogProject: Identifiable {
    let project: Project
    var id: String { project.path }
}

private struct DeferredWorktreeCreateRequest: Equatable {
    let rootProjectPath: String
    let branch: String
    let createBranch: Bool
    let baseBranch: String?
    let autoOpen: Bool
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
    let initialSelectedProjectPaths: Set<String>
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
    @State private var deferredWorktreeCreateRequest: DeferredWorktreeCreateRequest?
    @State private var pendingDeleteRequest: WorktreeDeleteRequest?
    @State private var alignmentEditorContext: WorkspaceAlignmentEditorContext?
    @State private var alignmentEditorIsSubmitting = false
    @State private var alignmentEditorErrorMessage: String?
    @State private var alignmentAddProjectsContext: WorkspaceAlignmentAddProjectsContext?
    @State private var alignmentAddProjectsIsSubmitting = false
    @State private var alignmentAddProjectsErrorMessage: String?
    @State private var pendingDeleteWorkspaceAlignment: WorkspaceAlignmentDeleteRequest?

    private var worktreeDialogProject: Project? {
        guard let worktreeDialogProjectPath else {
            return nil
        }
        return viewModel.snapshot.projects.first(where: { $0.path == worktreeDialogProjectPath })
    }

    private func openOrActivateProject(_ member: WorkspaceAlignmentMemberProjection) {
        if member.openTarget.path.isEmpty {
            return
        }
        viewModel.openWorkspaceAlignmentMember(member)
    }

    var body: some View {
        withDeleteWorkspaceAlert(on: withDeleteWorktreeConfirmation(on: contentWithSheets))
    }

    private var contentWithSheets: some View {
        WorkspaceProjectListView(
            groups: sidebarProjectionStore.projection.groups,
            canOpenMoreProjects: !sidebarProjectionStore.projection.availableProjects.isEmpty,
            workspaceAlignmentGroups: sidebarProjectionStore.projection.workspaceAlignmentGroups,
            workspaceAlignmentProjectOptions: sidebarProjectionStore.projection.workspaceAlignmentProjectOptions,
            onSelectProject: viewModel.activateWorkspaceSidebarProject,
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
                guard let presentation = viewModel.workspaceWorktreeDeletePresentation(
                    for: worktreePath,
                    from: rootProjectPath
                ) else {
                    return
                }
                pendingDeleteRequest = WorktreeDeleteRequest(presentation: presentation)
            },
            onFocusNotification: viewModel.focusWorkspaceNotification,
            onCloseProject: viewModel.closeWorkspaceProject,
            onMoveProjectGroup: { sourceID, targetID, insertAfter in
                viewModel.moveWorkspaceSidebarGroup(
                    sourceID,
                    relativeTo: targetID,
                    insertAfter: insertAfter
                )
            },
            onRequestCreateWorkspaceAlignment: { projectPath in
                presentCreateWorkspaceAlignmentSheet(prefilledProjectPath: projectPath)
            },
            onOpenWorkspaceAlignment: { workspaceID in
                do {
                    try viewModel.enterWorkspaceAlignmentGroup(workspaceID)
                } catch {
                    viewModel.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            },
            onRequestEditWorkspaceAlignment: presentEditWorkspaceAlignmentSheet,
            onRequestAddProjectsToWorkspaceAlignment: { workspaceID in
                presentAddProjectsSheet(workspaceID)
            },
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
            onMoveWorkspaceAlignmentGroup: { sourceID, targetID, insertAfter in
                do {
                    try viewModel.moveWorkspaceAlignmentGroup(
                        sourceID,
                        relativeTo: targetID,
                        insertAfter: insertAfter
                    )
                } catch {
                    viewModel.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
                presentAddProjectsSheet(workspaceID, preselectedProjectPaths: [projectPath])
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
                loadBaseBranchReferences: { try await viewModel.listWorkspaceBaseBranchReferences(for: $0) },
                loadWorktrees: { try await viewModel.listProjectWorktrees(for: $0) },
                managedPathPreview: { try viewModel.managedWorktreePathPreview(for: $0, branch: $1) },
                onCreateWorktree: { branch, createBranch, baseBranch, autoOpen in
                    try viewModel.validateStartCreateWorkspaceWorktree(
                        from: dialogProject.project.path,
                        branch: branch,
                        createBranch: createBranch,
                        baseBranch: baseBranch
                    )
                    deferredWorktreeCreateRequest = DeferredWorktreeCreateRequest(
                        rootProjectPath: dialogProject.project.path,
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
        .onChange(of: worktreeDialogProjectPath) { _, newValue in
            guard newValue == nil, let request = deferredWorktreeCreateRequest else {
                return
            }
            deferredWorktreeCreateRequest = nil
            Task { @MainActor in
                do {
                    // 先关闭 `.sheet`，再启动创建任务；否则全局 overlay 会被 sheet 遮住，用户看不到进度面板。
                    try viewModel.startCreateWorkspaceWorktree(
                        from: request.rootProjectPath,
                        branch: request.branch,
                        createBranch: request.createBranch,
                        baseBranch: request.baseBranch,
                        autoOpen: request.autoOpen
                    )
                } catch {
                    viewModel.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
        .sheet(item: $alignmentEditorContext) { context in
            WorkspaceAlignmentEditorSheet(
                title: context.title,
                mode: context.mode,
                availableProjects: sidebarProjectionStore.projection.workspaceAlignmentProjectOptions,
                loadBaseBranchReferences: { try await viewModel.listWorkspaceBaseBranchReferences(for: $0) },
                initialData: context.initialData,
                errorMessage: alignmentEditorErrorMessage,
                isSubmitting: alignmentEditorIsSubmitting,
                onSubmit: { formData in
                    submitWorkspaceAlignmentEditor(context: context, formData: formData)
                },
                onClose: dismissAlignmentEditor
            )
            .preferredColorScheme(.dark)
        }
        .sheet(item: $alignmentAddProjectsContext) { context in
            WorkspaceAlignmentAddProjectsSheet(
                workspaceName: context.workspaceName,
                availableProjects: sidebarProjectionStore.projection.workspaceAlignmentProjectOptions.filter {
                    !context.excludedProjectPaths.contains($0.path)
                },
                loadBaseBranchReferences: { try await viewModel.listWorkspaceBaseBranchReferences(for: $0) },
                initialMemberTemplate: workspaceAlignmentInitialAddTemplate(for: context.workspaceID),
                initialSelectedProjectPaths: context.initialSelectedProjectPaths,
                errorMessage: alignmentAddProjectsErrorMessage,
                isSubmitting: alignmentAddProjectsIsSubmitting,
                onSubmit: { members, applyRules in
                    submitAddProjects(to: context.workspaceID, members: members, applyRules: applyRules)
                },
                onClose: dismissAlignmentAddProjects
            )
            .preferredColorScheme(.dark)
        }
    }

    private func withDeleteWorktreeConfirmation<Content: View>(on content: Content) -> some View {
        content.confirmationDialog(
            pendingDeleteRequest?.presentation.title ?? "删除 worktree",
            isPresented: Binding(
                get: { pendingDeleteRequest != nil },
                set: { if !$0 { pendingDeleteRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(pendingDeleteRequest?.presentation.actionTitle ?? "删除", role: .destructive) {
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
            Text(pendingDeleteWorktreeMessage)
        }
    }

    private func withDeleteWorkspaceAlert<Content: View>(on content: Content) -> some View {
        content.alert(
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

    private var pendingDeleteWorktreeMessage: String {
        pendingDeleteRequest?.presentation.message ?? ""
    }

    private func syncSidebarProjection() {
        sidebarProjectionStore.sync(from: viewModel)
    }

    private func presentCreateWorkspaceAlignmentSheet(prefilledProjectPath: String?) {
        alignmentEditorIsSubmitting = false
        alignmentEditorErrorMessage = nil
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
                members: selectedProjectPaths
                    .map { projectPath in
                        WorkspaceAlignmentMemberFormEntry(
                            projectPath: projectPath,
                            alias: workspaceAlignmentDefaultAlias(for: projectPath),
                            targetBranch: "",
                            baseBranchMode: .specified,
                            specifiedBaseBranch: ""
                        )
                    },
                applyRulesAfterSave: prefilledProjectPath != nil
            )
        )
    }

    private func presentEditWorkspaceAlignmentSheet(_ workspaceID: String) {
        guard let group = sidebarProjectionStore.projection.workspaceAlignmentGroups.first(where: { $0.id == workspaceID }) else {
            return
        }
        alignmentEditorIsSubmitting = false
        alignmentEditorErrorMessage = nil
        alignmentEditorContext = WorkspaceAlignmentEditorContext(
            id: group.id,
            title: "编辑工作区",
            mode: .edit,
            initialData: WorkspaceAlignmentEditorFormData(
                name: group.definition.name,
                members: group.definition.effectiveMembers.map { member in
                    WorkspaceAlignmentMemberFormEntry(
                        projectPath: member.projectPath,
                        alias: group.definition.memberAliases[member.projectPath] ?? workspaceAlignmentDefaultAlias(for: member.projectPath),
                        targetBranch: member.targetBranch,
                        baseBranchMode: .specified,
                        specifiedBaseBranch: member.specifiedBaseBranch ?? ""
                    )
                },
                applyRulesAfterSave: false
            )
        )
    }

    private func presentAddProjectsSheet(
        _ workspaceID: String,
        preselectedProjectPaths: Set<String> = []
    ) {
        guard let group = sidebarProjectionStore.projection.workspaceAlignmentGroups.first(where: { $0.id == workspaceID }) else {
            return
        }
        alignmentAddProjectsIsSubmitting = false
        alignmentAddProjectsErrorMessage = nil
        alignmentAddProjectsContext = WorkspaceAlignmentAddProjectsContext(
            id: group.id,
            workspaceID: group.id,
            workspaceName: group.definition.name,
            excludedProjectPaths: Set(group.definition.projectPaths),
            initialSelectedProjectPaths: preselectedProjectPaths
        )
    }

    private func dismissAlignmentEditor() {
        alignmentEditorContext = nil
        alignmentEditorIsSubmitting = false
        alignmentEditorErrorMessage = nil
    }

    private func dismissAlignmentAddProjects() {
        alignmentAddProjectsContext = nil
        alignmentAddProjectsIsSubmitting = false
        alignmentAddProjectsErrorMessage = nil
    }

    private func submitWorkspaceAlignmentEditor(
        context: WorkspaceAlignmentEditorContext,
        formData: WorkspaceAlignmentEditorFormData
    ) {
        alignmentEditorIsSubmitting = true
        alignmentEditorErrorMessage = nil
        Task {
            do {
                switch context.mode {
                case .create:
                    try await viewModel.createWorkspaceAlignmentGroup(
                        name: formData.name,
                        members: formData.members.map(workspaceAlignmentMemberDefinition(from:)),
                        memberAliases: workspaceAlignmentMemberAliases(from: formData.members),
                        applyRules: formData.applyRulesAfterSave
                    )
                case .edit:
                    try await viewModel.updateWorkspaceAlignmentGroup(
                        id: context.id,
                        name: formData.name,
                        members: formData.members.map(workspaceAlignmentMemberDefinition(from:)),
                        memberAliases: workspaceAlignmentMemberAliases(from: formData.members),
                        applyRules: formData.applyRulesAfterSave
                    )
                }
                dismissAlignmentEditor()
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                alignmentEditorIsSubmitting = false
                alignmentEditorErrorMessage = message
                viewModel.errorMessage = message
            }
        }
    }

    private func submitAddProjects(
        to workspaceID: String,
        members: [WorkspaceAlignmentMemberFormEntry],
        applyRules: Bool
    ) {
        alignmentAddProjectsIsSubmitting = true
        alignmentAddProjectsErrorMessage = nil
        Task {
            do {
                try await viewModel.addWorkspaceAlignmentMembers(
                    members.map(workspaceAlignmentMemberDefinition(from:)),
                    memberAliases: workspaceAlignmentMemberAliases(from: members),
                    toWorkspaceAlignmentGroup: workspaceID,
                    applyRules: applyRules
                )
                dismissAlignmentAddProjects()
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                alignmentAddProjectsIsSubmitting = false
                alignmentAddProjectsErrorMessage = message
                viewModel.errorMessage = message
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

    private func workspaceAlignmentProjectName(for path: String) -> String {
        sidebarProjectionStore.projection.workspaceAlignmentProjectOptions
            .first(where: { $0.path == path })?.name
        ?? {
            let projectName = (path as NSString).lastPathComponent
            return projectName.isEmpty ? path : projectName
        }()
    }

    private func workspaceAlignmentDefaultAlias(for path: String) -> String {
        sanitizeWorkspaceAlias(workspaceAlignmentProjectName(for: path))
    }

    private func workspaceAlignmentMemberDefinition(
        from entry: WorkspaceAlignmentMemberFormEntry
    ) -> WorkspaceAlignmentMemberDefinition {
        WorkspaceAlignmentMemberDefinition(
            projectPath: entry.projectPath,
            targetBranch: entry.targetBranch,
            baseBranchMode: .specified,
            specifiedBaseBranch: entry.specifiedBaseBranch
        )
    }

    private func workspaceAlignmentMemberAliases(
        from members: [WorkspaceAlignmentMemberFormEntry]
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: members.map { ($0.projectPath, sanitizeWorkspaceAlias($0.alias)) })
    }

    private func workspaceAlignmentInitialAddTemplate(for workspaceID: String) -> WorkspaceAlignmentMemberFormEntry? {
        guard let group = sidebarProjectionStore.projection.workspaceAlignmentGroups.first(where: { $0.id == workspaceID }),
              let firstMember = group.definition.effectiveMembers.first else {
            return nil
        }
        return WorkspaceAlignmentMemberFormEntry(
            projectPath: "",
            alias: "",
            targetBranch: firstMember.targetBranch,
            baseBranchMode: .specified,
            specifiedBaseBranch: firstMember.specifiedBaseBranch ?? ""
        )
    }
}
