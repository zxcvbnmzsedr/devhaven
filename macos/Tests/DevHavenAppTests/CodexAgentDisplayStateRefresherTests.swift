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
            WorkspaceAgentPresentationOverride(state: .waiting, summary: nil)
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
            WorkspaceAgentPresentationOverride(state: .running, summary: nil)
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
}
