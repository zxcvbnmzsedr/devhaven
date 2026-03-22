import XCTest
@testable import DevHavenApp
@testable import DevHavenCore

final class WorkspaceAgentStatusAccessoryTests: XCTestCase {
    func testWaitingStateUsesAttentionAccessory() {
        let accessory = WorkspaceAgentStatusAccessory(
            agentState: .waiting,
            agentKind: .claude
        )

        XCTAssertEqual(accessory?.symbolName, "exclamationmark.circle.fill")
        XCTAssertEqual(accessory?.label, "Claude 等待处理")
    }

    func testCodexWaitingStateUsesInputAccessoryLabel() {
        let accessory = WorkspaceAgentStatusAccessory(
            agentState: .waiting,
            agentKind: .codex
        )

        XCTAssertEqual(accessory?.symbolName, "exclamationmark.circle.fill")
        XCTAssertEqual(accessory?.label, "Codex 等待输入")
    }

    func testRunningStateUsesBoltAccessory() {
        let accessory = WorkspaceAgentStatusAccessory(
            agentState: .running,
            agentKind: .codex
        )

        XCTAssertEqual(accessory?.symbolName, "bolt.fill")
        XCTAssertEqual(accessory?.label, "Codex 正在运行")
    }

    func testIdleStateDoesNotProduceAccessory() {
        XCTAssertNil(
            WorkspaceAgentStatusAccessory(
                agentState: .idle,
                agentKind: .claude
            )
        )
    }
}
