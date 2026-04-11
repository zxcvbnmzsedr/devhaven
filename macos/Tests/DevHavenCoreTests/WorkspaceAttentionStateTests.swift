import XCTest
@testable import DevHavenCore

final class WorkspaceAttentionStateTests: XCTestCase {
    func testPrioritizedAgentRecordPrefersHigherAttentionOverRunningState() {
        var attention = WorkspaceAttentionState()
        let earlier = Date(timeIntervalSinceReferenceDate: 100)
        let later = Date(timeIntervalSinceReferenceDate: 200)

        attention.setAgentState(
            .running,
            kind: .codex,
            sessionID: "session-running",
            phase: .runningTool,
            attention: WorkspaceAgentAttentionRequirement.none,
            summary: "running",
            updatedAt: later,
            for: "pane-running"
        )
        attention.setAgentState(
            .waiting,
            kind: .claude,
            sessionID: "session-approval",
            phase: .awaitingApproval,
            attention: .approval,
            summary: "approve",
            updatedAt: earlier,
            for: "pane-approval"
        )

        XCTAssertEqual(attention.agentState, .waiting)
        XCTAssertEqual(attention.agentPhase, .awaitingApproval)
        XCTAssertEqual(attention.agentAttention, .approval)
        XCTAssertEqual(attention.agentKind, .claude)
        XCTAssertEqual(attention.agentSummary, "approve")
    }

    func testResolvedAgentFieldsUseOverridePhaseAndAttentionInsteadOfStoredValues() {
        var attention = WorkspaceAttentionState()
        attention.setAgentState(
            .running,
            kind: .codex,
            sessionID: "session-1",
            phase: .thinking,
            attention: WorkspaceAgentAttentionRequirement.none,
            summary: "thinking",
            updatedAt: Date(timeIntervalSinceReferenceDate: 100),
            for: "pane-1"
        )

        let overrides = [
            "pane-1": WorkspaceAgentPresentationOverride(
                state: .waiting,
                phase: .awaitingInput,
                attention: .input,
                summary: nil
            )
        ]

        XCTAssertEqual(attention.resolvedAgentState(overridesByPaneID: overrides), .waiting)
        XCTAssertEqual(attention.resolvedAgentPhase(overridesByPaneID: overrides), .awaitingInput)
        XCTAssertEqual(attention.resolvedAgentAttention(overridesByPaneID: overrides), .input)
    }

    func testResolvedAgentFieldsPreferVisiblePaneOverHigherAttentionHiddenPane() {
        var attention = WorkspaceAttentionState()
        let earlier = Date(timeIntervalSinceReferenceDate: 100)
        let later = Date(timeIntervalSinceReferenceDate: 200)

        attention.setAgentState(
            .waiting,
            kind: .codex,
            sessionID: "session-hidden",
            phase: .awaitingInput,
            attention: .input,
            summary: "hidden waiting",
            updatedAt: earlier,
            for: "pane-hidden"
        )
        attention.setAgentState(
            .running,
            kind: .codex,
            sessionID: "session-visible",
            phase: .thinking,
            attention: WorkspaceAgentAttentionRequirement.none,
            summary: "visible running",
            updatedAt: later,
            for: "pane-visible"
        )

        let preferredPaneIDs: Set<String> = ["pane-visible"]
        XCTAssertEqual(
            attention.resolvedAgentState(
                overridesByPaneID: [:],
                preferringPaneIDs: preferredPaneIDs
            ),
            .running
        )
        XCTAssertEqual(
            attention.resolvedAgentPhase(
                overridesByPaneID: [:],
                preferringPaneIDs: preferredPaneIDs
            ),
            .thinking
        )
        XCTAssertEqual(
            attention.resolvedAgentSummary(
                overridesByPaneID: [:],
                preferringPaneIDs: preferredPaneIDs
            ),
            "visible running"
        )
    }

    func testSetAgentStateDropsNoneAttentionAndMissingSummary() {
        var attention = WorkspaceAttentionState()
        attention.setAgentState(
            .running,
            kind: .codex,
            sessionID: "session-1",
            phase: .thinking,
            attention: WorkspaceAgentAttentionRequirement.none,
            summary: "   ",
            updatedAt: Date(timeIntervalSinceReferenceDate: 100),
            for: "pane-1"
        )

        XCTAssertEqual(attention.agentStateByPaneID["pane-1"], .running)
        XCTAssertEqual(attention.agentSessionIDByPaneID["pane-1"], "session-1")
        XCTAssertEqual(attention.agentPhaseByPaneID["pane-1"], .thinking)
        XCTAssertNil(attention.agentAttentionByPaneID["pane-1"])
        XCTAssertNil(attention.agentSummaryByPaneID["pane-1"])
    }
}
