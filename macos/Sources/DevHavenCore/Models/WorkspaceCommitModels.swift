import Foundation

public struct WorkspaceCommitRepositoryContext: Equatable, Sendable {
    public var rootProjectPath: String
    public var repositoryPath: String
    public var executionPath: String

    public init(rootProjectPath: String, repositoryPath: String, executionPath: String) {
        self.rootProjectPath = rootProjectPath
        self.repositoryPath = repositoryPath
        self.executionPath = executionPath
    }
}

public enum WorkspaceCommitChangeStatus: String, Equatable, Sendable {
    case added
    case modified
    case deleted
    case renamed
    case copied
    case unmerged
    case unknown
}

public enum WorkspaceCommitChangeGroup: String, Equatable, Sendable {
    case staged
    case unstaged
    case untracked
    case conflicted
}

public struct WorkspaceCommitChange: Equatable, Sendable, Identifiable {
    public var id: String { "\(path)|\(oldPath ?? "")|\(status.rawValue)|\(group.rawValue)" }
    public var path: String
    public var oldPath: String?
    public var status: WorkspaceCommitChangeStatus
    public var group: WorkspaceCommitChangeGroup
    public var isIncludedByDefault: Bool

    public init(
        path: String,
        oldPath: String? = nil,
        status: WorkspaceCommitChangeStatus,
        group: WorkspaceCommitChangeGroup,
        isIncludedByDefault: Bool
    ) {
        self.path = path
        self.oldPath = oldPath
        self.status = status
        self.group = group
        self.isIncludedByDefault = isIncludedByDefault
    }
}

public struct WorkspaceCommitChangesSnapshot: Equatable, Sendable {
    public var branchName: String?
    public var changes: [WorkspaceCommitChange]

    public init(branchName: String?, changes: [WorkspaceCommitChange]) {
        self.branchName = branchName
        self.changes = changes
    }

    public static func fromGitWorkingTree(_ snapshot: WorkspaceGitWorkingTreeSnapshot) -> WorkspaceCommitChangesSnapshot {
        var items: [WorkspaceCommitChange] = []
        items.append(contentsOf: map(snapshot.staged, group: .staged, includedByDefault: true))
        items.append(contentsOf: map(snapshot.unstaged, group: .unstaged, includedByDefault: false))
        items.append(contentsOf: map(snapshot.untracked, group: .untracked, includedByDefault: false))
        items.append(contentsOf: map(snapshot.conflicted, group: .conflicted, includedByDefault: false))
        return WorkspaceCommitChangesSnapshot(branchName: snapshot.branchName, changes: items)
    }

    private static func map(
        _ statuses: [WorkspaceGitFileStatus],
        group: WorkspaceCommitChangeGroup,
        includedByDefault: Bool
    ) -> [WorkspaceCommitChange] {
        statuses.map { status in
            WorkspaceCommitChange(
                path: status.path,
                oldPath: status.originalPath,
                status: map(status),
                group: group,
                isIncludedByDefault: includedByDefault
            )
        }
    }

    private static func map(_ status: WorkspaceGitFileStatus) -> WorkspaceCommitChangeStatus {
        if status.kind == .renamed {
            return .renamed
        }

        if status.kind == .unmerged {
            return .unmerged
        }

        let code = status.indexStatus ?? status.workTreeStatus ?? ""
        if code == "A" {
            return .added
        }
        if code == "D" {
            return .deleted
        }
        if code == "R" {
            return .renamed
        }
        if code == "C" {
            return .copied
        }
        if code == "M" {
            return .modified
        }
        return .unknown
    }
}

public struct WorkspaceCommitDiffPreviewState: Equatable, Sendable {
    public var path: String?
    public var content: String
    public var isLoading: Bool
    public var errorMessage: String?

    public init(path: String?, content: String, isLoading: Bool, errorMessage: String?) {
        self.path = path
        self.content = content
        self.isLoading = isLoading
        self.errorMessage = errorMessage
    }

    public static let idle = WorkspaceCommitDiffPreviewState(
        path: nil,
        content: "",
        isLoading: false,
        errorMessage: nil
    )
}

public struct WorkspaceCommitOptionsState: Equatable, Sendable {
    public var isAmend: Bool
    public var isSignOff: Bool
    public var author: String?

    public init(
        isAmend: Bool = false,
        isSignOff: Bool = false,
        author: String? = nil
    ) {
        self.isAmend = isAmend
        self.isSignOff = isSignOff
        self.author = author
    }
}

public enum WorkspaceCommitAction: String, Equatable, Sendable {
    case commit
    case commitAndPush
}

public struct WorkspaceCommitExecutionRequest: Equatable, Sendable {
    public var action: WorkspaceCommitAction
    public var message: String
    public var includedPaths: [String]
    public var options: WorkspaceCommitOptionsState

    public init(
        action: WorkspaceCommitAction,
        message: String,
        includedPaths: [String],
        options: WorkspaceCommitOptionsState
    ) {
        self.action = action
        self.message = message
        self.includedPaths = includedPaths
        self.options = options
    }
}

public enum WorkspaceCommitExecutionState: Equatable, Sendable {
    case idle
    case running(WorkspaceCommitAction)
    case succeeded(WorkspaceCommitAction)
    case failed(String)
}
