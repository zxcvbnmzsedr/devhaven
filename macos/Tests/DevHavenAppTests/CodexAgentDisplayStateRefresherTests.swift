import XCTest
import DevHavenCore
@testable import DevHavenApp

@MainActor
final class CodexAgentDisplayStateRefresherTests: XCTestCase {
    func testRunningSignalSchedulesDeadlineBeforeWaitingFallback() {
        let projectPath = "/tmp/project"
        let paneID = "pane-1"
        let activityTime = Date(timeIntervalSinceReferenceDate: 100)
        let evaluationTime = activityTime.addingTimeInterval(1)

        let evaluation = CodexAgentDisplayStateRefresher.evaluate(
            for: [WorkspaceAgentDisplayCandidate(projectPath: projectPath, paneID: paneID, signalState: .running)],
            runtimeState: .init(),
            now: evaluationTime
        ) { _, _ in
            CodexAgentDisplaySnapshot(
                recentTextWindow: "/model to change",
                lastActivityAt: activityTime
            )
        }

        XCTAssertTrue(evaluation.overridesByProjectPath.isEmpty)
        XCTAssertEqual(
            evaluation.nextRefreshDeadline,
            activityTime.addingTimeInterval(CodexAgentDisplayStateRefresher.recentActivityWindow)
        )
    }

    func testRunningSignalFallsBackToWaitingAfterDeadline() {
        let projectPath = "/tmp/project"
        let paneID = "pane-1"
        let activityTime = Date(timeIntervalSinceReferenceDate: 100)
        let evaluationTime = activityTime.addingTimeInterval(2.1)

        let evaluation = CodexAgentDisplayStateRefresher.evaluate(
            for: [WorkspaceAgentDisplayCandidate(projectPath: projectPath, paneID: paneID, signalState: .running)],
            runtimeState: .init(),
            now: evaluationTime
        ) { _, _ in
            CodexAgentDisplaySnapshot(
                recentTextWindow: "/model to change",
                lastActivityAt: activityTime
            )
        }

        XCTAssertEqual(
            evaluation.overridesByProjectPath[projectPath]?[paneID],
            WorkspaceAgentPresentationOverride(
                state: .waiting,
                phase: .awaitingInput,
                attention: .input,
                summary: nil
            )
        )
        XCTAssertNil(evaluation.nextRefreshDeadline)
    }

    func testWaitingSignalTemporaryRunningOverrideExpiresAtDeadline() {
        let projectPath = "/tmp/project"
        let paneID = "pane-1"
        let activityTime = Date(timeIntervalSinceReferenceDate: 100)

        let beforeDeadline = CodexAgentDisplayStateRefresher.evaluate(
            for: [WorkspaceAgentDisplayCandidate(projectPath: projectPath, paneID: paneID, signalState: .waiting)],
            runtimeState: .init(),
            now: activityTime.addingTimeInterval(1)
        ) { _, _ in
            CodexAgentDisplaySnapshot(
                recentTextWindow: "transient output",
                lastActivityAt: activityTime
            )
        }

        XCTAssertEqual(
            beforeDeadline.overridesByProjectPath[projectPath]?[paneID],
            WorkspaceAgentPresentationOverride(
                state: .running,
                phase: .thinking,
                attention: WorkspaceAgentAttentionRequirement.none,
                summary: nil
            )
        )
        XCTAssertEqual(
            beforeDeadline.nextRefreshDeadline,
            activityTime.addingTimeInterval(CodexAgentDisplayStateRefresher.recentActivityWindow)
        )

        let afterDeadline = CodexAgentDisplayStateRefresher.evaluate(
            for: [WorkspaceAgentDisplayCandidate(projectPath: projectPath, paneID: paneID, signalState: .waiting)],
            runtimeState: beforeDeadline.runtimeState,
            now: activityTime.addingTimeInterval(2.1)
        ) { _, _ in
            CodexAgentDisplaySnapshot(
                recentTextWindow: "transient output",
                lastActivityAt: activityTime
            )
        }

        XCTAssertNil(afterDeadline.overridesByProjectPath[projectPath]?[paneID])
        XCTAssertNil(afterDeadline.nextRefreshDeadline)
    }

    func testRecentSignalWinsBeforeFallbackWindowOpens() {
        let projectPath = "/tmp/project"
        let paneID = "pane-1"
        let signalUpdatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let evaluationTime = signalUpdatedAt.addingTimeInterval(0.2)

        let evaluation = CodexAgentDisplayStateRefresher.evaluate(
            for: [
                WorkspaceAgentDisplayCandidate(
                    projectPath: projectPath,
                    paneID: paneID,
                    signalState: .waiting,
                    signalUpdatedAt: signalUpdatedAt
                )
            ],
            runtimeState: .init(),
            now: evaluationTime
        ) { _, _ in
            CodexAgentDisplaySnapshot(
                recentTextWindow: "transient output",
                lastActivityAt: signalUpdatedAt
            )
        }

        XCTAssertNil(evaluation.overridesByProjectPath[projectPath]?[paneID])
        XCTAssertEqual(
            evaluation.nextRefreshDeadline,
            signalUpdatedAt.addingTimeInterval(CodexAgentDisplayStateRefresher.minimumSignalPriorityWindow)
        )
    }

    func testUserActionAttentionDisablesVisibleTextFallback() {
        let projectPath = "/tmp/project"
        let paneID = "pane-1"
        let signalTime = Date(timeIntervalSinceReferenceDate: 100)

        let evaluation = CodexAgentDisplayStateRefresher.evaluate(
            for: [
                WorkspaceAgentDisplayCandidate(
                    projectPath: projectPath,
                    paneID: paneID,
                    signalState: .waiting,
                    signalPhase: .awaitingInput,
                    signalAttention: .input,
                    signalUpdatedAt: signalTime
                )
            ],
            runtimeState: .init(),
            now: signalTime.addingTimeInterval(5)
        ) { _, _ in
            CodexAgentDisplaySnapshot(
                recentTextWindow: "transient output",
                lastActivityAt: signalTime
            )
        }

        XCTAssertTrue(evaluation.overridesByProjectPath.isEmpty)
        XCTAssertNil(evaluation.nextRefreshDeadline)
    }

    func testUserActionAttentionAllowsFallbackAfterPostSignalActivity() {
        let projectPath = "/tmp/project"
        let paneID = "pane-1"
        let signalTime = Date(timeIntervalSinceReferenceDate: 100)
        let activityTime = signalTime.addingTimeInterval(3)

        let evaluation = CodexAgentDisplayStateRefresher.evaluate(
            for: [
                WorkspaceAgentDisplayCandidate(
                    projectPath: projectPath,
                    paneID: paneID,
                    signalState: .waiting,
                    signalPhase: .awaitingInput,
                    signalAttention: .input,
                    signalUpdatedAt: signalTime
                )
            ],
            runtimeState: .init(),
            now: activityTime.addingTimeInterval(1)
        ) { _, _ in
            CodexAgentDisplaySnapshot(
                recentTextWindow: "Called siyuan.siyuan_update_block",
                lastActivityAt: activityTime
            )
        }

        XCTAssertEqual(
            evaluation.overridesByProjectPath[projectPath]?[paneID],
            WorkspaceAgentPresentationOverride(
                state: .running,
                phase: .thinking,
                attention: WorkspaceAgentAttentionRequirement.none,
                summary: nil
            )
        )
        XCTAssertEqual(
            evaluation.nextRefreshDeadline,
            activityTime.addingTimeInterval(CodexAgentDisplayStateRefresher.recentActivityWindow)
        )
    }

    func testRunningToolPhaseIsPreservedWhenWaitingSignalFallsBackToRunning() {
        let projectPath = "/tmp/project"
        let paneID = "pane-1"
        let activityTime = Date(timeIntervalSinceReferenceDate: 100)

        let evaluation = CodexAgentDisplayStateRefresher.evaluate(
            for: [
                WorkspaceAgentDisplayCandidate(
                    projectPath: projectPath,
                    paneID: paneID,
                    signalState: .waiting,
                    signalPhase: .runningTool,
                    signalAttention: WorkspaceAgentAttentionRequirement.none
                )
            ],
            runtimeState: .init(),
            now: activityTime.addingTimeInterval(1)
        ) { _, _ in
            CodexAgentDisplaySnapshot(
                recentTextWindow: "Working (12s) esc to interrupt",
                lastActivityAt: activityTime
            )
        }

        XCTAssertEqual(
            evaluation.overridesByProjectPath[projectPath]?[paneID],
            WorkspaceAgentPresentationOverride(
                state: .running,
                phase: .runningTool,
                attention: WorkspaceAgentAttentionRequirement.none,
                summary: nil
            )
        )
    }
}
