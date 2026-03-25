import Foundation

public enum WorkspacePrimaryMode: String, CaseIterable, Identifiable, Sendable {
    case terminal
    case git

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .terminal:
            return "终端"
        case .git:
            return "Git"
        }
    }
}

public enum WorkspaceGitSection: String, CaseIterable, Identifiable, Sendable {
    case log
    case changes
    case branches
    case operations

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .log:
            return "日志"
        case .changes:
            return "变更"
        case .branches:
            return "分支"
        case .operations:
            return "操作"
        }
    }
}

public struct WorkspaceGitRepositoryContext: Equatable, Sendable {
    public var rootProjectPath: String
    public var repositoryPath: String

    public init(rootProjectPath: String, repositoryPath: String) {
        self.rootProjectPath = rootProjectPath
        self.repositoryPath = repositoryPath
    }
}

public struct WorkspaceGitWorktreeContext: Equatable, Sendable, Identifiable {
    public var id: String { path }
    public var path: String
    public var displayName: String
    public var branchName: String?
    public var isRootProject: Bool

    public init(path: String, displayName: String, branchName: String?, isRootProject: Bool) {
        self.path = path
        self.displayName = displayName
        self.branchName = branchName
        self.isRootProject = isRootProject
    }
}

public struct WorkspaceGitLogQuery: Equatable, Sendable {
    public static let defaultLimit = 300

    public var limit: Int
    public var revision: String?
    public var searchTerm: String?
    public var author: String?
    public var since: String?
    public var path: String?

    public init(
        limit: Int = WorkspaceGitLogQuery.defaultLimit,
        revision: String? = nil,
        searchTerm: String? = nil,
        author: String? = nil,
        since: String? = nil,
        path: String? = nil
    ) {
        self.limit = max(1, limit)
        self.revision = revision
        self.searchTerm = searchTerm
        self.author = author
        self.since = since
        self.path = path
    }
}

public enum WorkspaceGitDateFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case last24Hours
    case last7Days
    case last30Days

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all:
            return "全部时间"
        case .last24Hours:
            return "24 小时"
        case .last7Days:
            return "7 天"
        case .last30Days:
            return "30 天"
        }
    }

    public var gitSinceExpression: String? {
        switch self {
        case .all:
            return nil
        case .last24Hours:
            return "24 hours ago"
        case .last7Days:
            return "7 days ago"
        case .last30Days:
            return "30 days ago"
        }
    }
}

public struct WorkspaceGitCommitSummary: Equatable, Sendable, Identifiable {
    public var id: String { hash }
    public var hash: String
    public var shortHash: String
    public var graphPrefix: String
    public var parentHashes: [String]
    public var authorName: String
    public var authorEmail: String
    public var authorTimestamp: TimeInterval
    public var subject: String
    public var decorations: String?

    public init(
        hash: String,
        shortHash: String,
        graphPrefix: String,
        parentHashes: [String],
        authorName: String,
        authorEmail: String,
        authorTimestamp: TimeInterval,
        subject: String,
        decorations: String?
    ) {
        self.hash = hash
        self.shortHash = shortHash
        self.graphPrefix = graphPrefix
        self.parentHashes = parentHashes
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.authorTimestamp = authorTimestamp
        self.subject = subject
        self.decorations = decorations
    }
}

public enum WorkspaceGitCommitFileStatus: String, Equatable, Sendable {
    case added
    case modified
    case deleted
    case renamed
    case copied
    case typeChanged
    case unmerged
    case unknown
}

public struct WorkspaceGitCommitFileChange: Equatable, Sendable, Identifiable {
    public var id: String { "\(path)|\(oldPath ?? "")|\(status.rawValue)" }
    public var path: String
    public var oldPath: String?
    public var status: WorkspaceGitCommitFileStatus

    public init(path: String, oldPath: String? = nil, status: WorkspaceGitCommitFileStatus) {
        self.path = path
        self.oldPath = oldPath
        self.status = status
    }
}

public struct WorkspaceGitCommitDetail: Equatable, Sendable, Identifiable {
    public var id: String { hash }
    public var hash: String
    public var shortHash: String
    public var parentHashes: [String]
    public var authorName: String
    public var authorEmail: String
    public var authorTimestamp: TimeInterval
    public var subject: String
    public var body: String?
    public var decorations: String?
    public var changedFiles: [WorkspaceGitCommitFileChange]
    public var diff: String

    public var files: [WorkspaceGitCommitFileChange] {
        changedFiles
    }

    public init(
        hash: String,
        shortHash: String,
        parentHashes: [String],
        authorName: String,
        authorEmail: String,
        authorTimestamp: TimeInterval,
        subject: String,
        body: String?,
        decorations: String?,
        changedFiles: [WorkspaceGitCommitFileChange],
        diff: String = ""
    ) {
        self.hash = hash
        self.shortHash = shortHash
        self.parentHashes = parentHashes
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.authorTimestamp = authorTimestamp
        self.subject = subject
        self.body = body
        self.decorations = decorations
        self.changedFiles = changedFiles
        self.diff = diff
    }
}

public enum WorkspaceGitBranchKind: String, Equatable, Sendable {
    case local
    case remote
}

public struct WorkspaceGitBranchSnapshot: Equatable, Sendable, Identifiable {
    public var id: String { fullName }
    public var name: String
    public var fullName: String
    public var hash: String
    public var kind: WorkspaceGitBranchKind
    public var isCurrent: Bool
    public var upstream: String?

    public init(
        name: String,
        fullName: String,
        hash: String,
        kind: WorkspaceGitBranchKind,
        isCurrent: Bool,
        upstream: String? = nil
    ) {
        self.name = name
        self.fullName = fullName
        self.hash = hash
        self.kind = kind
        self.isCurrent = isCurrent
        self.upstream = upstream
    }
}

public struct WorkspaceGitTagSnapshot: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var hash: String

    public init(name: String, hash: String) {
        self.name = name
        self.hash = hash
    }
}

public struct WorkspaceGitRefsSnapshot: Equatable, Sendable {
    public var localBranches: [WorkspaceGitBranchSnapshot]
    public var remoteBranches: [WorkspaceGitBranchSnapshot]
    public var tags: [WorkspaceGitTagSnapshot]

    public init(localBranches: [WorkspaceGitBranchSnapshot], remoteBranches: [WorkspaceGitBranchSnapshot], tags: [WorkspaceGitTagSnapshot]) {
        self.localBranches = localBranches
        self.remoteBranches = remoteBranches
        self.tags = tags
    }
}

public struct WorkspaceGitLogSnapshot: Equatable, Sendable {
    public var refs: WorkspaceGitRefsSnapshot
    public var commits: [WorkspaceGitCommitSummary]

    public init(refs: WorkspaceGitRefsSnapshot, commits: [WorkspaceGitCommitSummary]) {
        self.refs = refs
        self.commits = commits
    }
}

public struct WorkspaceGitFileStatus: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        case tracked
        case renamed
        case untracked
        case unmerged
        case ignored
    }

    public var id: String { "\(path)|\(originalPath ?? "")|\(indexStatus ?? "")|\(workTreeStatus ?? "")" }
    public var path: String
    public var originalPath: String?
    public var indexStatus: String?
    public var workTreeStatus: String?
    public var kind: Kind

    public init(
        path: String,
        originalPath: String? = nil,
        indexStatus: String? = nil,
        workTreeStatus: String? = nil,
        kind: Kind
    ) {
        self.path = path
        self.originalPath = originalPath
        self.indexStatus = indexStatus
        self.workTreeStatus = workTreeStatus
        self.kind = kind
    }
}

public struct WorkspaceGitWorkingTreeSnapshot: Equatable, Sendable {
    public var headOID: String?
    public var branchName: String?
    public var isDetachedHead: Bool
    public var isEmptyRepository: Bool
    public var upstreamBranch: String?
    public var aheadCount: Int
    public var behindCount: Int
    public var staged: [WorkspaceGitFileStatus]
    public var unstaged: [WorkspaceGitFileStatus]
    public var untracked: [WorkspaceGitFileStatus]
    public var conflicted: [WorkspaceGitFileStatus]

    public var hasUpstream: Bool { upstreamBranch != nil }
    public var headName: String {
        isDetachedHead ? "HEAD" : (branchName ?? "HEAD")
    }
    public var upstreamName: String? {
        upstreamBranch
    }

    public init(
        headOID: String?,
        branchName: String?,
        isDetachedHead: Bool,
        isEmptyRepository: Bool,
        upstreamBranch: String?,
        aheadCount: Int,
        behindCount: Int,
        staged: [WorkspaceGitFileStatus],
        unstaged: [WorkspaceGitFileStatus],
        untracked: [WorkspaceGitFileStatus],
        conflicted: [WorkspaceGitFileStatus]
    ) {
        self.headOID = headOID
        self.branchName = branchName
        self.isDetachedHead = isDetachedHead
        self.isEmptyRepository = isEmptyRepository
        self.upstreamBranch = upstreamBranch
        self.aheadCount = aheadCount
        self.behindCount = behindCount
        self.staged = staged
        self.unstaged = unstaged
        self.untracked = untracked
        self.conflicted = conflicted
    }
}

public struct WorkspaceGitRemoteSnapshot: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var fetchURL: String?
    public var pushURL: String?

    public init(name: String, fetchURL: String?, pushURL: String?) {
        self.name = name
        self.fetchURL = fetchURL
        self.pushURL = pushURL
    }
}

public struct WorkspaceGitAheadBehindSnapshot: Equatable, Sendable {
    public var upstream: String?
    public var ahead: Int
    public var behind: Int

    public var hasUpstream: Bool { upstream != nil }

    public init(upstream: String?, ahead: Int, behind: Int) {
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
    }
}

public enum WorkspaceGitOperationState: Equatable, Sendable {
    case idle
    case merging
    case rebasing
    case cherryPicking
}

public enum WorkspaceGitMutationKind: String, Equatable, Sendable {
    case stage
    case unstage
    case stageAll
    case unstageAll
    case discard
    case commit
    case amend
    case createBranch
    case checkoutBranch
    case deleteLocalBranch
    case fetch
    case pull
    case push
    case abortOperation
}

public enum WorkspaceGitCommandError: LocalizedError, Equatable, Sendable {
    case invalidRepository(String)
    case parseFailure(String)
    case operationRejected(String)
    case interactionRequired(command: String, reason: String)
    case commandFailed(command: String, message: String)
    case timedOut(command: String, timeout: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case let .invalidRepository(message):
            return message
        case let .parseFailure(message):
            return message
        case let .operationRejected(message):
            return message
        case let .interactionRequired(command, reason):
            return "命令需要交互处理（\(command)）：\(reason)"
        case let .commandFailed(command, message):
            return "命令执行失败（\(command)）：\(message)"
        case let .timedOut(command, timeout):
            return "命令超时（\(command)，\(Int(timeout)) 秒）"
        }
    }
}
