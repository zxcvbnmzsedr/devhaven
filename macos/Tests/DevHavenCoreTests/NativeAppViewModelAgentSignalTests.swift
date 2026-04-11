import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelAgentSignalTests: XCTestCase {
    func testCodexDisplayCandidatesRevisionOnlyChangesWhenCandidateSetChanges() {
        let projectPath = "/tmp/project"
        let signalUpdatedAt = Date(timeIntervalSinceReferenceDate: 123)
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        let tab = controller.createTab()
        let viewModel = NativeAppViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: projectPath,
                controller: controller
            )
        ]
        viewModel.activeWorkspaceProjectPath = projectPath

        XCTAssertTrue(viewModel.codexDisplayCandidates().isEmpty)
        let initialRevision = viewModel.codexDisplayCandidatesRevision

        viewModel.updateWorkspaceTaskStatus(
            projectPath: projectPath,
            paneID: tab.focusedPaneId,
            status: .running
        )

        XCTAssertEqual(
            viewModel.codexDisplayCandidatesRevision,
            initialRevision,
            "仅 task status 变化不应触发 codex candidate 链路刷新"
        )

        viewModel.recordAgentSignal(
            WorkspaceAgentSessionSignal(
                projectPath: projectPath,
                workspaceId: "workspace",
                tabId: tab.id,
                paneId: tab.focusedPaneId,
                surfaceId: "surface",
                terminalSessionId: "terminal-1",
                agentKind: .codex,
                sessionId: "session-1",
                state: .running,
                summary: "running",
                updatedAt: signalUpdatedAt
            )
        )

        XCTAssertEqual(
            viewModel.codexDisplayCandidates(),
            [
                WorkspaceAgentDisplayCandidate(
                    projectPath: projectPath,
                    paneID: tab.focusedPaneId,
                    signalSessionID: "session-1",
                    signalState: .running,
                    signalPhase: .thinking,
                    signalUpdatedAt: signalUpdatedAt
                )
            ]
        )
        let signalRevision = viewModel.codexDisplayCandidatesRevision
        XCTAssertGreaterThan(signalRevision, initialRevision)

        viewModel.updateWorkspaceTaskStatus(
            projectPath: projectPath,
            paneID: tab.focusedPaneId,
            status: .idle
        )
        XCTAssertEqual(
            viewModel.codexDisplayCandidatesRevision,
            signalRevision,
            "非 agent attention 更新不应重复触发 codex candidate 刷新"
        )

        viewModel.clearAgentSignal(projectPath: projectPath, paneID: tab.focusedPaneId)

        XCTAssertTrue(viewModel.codexDisplayCandidates().isEmpty)
        XCTAssertGreaterThan(viewModel.codexDisplayCandidatesRevision, signalRevision)
    }

    func testCodexDisplayCandidatesOnlyTrackVisiblePanesInActiveTerminalTab() {
        let projectPath = "/tmp/project"
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        let firstTab = controller.createTab()
        let secondTab = controller.createTab()
        let firstPaneID = firstTab.focusedPaneId
        let secondPaneID = secondTab.focusedPaneId
        let firstSignalTime = Date(timeIntervalSinceReferenceDate: 10)
        let secondSignalTime = Date(timeIntervalSinceReferenceDate: 20)

        let viewModel = NativeAppViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: projectPath,
                controller: controller
            )
        ]
        viewModel.activeWorkspaceProjectPath = projectPath

        viewModel.recordAgentSignal(
            WorkspaceAgentSessionSignal(
                projectPath: projectPath,
                workspaceId: "workspace",
                tabId: firstTab.id,
                paneId: firstPaneID,
                surfaceId: "surface-1",
                terminalSessionId: "terminal-1",
                agentKind: .codex,
                sessionId: "session-1",
                state: .running,
                summary: "running",
                updatedAt: firstSignalTime
            )
        )
        viewModel.recordAgentSignal(
            WorkspaceAgentSessionSignal(
                projectPath: projectPath,
                workspaceId: "workspace",
                tabId: secondTab.id,
                paneId: secondPaneID,
                surfaceId: "surface-2",
                terminalSessionId: "terminal-2",
                agentKind: .codex,
                sessionId: "session-2",
                state: .waiting,
                summary: "waiting",
                updatedAt: secondSignalTime
            )
        )

        XCTAssertEqual(
            viewModel.codexDisplayCandidates(),
            [
                WorkspaceAgentDisplayCandidate(
                    projectPath: projectPath,
                    paneID: secondPaneID,
                    signalSessionID: "session-2",
                    signalState: .waiting,
                    signalPhase: .awaitingInput,
                    signalAttention: .input,
                    signalUpdatedAt: secondSignalTime
                )
            ],
            "仅当前活动 terminal tab 中真正可见的 pane 才应进入 Codex fallback 追踪"
        )

        controller.selectTab(firstTab.id)

        XCTAssertEqual(
            viewModel.codexDisplayCandidates(),
            [
                WorkspaceAgentDisplayCandidate(
                    projectPath: projectPath,
                    paneID: firstPaneID,
                    signalSessionID: "session-1",
                    signalState: .running,
                    signalPhase: .thinking,
                    signalUpdatedAt: firstSignalTime
                )
            ]
        )
    }

    func testRecordAgentSignalRemapsMovedSurfaceToCurrentPane() throws {
        let projectPath = "/tmp/project"
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        let sourcePaneID = try XCTUnwrap(controller.selectedPane?.id)
        let movedItem = try XCTUnwrap(controller.createTerminalItem(inPane: sourcePaneID))
        let targetPane = try XCTUnwrap(controller.splitFocusedPane(direction: .right))
        _ = try XCTUnwrap(
            controller.movePaneItem(
                movedItem.id,
                from: sourcePaneID,
                to: targetPane.id,
                at: 1
            )
        )

        let viewModel = NativeAppViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: projectPath,
                controller: controller
            )
        ]
        viewModel.activeWorkspaceProjectPath = projectPath

        viewModel.recordAgentSignal(
            WorkspaceAgentSessionSignal(
                projectPath: projectPath,
                workspaceId: controller.workspaceId,
                tabId: try XCTUnwrap(controller.selectedTabId),
                paneId: sourcePaneID,
                surfaceId: movedItem.id,
                terminalSessionId: movedItem.request.terminalSessionId,
                agentKind: .codex,
                sessionId: "session-1",
                state: .running,
                summary: "running",
                updatedAt: Date(timeIntervalSinceReferenceDate: 42)
            )
        )

        XCTAssertEqual(
            viewModel.codexDisplayCandidates(),
            [
                WorkspaceAgentDisplayCandidate(
                    projectPath: projectPath,
                    paneID: targetPane.id,
                    signalSessionID: "session-1",
                    signalState: .running,
                    signalPhase: .thinking,
                    signalUpdatedAt: Date(timeIntervalSinceReferenceDate: 42)
                )
            ]
        )
    }

    func testRecordAgentSignalPreservesPhaseAndAttentionInWorkspaceAttentionState() {
        let projectPath = "/tmp/project"
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        let tab = controller.createTab()
        let paneID = tab.focusedPaneId
        let viewModel = NativeAppViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: projectPath,
                controller: controller
            )
        ]

        viewModel.recordAgentSignal(
            WorkspaceAgentSessionSignal(
                projectPath: projectPath,
                workspaceId: "workspace",
                tabId: tab.id,
                paneId: paneID,
                surfaceId: "surface",
                terminalSessionId: "terminal-1",
                agentKind: .claude,
                sessionId: "session-1",
                state: .waiting,
                phase: .awaitingApproval,
                attention: .approval,
                toolName: "Bash",
                summary: "Claude 等待审批",
                updatedAt: Date(timeIntervalSinceReferenceDate: 123)
            )
        )

        let attention = viewModel.workspaceAttentionState(for: projectPath)
        XCTAssertEqual(attention?.agentStateByPaneID[paneID], .waiting)
        XCTAssertEqual(attention?.agentSessionIDByPaneID[paneID], "session-1")
        XCTAssertEqual(attention?.agentPhaseByPaneID[paneID], .awaitingApproval)
        XCTAssertEqual(attention?.agentAttentionByPaneID[paneID], .approval)
        XCTAssertEqual(attention?.resolvedAgentPhase(overridesByPaneID: [:]), .awaitingApproval)
        XCTAssertEqual(attention?.resolvedAgentAttention(overridesByPaneID: [:]), .approval)
    }

    func testWorkspaceSidebarGroupPrefersActiveWorktreeAgentPresentationOverRootProjectState() {
        let rootProjectPath = "/tmp/project"
        let worktreePath = "/tmp/project-feature-ai"
        let rootController = GhosttyWorkspaceController(projectPath: rootProjectPath)
        let rootTab = rootController.createTab()
        let worktreeController = GhosttyWorkspaceController(projectPath: worktreePath)
        let worktreeTab = worktreeController.createTab()

        let viewModel = NativeAppViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: .init(),
            projects: [
                Project(
                    id: "project-root",
                    name: "AI客服",
                    path: rootProjectPath,
                    tags: [],
                    runConfigurations: [],
                    worktrees: [
                        ProjectWorktree(
                            id: "worktree-feature-ai",
                            name: "AI客服",
                            path: worktreePath,
                            branch: "feature/ai",
                            inheritConfig: true,
                            created: 0,
                            updatedAt: 0
                        )
                    ],
                    mtime: 0,
                    size: 0,
                    checksum: "",
                    gitCommits: 0,
                    gitLastCommit: 0,
                    created: 0,
                    checked: 0
                )
            ]
        )
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: rootProjectPath,
                controller: rootController
            ),
            OpenWorkspaceSessionState(
                projectPath: worktreePath,
                rootProjectPath: rootProjectPath,
                controller: worktreeController
            )
        ]
        viewModel.activeWorkspaceProjectPath = worktreePath

        viewModel.recordAgentSignal(
            WorkspaceAgentSessionSignal(
                projectPath: rootProjectPath,
                workspaceId: "workspace-root",
                tabId: rootTab.id,
                paneId: rootTab.focusedPaneId,
                surfaceId: "surface-root",
                terminalSessionId: "terminal-root",
                agentKind: .codex,
                sessionId: "session-root",
                state: .waiting,
                summary: "root stale waiting",
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            )
        )
        viewModel.recordAgentSignal(
            WorkspaceAgentSessionSignal(
                projectPath: worktreePath,
                workspaceId: "workspace-worktree",
                tabId: worktreeTab.id,
                paneId: worktreeTab.focusedPaneId,
                surfaceId: "surface-worktree",
                terminalSessionId: "terminal-worktree",
                agentKind: .codex,
                sessionId: "session-worktree",
                state: .running,
                phase: .thinking,
                summary: "active worktree thinking",
                updatedAt: Date(timeIntervalSinceReferenceDate: 200)
            )
        )

        let rootGroup = try? XCTUnwrap(viewModel.workspaceSidebarGroups.first)
        XCTAssertEqual(rootGroup?.agentState, .running)
        XCTAssertEqual(rootGroup?.agentPhase, .thinking)
        XCTAssertEqual(rootGroup?.agentSummary, "active worktree thinking")
        XCTAssertEqual(rootGroup?.agentKind, .codex)
    }

    func testWorkspaceSidebarGroupPrefersVisiblePanePresentationOverHiddenWaitingPane() {
        let projectPath = "/tmp/project"
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        let hiddenTab = controller.createTab()
        let visibleTab = controller.createTab()

        let viewModel = NativeAppViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: .init(),
            projects: [
                Project(
                    id: "project-root",
                    name: "quotation",
                    path: projectPath,
                    tags: [],
                    runConfigurations: [],
                    worktrees: [],
                    mtime: 0,
                    size: 0,
                    checksum: "",
                    gitCommits: 0,
                    gitLastCommit: 0,
                    created: 0,
                    checked: 0
                )
            ]
        )
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: projectPath,
                controller: controller
            )
        ]
        viewModel.activeWorkspaceProjectPath = projectPath

        viewModel.recordAgentSignal(
            WorkspaceAgentSessionSignal(
                projectPath: projectPath,
                workspaceId: "workspace",
                tabId: hiddenTab.id,
                paneId: hiddenTab.focusedPaneId,
                surfaceId: "surface-hidden",
                terminalSessionId: "terminal-hidden",
                agentKind: .codex,
                sessionId: "session-hidden",
                state: .waiting,
                phase: .awaitingInput,
                attention: .input,
                summary: "hidden waiting",
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            )
        )
        viewModel.recordAgentSignal(
            WorkspaceAgentSessionSignal(
                projectPath: projectPath,
                workspaceId: "workspace",
                tabId: visibleTab.id,
                paneId: visibleTab.focusedPaneId,
                surfaceId: "surface-visible",
                terminalSessionId: "terminal-visible",
                agentKind: .codex,
                sessionId: "session-visible",
                state: .running,
                phase: .thinking,
                summary: "visible running",
                updatedAt: Date(timeIntervalSinceReferenceDate: 200)
            )
        )

        let rootGroup = try? XCTUnwrap(viewModel.workspaceSidebarGroups.first)
        XCTAssertEqual(rootGroup?.agentState, .running)
        XCTAssertEqual(rootGroup?.agentPhase, .thinking)
        XCTAssertEqual(rootGroup?.agentAttention, WorkspaceAgentAttentionRequirement.none)
        XCTAssertEqual(rootGroup?.agentSummary, "visible running")
        XCTAssertEqual(rootGroup?.agentKind, .codex)
    }
}
