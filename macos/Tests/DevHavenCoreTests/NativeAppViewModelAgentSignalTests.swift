import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelAgentSignalTests: XCTestCase {
    func testCodexDisplayCandidatesRevisionOnlyChangesWhenCandidateSetChanges() {
        let projectPath = "/tmp/project"
        let viewModel = NativeAppViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: projectPath,
                controller: GhosttyWorkspaceController(projectPath: projectPath)
            )
        ]

        XCTAssertTrue(viewModel.codexDisplayCandidates().isEmpty)
        let initialRevision = viewModel.codexDisplayCandidatesRevision

        viewModel.updateWorkspaceTaskStatus(
            projectPath: projectPath,
            paneID: "pane-1",
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
                tabId: "tab-1",
                paneId: "pane-1",
                surfaceId: "surface",
                terminalSessionId: "terminal-1",
                agentKind: .codex,
                sessionId: "session-1",
                state: .running,
                summary: "running"
            )
        )

        XCTAssertEqual(
            viewModel.codexDisplayCandidates(),
            [
                WorkspaceAgentDisplayCandidate(
                    projectPath: projectPath,
                    paneID: "pane-1",
                    signalState: .running
                )
            ]
        )
        let signalRevision = viewModel.codexDisplayCandidatesRevision
        XCTAssertGreaterThan(signalRevision, initialRevision)

        viewModel.updateWorkspaceTaskStatus(
            projectPath: projectPath,
            paneID: "pane-1",
            status: .idle
        )
        XCTAssertEqual(
            viewModel.codexDisplayCandidatesRevision,
            signalRevision,
            "非 agent attention 更新不应重复触发 codex candidate 刷新"
        )

        viewModel.clearAgentSignal(projectPath: projectPath, paneID: "pane-1")

        XCTAssertTrue(viewModel.codexDisplayCandidates().isEmpty)
        XCTAssertGreaterThan(viewModel.codexDisplayCandidatesRevision, signalRevision)
    }
}
