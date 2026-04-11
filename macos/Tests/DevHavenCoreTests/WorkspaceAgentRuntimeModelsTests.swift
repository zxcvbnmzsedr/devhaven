import XCTest
@testable import DevHavenCore

final class WorkspaceAgentRuntimeModelsTests: XCTestCase {
    func testDefaultPhaseMappingFollowsLegacyStateCompatibility() {
        XCTAssertEqual(WorkspaceAgentState.unknown.defaultPhase, .unknown)
        XCTAssertEqual(WorkspaceAgentState.running.defaultPhase, .thinking)
        XCTAssertEqual(WorkspaceAgentState.waiting.defaultPhase, .awaitingInput)
        XCTAssertEqual(WorkspaceAgentState.idle.defaultPhase, .idle)
        XCTAssertEqual(WorkspaceAgentState.completed.defaultPhase, .completed)
        XCTAssertEqual(WorkspaceAgentState.failed.defaultPhase, .failed)
    }

    func testDefaultAttentionMappingFollowsPhaseSemantics() {
        XCTAssertEqual(WorkspaceAgentPhase.awaitingApproval.defaultAttention, .approval)
        XCTAssertEqual(WorkspaceAgentPhase.awaitingInput.defaultAttention, .input)
        XCTAssertEqual(WorkspaceAgentPhase.notifying.defaultAttention, .notification)
        XCTAssertEqual(WorkspaceAgentPhase.failed.defaultAttention, .error)
        XCTAssertEqual(WorkspaceAgentPhase.stale.defaultAttention, .error)
        XCTAssertEqual(WorkspaceAgentPhase.runningTool.defaultAttention, .none)
    }

    func testSignalEffectiveValuesPreferRicherFields() {
        let signal = WorkspaceAgentSessionSignal(
            projectPath: "/tmp/project",
            workspaceId: "workspace",
            tabId: "tab",
            paneId: "pane",
            surfaceId: "surface",
            terminalSessionId: "terminal",
            agentKind: .codex,
            sessionId: "session",
            state: .running,
            phase: .awaitingApproval,
            attention: .approval,
            toolName: "bash",
            summary: "needs approval"
        )

        XCTAssertEqual(signal.effectivePhase, .awaitingApproval)
        XCTAssertEqual(signal.effectiveAttention, .approval)
        XCTAssertEqual(signal.effectiveState, .waiting)
    }

    func testSignalEffectiveValuesFallbackFromLegacyStateWhenPhaseMissing() {
        let signal = WorkspaceAgentSessionSignal(
            projectPath: "/tmp/project",
            workspaceId: "workspace",
            tabId: "tab",
            paneId: "pane",
            surfaceId: "surface",
            terminalSessionId: "terminal",
            agentKind: .claude,
            sessionId: "session",
            state: .waiting,
            summary: "waiting"
        )

        XCTAssertEqual(signal.effectivePhase, .awaitingInput)
        XCTAssertEqual(signal.effectiveAttention, .input)
        XCTAssertEqual(signal.effectiveState, .waiting)
    }
}
