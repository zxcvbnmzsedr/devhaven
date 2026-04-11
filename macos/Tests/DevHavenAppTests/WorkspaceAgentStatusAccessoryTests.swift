import XCTest
import DevHavenCore
@testable import DevHavenApp

final class WorkspaceAgentStatusAccessoryTests: XCTestCase {
    func testAttentionTakesPriorityOverGenericStateLabel() {
        let accessory = WorkspaceAgentStatusAccessory(
            agentState: .waiting,
            agentKind: .codex,
            agentPhase: .awaitingApproval,
            agentAttention: .approval
        )

        XCTAssertEqual(accessory?.symbolName, "exclamationmark.triangle.fill")
        XCTAssertEqual(accessory?.label, "Codex 等待审批")
        XCTAssertEqual(accessory?.state, .waiting)
    }

    func testRunningToolPhaseProducesSpecificLabel() {
        let accessory = WorkspaceAgentStatusAccessory(
            agentState: .running,
            agentKind: .claude,
            agentPhase: .runningTool,
            agentAttention: WorkspaceAgentAttentionRequirement.none
        )

        XCTAssertEqual(accessory?.symbolName, "wrench.and.screwdriver.fill")
        XCTAssertEqual(accessory?.label, "Claude 正在执行工具")
        XCTAssertEqual(accessory?.state, .running)
    }
}
