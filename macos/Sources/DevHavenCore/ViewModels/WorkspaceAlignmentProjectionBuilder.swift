import Foundation

@MainActor
final class WorkspaceAlignmentProjectionBuilder {
    private let normalizePath: @MainActor (String) -> String
    private let activeProjectPath: @MainActor () -> String?
    private let activeWorkspaceRootGroupID: @MainActor () -> String?
    private let activeWorkspaceOwnedGroupID: @MainActor () -> String?
    private let projectsByNormalizedPath: @MainActor () -> [String: Project]
    private let currentBranchByProjectPath: @MainActor () -> [String: String]
    private let aliasesForGroup: @MainActor (WorkspaceAlignmentGroupDefinition, [String: Project]) -> [String: String]
    private let statusForMember: @MainActor (String, String) -> WorkspaceAlignmentMemberStatus?

    init(
        normalizePath: @escaping @MainActor (String) -> String,
        activeProjectPath: @escaping @MainActor () -> String?,
        activeWorkspaceRootGroupID: @escaping @MainActor () -> String?,
        activeWorkspaceOwnedGroupID: @escaping @MainActor () -> String?,
        projectsByNormalizedPath: @escaping @MainActor () -> [String: Project],
        currentBranchByProjectPath: @escaping @MainActor () -> [String: String],
        aliasesForGroup: @escaping @MainActor (WorkspaceAlignmentGroupDefinition, [String: Project]) -> [String: String],
        statusForMember: @escaping @MainActor (String, String) -> WorkspaceAlignmentMemberStatus?
    ) {
        self.normalizePath = normalizePath
        self.activeProjectPath = activeProjectPath
        self.activeWorkspaceRootGroupID = activeWorkspaceRootGroupID
        self.activeWorkspaceOwnedGroupID = activeWorkspaceOwnedGroupID
        self.projectsByNormalizedPath = projectsByNormalizedPath
        self.currentBranchByProjectPath = currentBranchByProjectPath
        self.aliasesForGroup = aliasesForGroup
        self.statusForMember = statusForMember
    }

    func groups(
        definitions: [WorkspaceAlignmentGroupDefinition]
    ) -> [WorkspaceAlignmentGroupProjection] {
        let projectsByNormalizedPath = projectsByNormalizedPath()
        let currentBranchByProjectPath = currentBranchByProjectPath()
        let normalizedActiveProjectPath = activeProjectPath().map(normalizePath)
        let activeWorkspaceRootGroupID = activeWorkspaceRootGroupID()
        let activeWorkspaceOwnedGroupID = activeWorkspaceOwnedGroupID()

        return definitions.map { definition in
            let aliasByProjectPath = aliasesForGroup(definition, projectsByNormalizedPath)
            let members = definition.effectiveMembers.map { memberDefinition in
                let normalizedProjectPath = normalizePath(memberDefinition.projectPath)
                let status = statusForMember(definition.id, normalizedProjectPath) ?? .checking
                let openTarget = openTarget(
                    for: normalizedProjectPath,
                    targetBranch: memberDefinition.targetBranch,
                    status: status,
                    projectsByNormalizedPath: projectsByNormalizedPath,
                    currentBranchByProjectPath: currentBranchByProjectPath
                )
                let isActive = isActiveMember(
                    groupID: definition.id,
                    memberProjectPath: normalizedProjectPath,
                    status: status,
                    openTarget: openTarget,
                    normalizedActiveProjectPath: normalizedActiveProjectPath,
                    activeWorkspaceOwnedGroupID: activeWorkspaceOwnedGroupID
                )
                return WorkspaceAlignmentMemberProjection(
                    groupID: definition.id,
                    projectPath: normalizedProjectPath,
                    alias: aliasByProjectPath[normalizedProjectPath] ?? workspaceAlignmentProjectionLastPathComponent(normalizedProjectPath),
                    projectName: projectsByNormalizedPath[normalizedProjectPath]?.name
                        ?? workspaceAlignmentProjectionLastPathComponent(memberDefinition.projectPath),
                    targetBranch: memberDefinition.targetBranch,
                    branchLabel: branchLabel(
                        for: normalizedProjectPath,
                        targetBranch: memberDefinition.targetBranch,
                        status: status,
                        openTarget: openTarget,
                        projectsByNormalizedPath: projectsByNormalizedPath,
                        currentBranchByProjectPath: currentBranchByProjectPath
                    ),
                    status: status,
                    openTarget: openTarget,
                    isActive: isActive
                )
            }
            let isActive = activeWorkspaceRootGroupID == definition.id ||
                activeWorkspaceOwnedGroupID == definition.id ||
                members.contains(where: \.isActive)
            return WorkspaceAlignmentGroupProjection(
                definition: definition,
                members: members,
                isActive: isActive
            )
        }
    }

    private func openTarget(
        for projectPath: String,
        targetBranch: String,
        status: WorkspaceAlignmentMemberStatus,
        projectsByNormalizedPath: [String: Project],
        currentBranchByProjectPath: [String: String]
    ) -> WorkspaceAlignmentOpenTarget {
        guard case .aligned = status else {
            return .project(projectPath: projectPath)
        }

        let normalizedProjectPath = normalizePath(projectPath)
        guard let rootProject = projectsByNormalizedPath[normalizedProjectPath] else {
            return .project(projectPath: projectPath)
        }

        let currentBranch = currentBranchByProjectPath[rootProject.path]
            ?? currentBranchByProjectPath[normalizedProjectPath]
        if currentBranch == targetBranch {
            return .project(projectPath: rootProject.path)
        }

        if let worktree = rootProject.worktrees.first(where: { $0.branch == targetBranch }) {
            return .worktree(rootProjectPath: rootProject.path, worktreePath: worktree.path)
        }

        return .project(projectPath: rootProject.path)
    }

    private func branchLabel(
        for projectPath: String,
        targetBranch: String,
        status: WorkspaceAlignmentMemberStatus,
        openTarget: WorkspaceAlignmentOpenTarget,
        projectsByNormalizedPath: [String: Project],
        currentBranchByProjectPath: [String: String]
    ) -> String {
        switch status {
        case let .currentBranch(branch):
            return branch
        case .aligned, .branchMissing, .worktreeMissing, .checking, .applying, .applyFailed, .checkFailed:
            break
        }

        let normalizedProjectPath = normalizePath(projectPath)
        if let rootProject = projectsByNormalizedPath[normalizedProjectPath] {
            switch openTarget {
            case .project:
                if let currentBranch = currentBranchByProjectPath[rootProject.path] {
                    return currentBranch
                }
            case let .worktree(_, worktreePath):
                if let worktree = rootProject.worktrees.first(where: {
                    normalizePath($0.path) == normalizePath(worktreePath)
                }) {
                    return worktree.branch
                }
            }
        }

        return targetBranch
    }

    private func isActiveMember(
        groupID: String,
        memberProjectPath: String,
        status: WorkspaceAlignmentMemberStatus,
        openTarget: WorkspaceAlignmentOpenTarget,
        normalizedActiveProjectPath: String?,
        activeWorkspaceOwnedGroupID: String?
    ) -> Bool {
        guard let normalizedActiveProjectPath else {
            return false
        }

        let normalizedMemberProjectPath = normalizePath(memberProjectPath)
        let normalizedOpenTargetPath = normalizePath(openTarget.path)

        if let activeWorkspaceOwnedGroupID {
            guard activeWorkspaceOwnedGroupID == groupID else {
                return false
            }
            return normalizedActiveProjectPath == normalizedOpenTargetPath ||
                normalizedActiveProjectPath == normalizedMemberProjectPath
        }

        guard normalizedActiveProjectPath == normalizedOpenTargetPath else {
            return false
        }

        switch openTarget {
        case .worktree:
            return true
        case .project:
            guard case .aligned = status else {
                return false
            }
            return normalizedActiveProjectPath == normalizedMemberProjectPath
        }
    }
}

private func workspaceAlignmentProjectionLastPathComponent(_ path: String) -> String {
    let lastComponent = (path as NSString).lastPathComponent
    return lastComponent.isEmpty ? path : lastComponent
}
