import Foundation

public enum WorkspaceGitHubSection: String, CaseIterable, Identifiable, Sendable {
    case pulls
    case issues
    case reviews

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pulls:
            return "Pull Requests"
        case .issues:
            return "Issues"
        case .reviews:
            return "Reviews"
        }
    }
}

public struct WorkspaceGitHubRepositoryContext: Equatable, Sendable {
    public var rootProjectPath: String
    public var repositoryPath: String
    public var remoteName: String
    public var remoteURL: String
    public var host: String
    public var owner: String
    public var name: String

    public var repositoryFullName: String {
        "\(owner)/\(name)"
    }

    public var repoSelector: String {
        if host.caseInsensitiveCompare("github.com") == .orderedSame {
            return repositoryFullName
        }
        return "\(host)/\(repositoryFullName)"
    }

    public init(
        rootProjectPath: String,
        repositoryPath: String,
        remoteName: String,
        remoteURL: String,
        host: String,
        owner: String,
        name: String
    ) {
        self.rootProjectPath = rootProjectPath
        self.repositoryPath = repositoryPath
        self.remoteName = remoteName
        self.remoteURL = remoteURL
        self.host = host
        self.owner = owner
        self.name = name
    }
}

public enum WorkspaceGitHubAuthState: String, Equatable, Sendable {
    case unknown
    case authenticated
    case unauthenticated
}

public struct WorkspaceGitHubAuthStatus: Equatable, Sendable {
    public var host: String
    public var state: WorkspaceGitHubAuthState
    public var activeLogin: String?
    public var gitProtocol: String?
    public var tokenSource: String?
    public var scopes: [String]

    public var isAuthenticated: Bool {
        state == .authenticated
    }

    public var summaryText: String {
        switch state {
        case .unknown:
            return "尚未检查 GitHub 登录状态"
        case .authenticated:
            if let activeLogin, !activeLogin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "已登录 GitHub：\(activeLogin)"
            }
            return "已登录 GitHub"
        case .unauthenticated:
            return "未登录 GitHub CLI"
        }
    }

    public init(
        host: String,
        state: WorkspaceGitHubAuthState,
        activeLogin: String? = nil,
        gitProtocol: String? = nil,
        tokenSource: String? = nil,
        scopes: [String] = []
    ) {
        self.host = host
        self.state = state
        self.activeLogin = activeLogin
        self.gitProtocol = gitProtocol
        self.tokenSource = tokenSource
        self.scopes = scopes
    }

    public static func unchecked(host: String) -> WorkspaceGitHubAuthStatus {
        WorkspaceGitHubAuthStatus(host: host, state: .unknown)
    }
}

public struct WorkspaceGitHubActor: Codable, Equatable, Hashable, Sendable {
    public var nodeID: String?
    public var login: String?
    public var name: String?
    public var isBot: Bool
    public var url: String?

    public var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        if let login, !login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return login
        }
        return "未知用户"
    }

    public init(
        nodeID: String? = nil,
        login: String? = nil,
        name: String? = nil,
        isBot: Bool = false,
        url: String? = nil
    ) {
        self.nodeID = nodeID
        self.login = login
        self.name = name
        self.isBot = isBot
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case nodeID = "id"
        case login
        case name
        case isBot
        case url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.nodeID = try container.decodeIfPresent(String.self, forKey: .nodeID)
        self.login = try container.decodeIfPresent(String.self, forKey: .login)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.isBot = try container.decodeIfPresent(Bool.self, forKey: .isBot) ?? false
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(nodeID, forKey: .nodeID)
        try container.encodeIfPresent(login, forKey: .login)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(isBot, forKey: .isBot)
        try container.encodeIfPresent(url, forKey: .url)
    }
}

public struct WorkspaceGitHubLabel: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var color: String?
    public var description: String?

    public init(name: String, color: String? = nil, description: String? = nil) {
        self.name = name
        self.color = color
        self.description = description
    }
}

public struct WorkspaceGitHubMilestone: Codable, Equatable, Sendable {
    public var title: String
    public var number: Int?
    public var description: String?
    public var dueOn: Date?

    public init(title: String, number: Int? = nil, description: String? = nil, dueOn: Date? = nil) {
        self.title = title
        self.number = number
        self.description = description
        self.dueOn = dueOn
    }
}

public struct WorkspaceGitHubComment: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var author: WorkspaceGitHubActor?
    public var authorAssociation: String?
    public var body: String
    public var createdAt: Date
    public var url: String

    public init(
        id: String,
        author: WorkspaceGitHubActor?,
        authorAssociation: String? = nil,
        body: String,
        createdAt: Date,
        url: String
    ) {
        self.id = id
        self.author = author
        self.authorAssociation = authorAssociation
        self.body = body
        self.createdAt = createdAt
        self.url = url
    }
}

public enum WorkspaceGitHubPullMergeMethod: String, CaseIterable, Identifiable, Sendable {
    case merge

    public var id: String { rawValue }

    public var ghArgument: String {
        switch self {
        case .merge:
            return "--merge"
        }
    }

    public var title: String {
        switch self {
        case .merge:
            return "Merge"
        }
    }
}

public enum WorkspaceGitHubReviewSubmissionEvent: String, CaseIterable, Identifiable, Sendable {
    case comment
    case approve
    case requestChanges

    public var id: String { rawValue }

    public var ghArgument: String {
        switch self {
        case .comment:
            return "--comment"
        case .approve:
            return "--approve"
        case .requestChanges:
            return "--request-changes"
        }
    }
}

public enum WorkspaceGitHubMutationKind: Equatable, Sendable {
    case addIssueComment
    case closeIssue
    case reopenIssue
    case createIssueBranch
    case createIssueWorktree
    case addPullComment
    case closePull
    case reopenPull
    case mergePull(WorkspaceGitHubPullMergeMethod)
    case checkoutPullBranch
    case submitReview(WorkspaceGitHubReviewSubmissionEvent)
}

public struct WorkspaceGitHubCommitAuthor: Codable, Equatable, Sendable {
    public var nodeID: String?
    public var login: String?
    public var name: String?
    public var email: String?

    public init(nodeID: String? = nil, login: String? = nil, name: String? = nil, email: String? = nil) {
        self.nodeID = nodeID
        self.login = login
        self.name = name
        self.email = email
    }

    private enum CodingKeys: String, CodingKey {
        case nodeID = "id"
        case login
        case name
        case email
    }
}

public struct WorkspaceGitHubCommitSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: String { oid }
    public var oid: String
    public var messageHeadline: String
    public var messageBody: String?
    public var authoredDate: Date?
    public var committedDate: Date?
    public var authors: [WorkspaceGitHubCommitAuthor]

    public init(
        oid: String,
        messageHeadline: String,
        messageBody: String? = nil,
        authoredDate: Date? = nil,
        committedDate: Date? = nil,
        authors: [WorkspaceGitHubCommitAuthor] = []
    ) {
        self.oid = oid
        self.messageHeadline = messageHeadline
        self.messageBody = messageBody
        self.authoredDate = authoredDate
        self.committedDate = committedDate
        self.authors = authors
    }
}

public enum WorkspaceGitHubPullState: Codable, Equatable, Sendable {
    case open
    case closed
    case merged
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "OPEN":
            self = .open
        case "CLOSED":
            self = .closed
        case "MERGED":
            self = .merged
        default:
            self = .unknown(rawValue)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .open:
            return "OPEN"
        case .closed:
            return "CLOSED"
        case .merged:
            return "MERGED"
        case let .unknown(value):
            return value
        }
    }
}

public enum WorkspaceGitHubIssueState: Codable, Equatable, Sendable {
    case open
    case closed
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "OPEN":
            self = .open
        case "CLOSED":
            self = .closed
        default:
            self = .unknown(rawValue)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .open:
            return "OPEN"
        case .closed:
            return "CLOSED"
        case let .unknown(value):
            return value
        }
    }
}

public enum WorkspaceGitHubIssueStateReason: Codable, Equatable, Sendable {
    case completed
    case notPlanned
    case reopened
    case none
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? ""
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch normalized {
        case "":
            self = .none
        case "COMPLETED":
            self = .completed
        case "NOT_PLANNED":
            self = .notPlanned
        case "REOPENED":
            self = .reopened
        default:
            self = .unknown(rawValue)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .completed:
            return "COMPLETED"
        case .notPlanned:
            return "NOT_PLANNED"
        case .reopened:
            return "REOPENED"
        case .none:
            return ""
        case let .unknown(value):
            return value
        }
    }
}

public enum WorkspaceGitHubReviewDecision: Codable, Equatable, Sendable {
    case none
    case approved
    case changesRequested
    case reviewRequired
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? ""
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch normalized {
        case "":
            self = .none
        case "APPROVED":
            self = .approved
        case "CHANGES_REQUESTED":
            self = .changesRequested
        case "REVIEW_REQUIRED":
            self = .reviewRequired
        default:
            self = .unknown(rawValue)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .none:
            return ""
        case .approved:
            return "APPROVED"
        case .changesRequested:
            return "CHANGES_REQUESTED"
        case .reviewRequired:
            return "REVIEW_REQUIRED"
        case let .unknown(value):
            return value
        }
    }
}

public enum WorkspaceGitHubMergeStateStatus: Codable, Equatable, Sendable {
    case clean
    case blocked
    case behind
    case dirty
    case draft
    case hasHooks
    case unstable
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "CLEAN":
            self = .clean
        case "BLOCKED":
            self = .blocked
        case "BEHIND":
            self = .behind
        case "DIRTY":
            self = .dirty
        case "DRAFT":
            self = .draft
        case "HAS_HOOKS":
            self = .hasHooks
        case "UNSTABLE":
            self = .unstable
        default:
            self = .unknown(rawValue)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .clean:
            return "CLEAN"
        case .blocked:
            return "BLOCKED"
        case .behind:
            return "BEHIND"
        case .dirty:
            return "DIRTY"
        case .draft:
            return "DRAFT"
        case .hasHooks:
            return "HAS_HOOKS"
        case .unstable:
            return "UNSTABLE"
        case let .unknown(value):
            return value
        }
    }
}

public struct WorkspaceGitHubPullSummary: Equatable, Sendable, Identifiable {
    public var id: String
    public var number: Int
    public var title: String
    public var state: WorkspaceGitHubPullState
    public var isDraft: Bool
    public var author: WorkspaceGitHubActor?
    public var assignees: [WorkspaceGitHubActor]
    public var labels: [WorkspaceGitHubLabel]
    public var commentsCount: Int
    public var reviewDecision: WorkspaceGitHubReviewDecision
    public var createdAt: Date
    public var updatedAt: Date
    public var url: String
    public var headRefName: String
    public var baseRefName: String

    public init(
        id: String,
        number: Int,
        title: String,
        state: WorkspaceGitHubPullState,
        isDraft: Bool,
        author: WorkspaceGitHubActor?,
        assignees: [WorkspaceGitHubActor] = [],
        labels: [WorkspaceGitHubLabel] = [],
        commentsCount: Int = 0,
        reviewDecision: WorkspaceGitHubReviewDecision = .none,
        createdAt: Date,
        updatedAt: Date,
        url: String,
        headRefName: String,
        baseRefName: String
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.state = state
        self.isDraft = isDraft
        self.author = author
        self.assignees = assignees
        self.labels = labels
        self.commentsCount = commentsCount
        self.reviewDecision = reviewDecision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.url = url
        self.headRefName = headRefName
        self.baseRefName = baseRefName
    }
}

public struct WorkspaceGitHubPullDetail: Equatable, Sendable, Identifiable {
    public var id: String
    public var number: Int
    public var title: String
    public var state: WorkspaceGitHubPullState
    public var isDraft: Bool
    public var author: WorkspaceGitHubActor?
    public var assignees: [WorkspaceGitHubActor]
    public var labels: [WorkspaceGitHubLabel]
    public var reviewDecision: WorkspaceGitHubReviewDecision
    public var mergeStateStatus: WorkspaceGitHubMergeStateStatus
    public var milestone: WorkspaceGitHubMilestone?
    public var body: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var mergedAt: Date?
    public var mergedBy: WorkspaceGitHubActor?
    public var url: String
    public var headRefName: String
    public var baseRefName: String
    public var changedFiles: Int
    public var comments: [WorkspaceGitHubComment]
    public var commits: [WorkspaceGitHubCommitSummary]

    public var commentsCount: Int {
        comments.count
    }

    public var commitCount: Int {
        commits.count
    }

    public init(
        id: String,
        number: Int,
        title: String,
        state: WorkspaceGitHubPullState,
        isDraft: Bool,
        author: WorkspaceGitHubActor?,
        assignees: [WorkspaceGitHubActor] = [],
        labels: [WorkspaceGitHubLabel] = [],
        reviewDecision: WorkspaceGitHubReviewDecision = .none,
        mergeStateStatus: WorkspaceGitHubMergeStateStatus = .unknown("UNKNOWN"),
        milestone: WorkspaceGitHubMilestone? = nil,
        body: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        mergedAt: Date? = nil,
        mergedBy: WorkspaceGitHubActor? = nil,
        url: String,
        headRefName: String,
        baseRefName: String,
        changedFiles: Int = 0,
        comments: [WorkspaceGitHubComment] = [],
        commits: [WorkspaceGitHubCommitSummary] = []
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.state = state
        self.isDraft = isDraft
        self.author = author
        self.assignees = assignees
        self.labels = labels
        self.reviewDecision = reviewDecision
        self.mergeStateStatus = mergeStateStatus
        self.milestone = milestone
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mergedAt = mergedAt
        self.mergedBy = mergedBy
        self.url = url
        self.headRefName = headRefName
        self.baseRefName = baseRefName
        self.changedFiles = changedFiles
        self.comments = comments
        self.commits = commits
    }
}

public struct WorkspaceGitHubIssueSummary: Equatable, Sendable, Identifiable {
    public var id: String
    public var number: Int
    public var title: String
    public var state: WorkspaceGitHubIssueState
    public var stateReason: WorkspaceGitHubIssueStateReason
    public var author: WorkspaceGitHubActor?
    public var assignees: [WorkspaceGitHubActor]
    public var labels: [WorkspaceGitHubLabel]
    public var commentsCount: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var url: String

    public init(
        id: String,
        number: Int,
        title: String,
        state: WorkspaceGitHubIssueState,
        stateReason: WorkspaceGitHubIssueStateReason = .none,
        author: WorkspaceGitHubActor?,
        assignees: [WorkspaceGitHubActor] = [],
        labels: [WorkspaceGitHubLabel] = [],
        commentsCount: Int = 0,
        createdAt: Date,
        updatedAt: Date,
        url: String
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.state = state
        self.stateReason = stateReason
        self.author = author
        self.assignees = assignees
        self.labels = labels
        self.commentsCount = commentsCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.url = url
    }

    public var suggestedBranchName: String {
        GitHubIssueBranchNameBuilder.suggestedBranchName(number: number, title: title)
    }
}

public struct WorkspaceGitHubIssueDetail: Equatable, Sendable, Identifiable {
    public var id: String
    public var number: Int
    public var title: String
    public var state: WorkspaceGitHubIssueState
    public var stateReason: WorkspaceGitHubIssueStateReason
    public var author: WorkspaceGitHubActor?
    public var assignees: [WorkspaceGitHubActor]
    public var labels: [WorkspaceGitHubLabel]
    public var milestone: WorkspaceGitHubMilestone?
    public var body: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var closedAt: Date?
    public var url: String
    public var comments: [WorkspaceGitHubComment]

    public var commentsCount: Int {
        comments.count
    }

    public var suggestedBranchName: String {
        GitHubIssueBranchNameBuilder.suggestedBranchName(number: number, title: title)
    }

    public init(
        id: String,
        number: Int,
        title: String,
        state: WorkspaceGitHubIssueState,
        stateReason: WorkspaceGitHubIssueStateReason = .none,
        author: WorkspaceGitHubActor?,
        assignees: [WorkspaceGitHubActor] = [],
        labels: [WorkspaceGitHubLabel] = [],
        milestone: WorkspaceGitHubMilestone? = nil,
        body: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        closedAt: Date? = nil,
        url: String,
        comments: [WorkspaceGitHubComment] = []
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.state = state
        self.stateReason = stateReason
        self.author = author
        self.assignees = assignees
        self.labels = labels
        self.milestone = milestone
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.closedAt = closedAt
        self.url = url
        self.comments = comments
    }
}

public enum GitHubIssueBranchNameBuilder {
    public static func suggestedBranchName(number: Int, title: String) -> String {
        let foldedTitle = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let slug = foldedTitle
            .replacingOccurrences(
                of: #"[^a-z0-9]+"#,
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let trimmedSlug = slug
            .split(separator: "-")
            .prefix(6)
            .joined(separator: "-")
        let fallbackSlug = trimmedSlug.isEmpty ? "issue" : trimmedSlug
        return "issue/\(number)-\(fallbackSlug)"
    }
}

public struct WorkspaceGitHubReviewRequestSummary: Equatable, Sendable, Identifiable {
    public var id: String
    public var number: Int
    public var title: String
    public var state: WorkspaceGitHubPullState
    public var isDraft: Bool
    public var author: WorkspaceGitHubActor?
    public var labels: [WorkspaceGitHubLabel]
    public var commentsCount: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var url: String

    public init(
        id: String,
        number: Int,
        title: String,
        state: WorkspaceGitHubPullState,
        isDraft: Bool,
        author: WorkspaceGitHubActor?,
        labels: [WorkspaceGitHubLabel] = [],
        commentsCount: Int = 0,
        createdAt: Date,
        updatedAt: Date,
        url: String
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.state = state
        self.isDraft = isDraft
        self.author = author
        self.labels = labels
        self.commentsCount = commentsCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.url = url
    }
}

public enum WorkspaceGitHubCommandError: LocalizedError, Equatable, Sendable {
    case invalidRepository(String)
    case unsupportedRemote(String)
    case authRequired(String)
    case parseFailure(String)
    case operationRejected(String)
    case commandFailed(command: String, message: String)
    case timedOut(command: String, timeout: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case let .invalidRepository(message):
            return message
        case let .unsupportedRemote(message):
            return message
        case let .authRequired(message):
            return message
        case let .parseFailure(message):
            return message
        case let .operationRejected(message):
            return message
        case let .commandFailed(command, message):
            return "GitHub 命令执行失败（\(command)）：\(message)"
        case let .timedOut(command, timeout):
            return "GitHub 命令超时（\(command)，\(Int(timeout)) 秒）"
        }
    }
}
