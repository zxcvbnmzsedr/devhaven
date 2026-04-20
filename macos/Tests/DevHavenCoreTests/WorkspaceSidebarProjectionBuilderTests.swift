import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceSidebarProjectionBuilderTests: XCTestCase {
    func testGroupsBuildTransientWorkspaceKindsInSessionOrder() {
        let workspaceRootPath = "/tmp/workspace-root"
        let quickTerminalPath = "/tmp/quick-terminal"
        let directoryWorkspacePath = "/tmp/directory-workspace"

        let builder = makeBuilder(
            openSessions: [
                OpenWorkspaceSessionState(
                    projectPath: workspaceRootPath,
                    controller: GhosttyWorkspaceController(projectPath: workspaceRootPath),
                    isQuickTerminal: true,
                    workspaceRootContext: WorkspaceRootSessionContext(
                        workspaceID: "workspace-1",
                        workspaceName: "支付链路"
                    )
                ),
                OpenWorkspaceSessionState(
                    projectPath: quickTerminalPath,
                    controller: GhosttyWorkspaceController(projectPath: quickTerminalPath),
                    isQuickTerminal: true
                ),
                OpenWorkspaceSessionState(
                    projectPath: directoryWorkspacePath,
                    controller: GhosttyWorkspaceController(projectPath: directoryWorkspacePath),
                    transientDisplayProject: Project.directoryWorkspace(at: directoryWorkspacePath)
                ),
            ],
            activeProjectPath: directoryWorkspacePath
        )

        let groups = builder.groups(
            showsInAppNotifications: true,
            moveNotifiedWorktreeToTop: true,
            collapsedProjectPaths: []
        )

        XCTAssertEqual(
            groups.map(\.rootProject.id),
            [
                Project.workspaceRoot(name: "支付链路", path: workspaceRootPath).id,
                Project.quickTerminal(at: quickTerminalPath).id,
                Project.directoryWorkspace(at: directoryWorkspacePath).id,
            ]
        )
        XCTAssertEqual(groups[0].rootProject.name, "支付链路")
        XCTAssertTrue(groups[0].rootProject.isWorkspaceRoot)
        XCTAssertTrue(groups[1].rootProject.isQuickTerminal)
        XCTAssertTrue(groups[2].rootProject.isDirectoryWorkspace)
        XCTAssertTrue(groups[2].isActive)
    }

    func testGroupsAggregateNotificationsUnreadCountsAndPromoteNotifiedWorktree() {
        let rootProjectPath = "/tmp/project"
        let worktreeAPath = "/tmp/project-feature-a"
        let worktreeBPath = "/tmp/project-feature-b"
        let rootController = GhosttyWorkspaceController(projectPath: rootProjectPath)
        let rootTab = rootController.createTab()
        let worktreeAController = GhosttyWorkspaceController(projectPath: worktreeAPath)
        let worktreeATab = worktreeAController.createTab()
        let worktreeBController = GhosttyWorkspaceController(projectPath: worktreeBPath)
        let worktreeBTab = worktreeBController.createTab()
        let rootProject = makeProject(
            id: "project-root",
            name: "Quotation",
            path: rootProjectPath,
            worktrees: [
                ProjectWorktree(
                    id: "worktree-a",
                    name: "feature-a",
                    path: worktreeAPath,
                    branch: "feature/a",
                    inheritConfig: true,
                    created: 0,
                    updatedAt: 0
                ),
                ProjectWorktree(
                    id: "worktree-b",
                    name: "feature-b",
                    path: worktreeBPath,
                    branch: "feature/b",
                    inheritConfig: true,
                    created: 0,
                    updatedAt: 0
                ),
            ]
        )
        let builder = makeBuilder(
            projectsByPath: [normalizeSidebarTestPath(rootProjectPath): rootProject],
            openSessions: [
                OpenWorkspaceSessionState(
                    projectPath: rootProjectPath,
                    controller: rootController
                ),
                OpenWorkspaceSessionState(
                    projectPath: worktreeAPath,
                    rootProjectPath: rootProjectPath,
                    controller: worktreeAController
                ),
                OpenWorkspaceSessionState(
                    projectPath: worktreeBPath,
                    rootProjectPath: rootProjectPath,
                    controller: worktreeBController
                ),
            ],
            currentBranches: [normalizeSidebarTestPath(rootProjectPath): "main"],
            attentionStates: [
                normalizeSidebarTestPath(rootProjectPath): makeAttentionState(
                    notifications: [
                        makeNotification(
                            projectPath: rootProjectPath,
                            rootProjectPath: rootProjectPath,
                            tabID: rootTab.id,
                            paneID: rootTab.focusedPaneId,
                            title: "root",
                            createdAt: Date(timeIntervalSinceReferenceDate: 100),
                            isRead: true
                        ),
                    ]
                ),
                normalizeSidebarTestPath(worktreeAPath): makeAttentionState(
                    notifications: [
                        makeNotification(
                            projectPath: worktreeAPath,
                            rootProjectPath: rootProjectPath,
                            tabID: worktreeATab.id,
                            paneID: worktreeATab.focusedPaneId,
                            title: "A",
                            createdAt: Date(timeIntervalSinceReferenceDate: 150),
                            isRead: false
                        ),
                    ],
                    taskStatuses: [worktreeATab.focusedPaneId: .idle]
                ),
                normalizeSidebarTestPath(worktreeBPath): makeAttentionState(
                    notifications: [
                        makeNotification(
                            projectPath: worktreeBPath,
                            rootProjectPath: rootProjectPath,
                            tabID: worktreeBTab.id,
                            paneID: worktreeBTab.focusedPaneId,
                            title: "B",
                            createdAt: Date(timeIntervalSinceReferenceDate: 200),
                            isRead: false
                        ),
                    ],
                    taskStatuses: [worktreeBTab.focusedPaneId: .running]
                ),
            ]
        )

        let group = try? XCTUnwrap(
            builder.groups(
                showsInAppNotifications: true,
                moveNotifiedWorktreeToTop: true,
                collapsedProjectPaths: []
            ).first
        )

        XCTAssertEqual(group?.currentBranch, "main")
        XCTAssertEqual(group?.worktrees.map(\.path), [worktreeBPath, worktreeAPath])
        XCTAssertEqual(group?.notifications.map(\.title), ["B", "A", "root"])
        XCTAssertEqual(group?.unreadNotificationCount, 2)
        XCTAssertEqual(group?.taskStatus, .running)
    }

    func testGroupProjectionPrefersActiveWorktreeAgentProjectionOverRoot() {
        let rootProjectPath = "/tmp/project"
        let worktreePath = "/tmp/project-feature-ai"
        let rootController = GhosttyWorkspaceController(projectPath: rootProjectPath)
        let rootTab = rootController.createTab()
        let worktreeController = GhosttyWorkspaceController(projectPath: worktreePath)
        let worktreeTab = worktreeController.createTab()
        let rootProject = makeProject(
            id: "project-root",
            name: "AI客服",
            path: rootProjectPath,
            worktrees: [
                ProjectWorktree(
                    id: "worktree-feature-ai",
                    name: "AI客服",
                    path: worktreePath,
                    branch: "feature/ai",
                    inheritConfig: true,
                    created: 0,
                    updatedAt: 0
                ),
            ]
        )
        let builder = makeBuilder(
            projectsByPath: [normalizeSidebarTestPath(rootProjectPath): rootProject],
            openSessions: [
                OpenWorkspaceSessionState(
                    projectPath: rootProjectPath,
                    controller: rootController
                ),
                OpenWorkspaceSessionState(
                    projectPath: worktreePath,
                    rootProjectPath: rootProjectPath,
                    controller: worktreeController
                ),
            ],
            activeProjectPath: worktreePath,
            attentionStates: [
                normalizeSidebarTestPath(rootProjectPath): makeAttentionState(
                    agentRecords: [
                        (
                            paneID: rootTab.focusedPaneId,
                            state: .waiting,
                            phase: nil,
                            attention: nil,
                            summary: "root stale waiting",
                            kind: .codex,
                            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
                        ),
                    ]
                ),
                normalizeSidebarTestPath(worktreePath): makeAttentionState(
                    agentRecords: [
                        (
                            paneID: worktreeTab.focusedPaneId,
                            state: .running,
                            phase: .thinking,
                            attention: WorkspaceAgentAttentionRequirement.none,
                            summary: "active worktree thinking",
                            kind: .codex,
                            updatedAt: Date(timeIntervalSinceReferenceDate: 200)
                        ),
                    ]
                ),
            ]
        )

        let rootGroup = try? XCTUnwrap(
            builder.groups(
                showsInAppNotifications: true,
                moveNotifiedWorktreeToTop: true,
                collapsedProjectPaths: []
            ).first
        )

        XCTAssertEqual(rootGroup?.agentState, .running)
        XCTAssertEqual(rootGroup?.agentPhase, .thinking)
        XCTAssertEqual(rootGroup?.agentSummary, "active worktree thinking")
        XCTAssertEqual(rootGroup?.agentKind, .codex)
    }

    func testGroupProjectionPrefersVisiblePaneOverHiddenWaitingPane() {
        let projectPath = "/tmp/project"
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        let hiddenTab = controller.createTab()
        let visibleTab = controller.createTab()
        let project = makeProject(
            id: "project-root",
            name: "quotation",
            path: projectPath
        )
        let builder = makeBuilder(
            projectsByPath: [normalizeSidebarTestPath(projectPath): project],
            openSessions: [
                OpenWorkspaceSessionState(
                    projectPath: projectPath,
                    controller: controller
                ),
            ],
            activeProjectPath: projectPath,
            attentionStates: [
                normalizeSidebarTestPath(projectPath): makeAttentionState(
                    agentRecords: [
                        (
                            paneID: hiddenTab.focusedPaneId,
                            state: .waiting,
                            phase: .awaitingInput,
                            attention: .input,
                            summary: "hidden waiting",
                            kind: .codex,
                            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
                        ),
                        (
                            paneID: visibleTab.focusedPaneId,
                            state: .running,
                            phase: .thinking,
                            attention: WorkspaceAgentAttentionRequirement.none,
                            summary: "visible running",
                            kind: .codex,
                            updatedAt: Date(timeIntervalSinceReferenceDate: 200)
                        ),
                    ]
                ),
            ]
        )

        let rootGroup = try? XCTUnwrap(
            builder.groups(
                showsInAppNotifications: true,
                moveNotifiedWorktreeToTop: true,
                collapsedProjectPaths: []
            ).first
        )

        XCTAssertEqual(rootGroup?.agentState, .running)
        XCTAssertEqual(rootGroup?.agentPhase, .thinking)
        XCTAssertEqual(rootGroup?.agentAttention, WorkspaceAgentAttentionRequirement.none)
        XCTAssertEqual(rootGroup?.agentSummary, "visible running")
        XCTAssertEqual(rootGroup?.agentKind, .codex)
    }

    private func makeBuilder(
        projectsByPath: [String: Project] = [:],
        openSessions: [OpenWorkspaceSessionState] = [],
        activeProjectPath: String? = nil,
        currentBranches: [String: String] = [:],
        attentionStates: [String: WorkspaceAttentionState] = [:],
        agentDisplayOverridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]] = [:],
        pendingWorktreeCreates: [WorkspaceSidebarPendingWorktreeCreate] = [],
        resolvedPresentedTabSelection: @escaping @MainActor (String, GhosttyWorkspaceController?) -> WorkspacePresentedTabSelection? = { _, controller in
            controller?.selectedTabId.map(WorkspacePresentedTabSelection.terminal)
        }
    ) -> WorkspaceSidebarProjectionBuilder {
        WorkspaceSidebarProjectionBuilder(
            normalizePath: { normalizeSidebarTestPath($0) },
            openWorkspaceSessions: { openSessions },
            activeProjectPath: { activeProjectPath },
            projectsByNormalizedPath: { projectsByPath },
            currentBranchByProjectPath: { currentBranches },
            attentionStateByProjectPath: { attentionStates },
            agentDisplayOverridesByProjectPath: { agentDisplayOverridesByProjectPath },
            pendingWorktreeCreates: { pendingWorktreeCreates },
            resolvedPresentedTabSelection: resolvedPresentedTabSelection
        )
    }

    private func makeProject(
        id: String,
        name: String,
        path: String,
        worktrees: [ProjectWorktree] = []
    ) -> Project {
        Project(
            id: id,
            name: name,
            path: path,
            tags: [],
            runConfigurations: [],
            worktrees: worktrees,
            mtime: 0,
            size: 0,
            checksum: "",
            gitCommits: 0,
            gitLastCommit: 0,
            created: 0,
            checked: 0
        )
    }

    private func makeAttentionState(
        notifications: [WorkspaceTerminalNotification] = [],
        taskStatuses: [String: WorkspaceTaskStatus] = [:],
        agentRecords: [(
            paneID: String,
            state: WorkspaceAgentState,
            phase: WorkspaceAgentPhase?,
            attention: WorkspaceAgentAttentionRequirement?,
            summary: String?,
            kind: WorkspaceAgentKind,
            updatedAt: Date
        )] = []
    ) -> WorkspaceAttentionState {
        var state = WorkspaceAttentionState(
            notifications: notifications,
            taskStatusByPaneID: taskStatuses
        )
        for record in agentRecords {
            state.setAgentState(
                record.state,
                kind: record.kind,
                sessionID: "session-\(record.paneID)",
                phase: record.phase,
                attention: record.attention,
                summary: record.summary,
                updatedAt: record.updatedAt,
                for: record.paneID
            )
        }
        return state
    }

    private func makeNotification(
        projectPath: String,
        rootProjectPath: String,
        tabID: String,
        paneID: String,
        title: String,
        createdAt: Date,
        isRead: Bool
    ) -> WorkspaceTerminalNotification {
        WorkspaceTerminalNotification(
            projectPath: projectPath,
            rootProjectPath: rootProjectPath,
            workspaceId: "workspace-\(paneID)",
            tabId: tabID,
            paneId: paneID,
            title: title,
            body: "",
            createdAt: createdAt,
            isRead: isRead
        )
    }
}

private func normalizeSidebarTestPath(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return ""
    }
    var normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
    while normalized.count > 1 && normalized.hasSuffix("/") {
        normalized.removeLast()
    }
    return normalized
}
