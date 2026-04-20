import Foundation

struct WorkspaceAlignmentStatusProbe: Sendable {
    let projectPath: String
    let targetBranch: String
    let managedWorktreePath: String
    let branches: [NativeGitBranch]
    let worktrees: [NativeGitWorktree]
    let currentBranch: String

    var branchExists: Bool {
        branches.contains(where: { $0.name == targetBranch })
    }

    var occupiedTargetWorktree: NativeGitWorktree? {
        worktrees.first(where: { $0.branch == targetBranch })
    }

    var hasOccupiedTargetCheckout: Bool {
        currentBranch == targetBranch || occupiedTargetWorktree != nil
    }
}

struct WorkspaceAlignmentStatusResolver {
    func status(from probe: WorkspaceAlignmentStatusProbe) -> WorkspaceAlignmentMemberStatus {
        if probe.hasOccupiedTargetCheckout {
            return .aligned
        }

        if !probe.branchExists {
            return .branchMissing
        }

        return .currentBranch(probe.currentBranch)
    }
}
