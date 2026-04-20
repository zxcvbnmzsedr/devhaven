import XCTest
@testable import DevHavenCore

final class WorkspaceAlignmentStatusResolverTests: XCTestCase {
    func testStatusIsAlignedWhenCurrentBranchAlreadyMatchesTarget() {
        let status = WorkspaceAlignmentStatusResolver().status(
            from: makeProbe(
                targetBranch: "feature/payment",
                branches: ["main", "feature/payment"],
                currentBranch: "feature/payment"
            )
        )

        XCTAssertEqual(status, .aligned)
    }

    func testStatusIsAlignedWhenTargetBranchIsCheckedOutInAnotherWorktree() {
        let status = WorkspaceAlignmentStatusResolver().status(
            from: makeProbe(
                targetBranch: "feature/payment",
                branches: ["main", "feature/payment"],
                worktrees: [
                    NativeGitWorktree(path: "/repo-feature-payment", branch: "feature/payment"),
                ],
                currentBranch: "main"
            )
        )

        XCTAssertEqual(status, .aligned)
    }

    func testStatusIsBranchMissingWhenNoTargetCheckoutAndBranchDoesNotExist() {
        let status = WorkspaceAlignmentStatusResolver().status(
            from: makeProbe(
                targetBranch: "feature/payment",
                branches: ["main"],
                currentBranch: "main"
            )
        )

        XCTAssertEqual(status, .branchMissing)
    }

    func testStatusReportsCurrentBranchWhenTargetBranchExistsButIsNotCheckedOut() {
        let status = WorkspaceAlignmentStatusResolver().status(
            from: makeProbe(
                targetBranch: "feature/payment",
                branches: ["main", "feature/payment"],
                currentBranch: "develop"
            )
        )

        XCTAssertEqual(status, .currentBranch("develop"))
    }

    private func makeProbe(
        targetBranch: String,
        branches: [String],
        worktrees: [NativeGitWorktree] = [],
        currentBranch: String
    ) -> WorkspaceAlignmentStatusProbe {
        WorkspaceAlignmentStatusProbe(
            projectPath: "/repo/project",
            targetBranch: targetBranch,
            managedWorktreePath: "/repo/project-\(targetBranch.replacingOccurrences(of: "/", with: "-"))",
            branches: branches.map { NativeGitBranch(name: $0, isMain: $0 == "main") },
            worktrees: worktrees,
            currentBranch: currentBranch
        )
    }
}
