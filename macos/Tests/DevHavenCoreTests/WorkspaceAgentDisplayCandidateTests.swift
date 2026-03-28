import XCTest
import DevHavenCore

final class WorkspaceAgentDisplayCandidateTests: XCTestCase {
    func testObservationStableSortedNormalizesDictionaryOrderNoise() {
        let lhs = WorkspaceAgentDisplayCandidate.observationStableSorted(
            [
                WorkspaceAgentDisplayCandidate(
                    projectPath: "/tmp/b",
                    paneID: "pane-2",
                    signalState: .waiting
                ),
                WorkspaceAgentDisplayCandidate(
                    projectPath: "/tmp/a",
                    paneID: "pane-3",
                    signalState: .running
                ),
                WorkspaceAgentDisplayCandidate(
                    projectPath: "/tmp/a",
                    paneID: "pane-1",
                    signalState: .waiting
                ),
            ]
        )

        let rhs = WorkspaceAgentDisplayCandidate.observationStableSorted(
            [
                WorkspaceAgentDisplayCandidate(
                    projectPath: "/tmp/a",
                    paneID: "pane-1",
                    signalState: .waiting
                ),
                WorkspaceAgentDisplayCandidate(
                    projectPath: "/tmp/b",
                    paneID: "pane-2",
                    signalState: .waiting
                ),
                WorkspaceAgentDisplayCandidate(
                    projectPath: "/tmp/a",
                    paneID: "pane-3",
                    signalState: .running
                ),
            ]
        )

        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(
            lhs.map { "\($0.projectPath)|\($0.paneID)|\($0.signalState.rawValue)" },
            [
                "/tmp/a|pane-1|waiting",
                "/tmp/a|pane-3|running",
                "/tmp/b|pane-2|waiting",
            ]
        )
    }
}
