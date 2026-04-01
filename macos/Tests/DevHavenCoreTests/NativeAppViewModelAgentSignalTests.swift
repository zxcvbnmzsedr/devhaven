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
                    signalState: .running,
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
                    signalState: .waiting,
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
                    signalState: .running,
                    signalUpdatedAt: firstSignalTime
                )
            ]
        )
    }
}
