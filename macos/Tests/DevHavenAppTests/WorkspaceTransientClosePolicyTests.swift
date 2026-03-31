import XCTest
import DevHavenCore
@testable import DevHavenApp

final class WorkspaceTransientClosePolicyTests: XCTestCase {
    func testLastTerminalTabClosesQuickTerminalWorkspace() {
        XCTAssertTrue(
            WorkspaceTransientClosePolicy.shouldCloseWorkspace(
                for: .tab,
                project: .quickTerminal(at: "/Users/tester"),
                terminalTabCount: 1,
                hasEditorTabs: false,
                hasDiffTabs: false
            )
        )
    }

    func testLastTerminalTabDoesNotCloseWhenEditorTabStillExists() {
        XCTAssertFalse(
            WorkspaceTransientClosePolicy.shouldCloseWorkspace(
                for: .tab,
                project: .workspaceRoot(name: "支付链路", path: "/tmp/workspace-root"),
                terminalTabCount: 1,
                hasEditorTabs: true,
                hasDiffTabs: false
            )
        )
    }

    func testRegularProjectNeverClosesWholeWorkspaceFromTerminalClose() {
        XCTAssertFalse(
            WorkspaceTransientClosePolicy.shouldCloseWorkspace(
                for: .tab,
                project: regularProject(path: "/tmp/project"),
                terminalTabCount: 1,
                hasEditorTabs: false,
                hasDiffTabs: false
            )
        )
    }

    private func regularProject(path: String) -> Project {
        Project(
            id: path,
            name: "Regular",
            path: path,
            tags: [],
            runConfigurations: [],
            worktrees: [],
            mtime: 0,
            size: 0,
            checksum: "",
            isGitRepository: true,
            gitCommits: 0,
            gitLastCommit: 0,
            gitLastCommitMessage: nil,
            gitDaily: nil,
            notesSummary: nil,
            created: 0,
            checked: 0
        )
    }
}
