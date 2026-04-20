import Foundation

struct WorkspaceSidebarPendingWorktreeCreate: Equatable {
    enum Status: Equatable {
        case creating
        case failed
    }

    let rootProjectPath: String
    let branch: String
    let baseBranch: String?
    let worktreePath: String
    let createdAt: SwiftDate
    let status: Status
    let step: NativeWorktreeInitStep
    let message: String
    let error: String?
}

@MainActor
final class WorkspaceSidebarProjectionBuilder {
    private let normalizePath: @MainActor (String) -> String
    private let openWorkspaceSessions: @MainActor () -> [OpenWorkspaceSessionState]
    private let activeProjectPath: @MainActor () -> String?
    private let projectsByNormalizedPath: @MainActor () -> [String: Project]
    private let currentBranchByProjectPath: @MainActor () -> [String: String]
    private let attentionStateByProjectPath: @MainActor () -> [String: WorkspaceAttentionState]
    private let agentDisplayOverridesByProjectPath: @MainActor () -> [String: [String: WorkspaceAgentPresentationOverride]]
    private let pendingWorktreeCreates: @MainActor () -> [WorkspaceSidebarPendingWorktreeCreate]
    private let resolvedPresentedTabSelection: @MainActor (String, GhosttyWorkspaceController?) -> WorkspacePresentedTabSelection?

    init(
        normalizePath: @escaping @MainActor (String) -> String,
        openWorkspaceSessions: @escaping @MainActor () -> [OpenWorkspaceSessionState],
        activeProjectPath: @escaping @MainActor () -> String?,
        projectsByNormalizedPath: @escaping @MainActor () -> [String: Project],
        currentBranchByProjectPath: @escaping @MainActor () -> [String: String],
        attentionStateByProjectPath: @escaping @MainActor () -> [String: WorkspaceAttentionState],
        agentDisplayOverridesByProjectPath: @escaping @MainActor () -> [String: [String: WorkspaceAgentPresentationOverride]],
        pendingWorktreeCreates: @escaping @MainActor () -> [WorkspaceSidebarPendingWorktreeCreate],
        resolvedPresentedTabSelection: @escaping @MainActor (String, GhosttyWorkspaceController?) -> WorkspacePresentedTabSelection?
    ) {
        self.normalizePath = normalizePath
        self.openWorkspaceSessions = openWorkspaceSessions
        self.activeProjectPath = activeProjectPath
        self.projectsByNormalizedPath = projectsByNormalizedPath
        self.currentBranchByProjectPath = currentBranchByProjectPath
        self.attentionStateByProjectPath = attentionStateByProjectPath
        self.agentDisplayOverridesByProjectPath = agentDisplayOverridesByProjectPath
        self.pendingWorktreeCreates = pendingWorktreeCreates
        self.resolvedPresentedTabSelection = resolvedPresentedTabSelection
    }

    func groups(
        showsInAppNotifications: Bool,
        moveNotifiedWorktreeToTop: Bool,
        collapsedProjectPaths: Set<String>
    ) -> [WorkspaceSidebarProjectGroup] {
        let sessions = openWorkspaceSessions()
        let normalizedActiveProjectPath = normalizeOptionalPath(activeProjectPath())
        let projectsByNormalizedPath = projectsByNormalizedPath()
        let currentBranchByProjectPath = currentBranchByProjectPath()
        let attentionStateByProjectPath = attentionStateByProjectPath()
        let agentDisplayOverridesByProjectPath = agentDisplayOverridesByProjectPath()
        let pendingWorktreeCreates = pendingWorktreeCreates()

        return orderedGroupIdentities(
            from: sessions,
            projectsByNormalizedPath: projectsByNormalizedPath
        ).compactMap { identity in
            if let transientKind = identity.transientKind {
                guard let session = sessions.first(where: { groupID(for: $0) == identity.id }) else {
                    return nil
                }
                let normalizedProjectPath = normalizePath(session.projectPath)
                let attention = attentionStateByProjectPath[normalizedProjectPath]
                let agentProjection = resolveAgentProjection(
                    attention: attention,
                    overridesByPaneID: agentDisplayOverridesByProjectPath[normalizedProjectPath] ?? [:],
                    preferredPaneIDs: preferredAgentPaneIDs(for: session)
                )
                let transientProject = makeTransientProject(
                    for: session,
                    transientKind: transientKind
                )
                return WorkspaceSidebarProjectGroup(
                    rootProject: transientProject,
                    worktrees: [],
                    isWorktreeListExpanded: true,
                    isActive: normalizedProjectPath == normalizedActiveProjectPath,
                    notifications: showsInAppNotifications ? (attention?.notifications ?? []) : [],
                    unreadNotificationCount: showsInAppNotifications ? (attention?.unreadCount ?? 0) : 0,
                    taskStatus: attention?.taskStatus,
                    agentState: agentProjection.state,
                    agentPhase: agentProjection.phase,
                    agentAttention: agentProjection.attention,
                    agentSummary: agentProjection.summary,
                    agentKind: agentProjection.kind,
                    agentUpdatedAt: agentProjection.updatedAt
                )
            }

            let rootPath = identity.normalizedPath
            guard let rootProject = projectsByNormalizedPath[rootPath] else {
                return nil
            }
            let worktrees = worktreeItems(
                for: rootProject,
                rootProjectPath: rootPath,
                sessions: sessions,
                normalizedActiveProjectPath: normalizedActiveProjectPath,
                attentionStateByProjectPath: attentionStateByProjectPath,
                agentDisplayOverridesByProjectPath: agentDisplayOverridesByProjectPath,
                pendingWorktreeCreates: pendingWorktreeCreates,
                showsInAppNotifications: showsInAppNotifications,
                moveNotifiedWorktreeToTop: moveNotifiedWorktreeToTop
            )
            let rootAttention = attentionStateByProjectPath[rootPath]
            let rootSession = sessions.first(where: {
                normalizePath($0.projectPath) == rootPath &&
                    normalizePath($0.rootProjectPath) == rootPath
            })
            let rootAgentProjection = resolveAgentProjection(
                attention: rootAttention,
                overridesByPaneID: agentDisplayOverridesByProjectPath[rootPath] ?? [:],
                preferredPaneIDs: preferredAgentPaneIDs(for: rootSession)
            )
            let notifications = showsInAppNotifications
                ? ([rootAttention?.notifications ?? []] + worktrees.map(\.notifications))
                    .flatMap { $0 }
                    .sorted { $0.createdAt > $1.createdAt }
                : []
            let unreadNotificationCount = showsInAppNotifications
                ? (rootAttention?.unreadCount ?? 0) + worktrees.reduce(into: 0) { count, item in
                    count += item.unreadNotificationCount
                }
                : 0
            let isGroupActive = normalizedActiveProjectPath == rootPath || worktrees.contains(where: \.isActive)
            let groupAgentProjection = groupedAgentProjection(
                rootIsActive: normalizedActiveProjectPath == rootPath,
                rootAgentProjection: rootAgentProjection,
                worktrees: worktrees
            )
            return WorkspaceSidebarProjectGroup(
                rootProject: rootProject,
                worktrees: worktrees,
                isWorktreeListExpanded: !collapsedProjectPaths.contains(rootPath),
                isActive: isGroupActive,
                currentBranch: currentBranchByProjectPath[rootPath],
                notifications: notifications,
                unreadNotificationCount: unreadNotificationCount,
                taskStatus: groupTaskStatus(
                    rootAttention: rootAttention,
                    worktrees: worktrees
                ),
                agentState: groupAgentProjection?.state,
                agentPhase: groupAgentProjection?.phase,
                agentAttention: groupAgentProjection?.attention,
                agentSummary: groupAgentProjection?.summary,
                agentKind: groupAgentProjection?.kind,
                agentUpdatedAt: groupAgentProjection?.updatedAt
            )
        }
    }

    func groupID(for session: OpenWorkspaceSessionState) -> String? {
        groupIdentity(
            for: session,
            projectsByNormalizedPath: projectsByNormalizedPath()
        )?.id
    }

    private func orderedGroupIdentities(
        from sessions: [OpenWorkspaceSessionState],
        projectsByNormalizedPath: [String: Project]
    ) -> [SidebarGroupIdentity] {
        var identities: [SidebarGroupIdentity] = []
        var seen = Set<String>()

        for session in sessions {
            guard let identity = groupIdentity(
                for: session,
                projectsByNormalizedPath: projectsByNormalizedPath
            ),
            seen.insert(identity.id).inserted
            else {
                continue
            }
            identities.append(identity)
        }

        return identities
    }

    private func groupIdentity(
        for session: OpenWorkspaceSessionState,
        projectsByNormalizedPath: [String: Project]
    ) -> SidebarGroupIdentity? {
        if let transientProject = session.transientDisplayProject,
           transientProject.isDirectoryWorkspace {
            return SidebarGroupIdentity(
                id: transientProject.id,
                normalizedPath: normalizePath(session.projectPath),
                transientKind: .directoryWorkspace
            )
        }
        if session.isQuickTerminal {
            if let workspaceRootContext = session.workspaceRootContext {
                return SidebarGroupIdentity(
                    id: Project.workspaceRoot(
                        name: workspaceRootContext.workspaceName,
                        path: session.projectPath
                    ).id,
                    normalizedPath: normalizePath(session.projectPath),
                    transientKind: .workspaceRoot
                )
            }

            return SidebarGroupIdentity(
                id: Project.quickTerminal(at: session.projectPath).id,
                normalizedPath: normalizePath(session.projectPath),
                transientKind: .quickTerminal
            )
        }

        let normalizedRootProjectPath = normalizePath(session.rootProjectPath)
        guard let rootProject = projectsByNormalizedPath[normalizedRootProjectPath] else {
            return nil
        }
        return SidebarGroupIdentity(
            id: rootProject.id,
            normalizedPath: normalizedRootProjectPath,
            transientKind: nil
        )
    }

    private func makeTransientProject(
        for session: OpenWorkspaceSessionState,
        transientKind: SidebarTransientKind
    ) -> Project {
        switch transientKind {
        case .workspaceRoot:
            Project.workspaceRoot(
                name: session.workspaceRootContext?.workspaceName ?? workspaceSidebarLastPathComponent(session.projectPath),
                path: session.projectPath
            )
        case .quickTerminal:
            Project.quickTerminal(at: session.projectPath)
        case .directoryWorkspace:
            session.transientDisplayProject ?? Project.directoryWorkspace(at: session.projectPath)
        }
    }

    private func worktreeItems(
        for rootProject: Project,
        rootProjectPath: String,
        sessions: [OpenWorkspaceSessionState],
        normalizedActiveProjectPath: String?,
        attentionStateByProjectPath: [String: WorkspaceAttentionState],
        agentDisplayOverridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]],
        pendingWorktreeCreates: [WorkspaceSidebarPendingWorktreeCreate],
        showsInAppNotifications: Bool,
        moveNotifiedWorktreeToTop: Bool
    ) -> [WorkspaceSidebarWorktreeItem] {
        let persistedPaths = Set(rootProject.worktrees.map { normalizePath($0.path) })
        let persistedItems = rootProject.worktrees.map { worktree -> WorkspaceSidebarWorktreeItem in
            let normalizedWorktreePath = normalizePath(worktree.path)
            let visibleSidebarSession = sessions.first(where: {
                normalizePath($0.projectPath) == normalizedWorktreePath &&
                    !$0.isQuickTerminal &&
                    normalizePath($0.rootProjectPath) == rootProjectPath
            })
            let attention = visibleSidebarSession.flatMap { _ in attentionStateByProjectPath[normalizedWorktreePath] }
            let agentProjection = resolveAgentProjection(
                attention: attention,
                overridesByPaneID: agentDisplayOverridesByProjectPath[normalizedWorktreePath] ?? [:],
                preferredPaneIDs: preferredAgentPaneIDs(for: visibleSidebarSession)
            )
            return WorkspaceSidebarWorktreeItem(
                rootProjectPath: rootProjectPath,
                worktree: worktree,
                isOpen: visibleSidebarSession != nil,
                isActive: visibleSidebarSession != nil && normalizedActiveProjectPath == normalizedWorktreePath,
                notifications: showsInAppNotifications ? (attention?.notifications ?? []) : [],
                unreadNotificationCount: showsInAppNotifications ? (attention?.unreadCount ?? 0) : 0,
                taskStatus: attention.map(\.taskStatus),
                agentState: agentProjection.state,
                agentPhase: agentProjection.phase,
                agentAttention: agentProjection.attention,
                agentSummary: agentProjection.summary,
                agentKind: agentProjection.kind,
                agentUpdatedAt: agentProjection.updatedAt
            )
        }
        let pendingItems = pendingWorktreeCreates
            .filter { normalizePath($0.rootProjectPath) == rootProjectPath }
            .filter { !persistedPaths.contains(normalizePath($0.worktreePath)) }
            .sorted { $0.worktreePath < $1.worktreePath }
            .map { pending in
                let syntheticWorktree = ProjectWorktree(
                    id: workspaceSidebarWorktreeProjectID(path: pending.worktreePath),
                    name: workspaceSidebarLastPathComponent(pending.worktreePath),
                    path: pending.worktreePath,
                    branch: pending.branch,
                    baseBranch: pending.baseBranch,
                    inheritConfig: true,
                    created: pending.createdAt,
                    updatedAt: pending.createdAt
                )
                return WorkspaceSidebarWorktreeItem(
                    rootProjectPath: rootProjectPath,
                    worktree: syntheticWorktree,
                    isOpen: false,
                    isActive: false,
                    notifications: [],
                    unreadNotificationCount: 0,
                    taskStatus: nil,
                    agentState: nil,
                    agentPhase: nil,
                    agentAttention: nil,
                    agentSummary: nil,
                    agentKind: nil,
                    agentUpdatedAt: nil,
                    displayStateOverride: pending.status == .creating
                        ? .creating(message: pending.message)
                        : .failed(message: pending.error ?? pending.message),
                    displayInitStepOverride: pending.step,
                    displayInitErrorOverride: pending.error,
                    displayInitMessageOverride: pending.message
                )
            }
        let items = persistedItems + pendingItems
        guard moveNotifiedWorktreeToTop, showsInAppNotifications else {
            return items
        }
        let originalIndices = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.path, $0.offset) })
        return items.sorted { lhs, rhs in
            if prefersBefore(lhs, rhs) {
                return true
            }
            if prefersBefore(rhs, lhs) {
                return false
            }
            return (originalIndices[lhs.path] ?? 0) < (originalIndices[rhs.path] ?? 0)
        }
    }

    private func preferredAgentPaneIDs(for session: OpenWorkspaceSessionState?) -> Set<String> {
        guard let session else {
            return []
        }
        let projectPath = normalizePath(session.projectPath)
        let controller = session.controller

        if case let .terminal(selectedTerminalTabID)? = resolvedPresentedTabSelection(
            projectPath,
            controller
        ),
        let selectedTab = controller.tabs.first(where: { $0.id == selectedTerminalTabID }) {
            return Set(selectedTab.leaves.map(\.id))
        }

        if let selectedTab = controller.selectedTab {
            return Set(selectedTab.leaves.map(\.id))
        }

        return []
    }

    private func resolveAgentProjection(
        attention: WorkspaceAttentionState?,
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride],
        preferredPaneIDs: Set<String>
    ) -> SidebarAgentProjection {
        guard let attention else {
            return SidebarAgentProjection()
        }
        if preferredPaneIDs.isEmpty {
            return SidebarAgentProjection(
                state: attention.resolvedAgentState(overridesByPaneID: overridesByPaneID),
                phase: attention.resolvedAgentPhase(overridesByPaneID: overridesByPaneID),
                attention: attention.resolvedAgentAttention(overridesByPaneID: overridesByPaneID),
                summary: attention.resolvedAgentSummary(overridesByPaneID: overridesByPaneID),
                kind: attention.resolvedAgentKind(overridesByPaneID: overridesByPaneID),
                updatedAt: attention.resolvedAgentUpdatedAt(overridesByPaneID: overridesByPaneID)
            )
        }
        return SidebarAgentProjection(
            state: attention.resolvedAgentState(
                overridesByPaneID: overridesByPaneID,
                preferringPaneIDs: preferredPaneIDs
            ),
            phase: attention.resolvedAgentPhase(
                overridesByPaneID: overridesByPaneID,
                preferringPaneIDs: preferredPaneIDs
            ),
            attention: attention.resolvedAgentAttention(
                overridesByPaneID: overridesByPaneID,
                preferringPaneIDs: preferredPaneIDs
            ),
            summary: attention.resolvedAgentSummary(
                overridesByPaneID: overridesByPaneID,
                preferringPaneIDs: preferredPaneIDs
            ),
            kind: attention.resolvedAgentKind(
                overridesByPaneID: overridesByPaneID,
                preferringPaneIDs: preferredPaneIDs
            ),
            updatedAt: attention.resolvedAgentUpdatedAt(
                overridesByPaneID: overridesByPaneID,
                preferringPaneIDs: preferredPaneIDs
            )
        )
    }

    private func prefersBefore(
        _ lhs: WorkspaceSidebarWorktreeItem,
        _ rhs: WorkspaceSidebarWorktreeItem
    ) -> Bool {
        if lhs.hasUnreadNotifications != rhs.hasUnreadNotifications {
            return lhs.hasUnreadNotifications && !rhs.hasUnreadNotifications
        }

        let lhsDate = lhs.notifications.first?.createdAt
        let rhsDate = rhs.notifications.first?.createdAt
        switch (lhsDate, rhsDate) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return false
        }
    }

    private func groupTaskStatus(
        rootAttention: WorkspaceAttentionState?,
        worktrees: [WorkspaceSidebarWorktreeItem]
    ) -> WorkspaceTaskStatus? {
        let statuses = [rootAttention?.taskStatus] + worktrees.map(\.taskStatus)
        if statuses.contains(.running) {
            return .running
        }
        if rootAttention != nil || worktrees.contains(where: { $0.taskStatus != nil }) {
            return .idle
        }
        return nil
    }

    private func groupedAgentProjection(
        rootIsActive: Bool,
        rootAgentProjection: SidebarAgentProjection,
        worktrees: [WorkspaceSidebarWorktreeItem]
    ) -> SidebarAgentProjection? {
        let activeWorktreeCandidates = worktrees.compactMap { worktree -> SidebarAgentCandidate? in
            guard worktree.isActive, let state = worktree.agentState else {
                return nil
            }
            return SidebarAgentCandidate(
                state: state,
                phase: worktree.agentPhase,
                attention: worktree.agentAttention,
                summary: worktree.agentSummary,
                kind: worktree.agentKind,
                updatedAt: worktree.agentUpdatedAt,
                isActive: true,
                isOpen: worktree.isOpen
            )
        }
        if let prioritizedActiveWorktree = prioritizedAgentCandidate(from: activeWorktreeCandidates) {
            return SidebarAgentProjection(
                state: prioritizedActiveWorktree.state,
                phase: prioritizedActiveWorktree.phase,
                attention: prioritizedActiveWorktree.attention,
                summary: prioritizedActiveWorktree.summary,
                kind: prioritizedActiveWorktree.kind,
                updatedAt: prioritizedActiveWorktree.updatedAt
            )
        }

        var fallbackCandidates = worktrees.compactMap { worktree -> SidebarAgentCandidate? in
            guard let state = worktree.agentState else {
                return nil
            }
            return SidebarAgentCandidate(
                state: state,
                phase: worktree.agentPhase,
                attention: worktree.agentAttention,
                summary: worktree.agentSummary,
                kind: worktree.agentKind,
                updatedAt: worktree.agentUpdatedAt,
                isActive: worktree.isActive,
                isOpen: worktree.isOpen
            )
        }
        if let rootAgentState = rootAgentProjection.state {
            fallbackCandidates.append(
                SidebarAgentCandidate(
                    state: rootAgentState,
                    phase: rootAgentProjection.phase,
                    attention: rootAgentProjection.attention,
                    summary: rootAgentProjection.summary,
                    kind: rootAgentProjection.kind,
                    updatedAt: rootAgentProjection.updatedAt,
                    isActive: rootIsActive,
                    isOpen: rootIsActive,
                    isRoot: true
                )
            )
        }

        guard let prioritizedCandidate = prioritizedAgentCandidate(from: fallbackCandidates) else {
            return nil
        }
        return SidebarAgentProjection(
            state: prioritizedCandidate.state,
            phase: prioritizedCandidate.phase,
            attention: prioritizedCandidate.attention,
            summary: prioritizedCandidate.summary,
            kind: prioritizedCandidate.kind,
            updatedAt: prioritizedCandidate.updatedAt
        )
    }

    private func prioritizedAgentCandidate(
        from candidates: [SidebarAgentCandidate]
    ) -> SidebarAgentCandidate? {
        candidates.max { lhs, rhs in
            if lhs.activityPriority != rhs.activityPriority {
                return lhs.activityPriority < rhs.activityPriority
            }
            if (lhs.attention?.priority ?? 0) != (rhs.attention?.priority ?? 0) {
                return (lhs.attention?.priority ?? 0) < (rhs.attention?.priority ?? 0)
            }
            if lhs.state.priority != rhs.state.priority {
                return lhs.state.priority < rhs.state.priority
            }
            if (lhs.updatedAt ?? .distantPast) != (rhs.updatedAt ?? .distantPast) {
                return (lhs.updatedAt ?? .distantPast) < (rhs.updatedAt ?? .distantPast)
            }
            if lhs.isRoot != rhs.isRoot {
                return lhs.isRoot && !rhs.isRoot
            }
            return false
        }
    }

    private func normalizeOptionalPath(_ path: String?) -> String? {
        guard let path else {
            return nil
        }
        return normalizePath(path)
    }

    private struct SidebarGroupIdentity {
        let id: String
        let normalizedPath: String
        let transientKind: SidebarTransientKind?
    }

    private enum SidebarTransientKind {
        case workspaceRoot
        case quickTerminal
        case directoryWorkspace
    }

    private struct SidebarAgentProjection {
        var state: WorkspaceAgentState?
        var phase: WorkspaceAgentPhase?
        var attention: WorkspaceAgentAttentionRequirement?
        var summary: String?
        var kind: WorkspaceAgentKind?
        var updatedAt: Date?
    }

    private struct SidebarAgentCandidate {
        let state: WorkspaceAgentState
        let phase: WorkspaceAgentPhase?
        let attention: WorkspaceAgentAttentionRequirement?
        let summary: String?
        let kind: WorkspaceAgentKind?
        let updatedAt: Date?
        let isActive: Bool
        let isOpen: Bool
        var isRoot: Bool = false

        var activityPriority: Int {
            if isActive {
                return 2
            }
            if isOpen {
                return 1
            }
            return 0
        }
    }
}

private func workspaceSidebarWorktreeProjectID(path: String) -> String {
    "worktree:\(path)"
}

private func workspaceSidebarLastPathComponent(_ path: String) -> String {
    let lastComponent = (path as NSString).lastPathComponent
    return lastComponent.isEmpty ? path : lastComponent
}
