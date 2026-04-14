import Foundation

public enum WorkspaceGitHubPullFilterState: String, CaseIterable, Identifiable, Sendable {
    case open
    case closed
    case merged
    case all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .open:
            return "Open"
        case .closed:
            return "Closed"
        case .merged:
            return "Merged"
        case .all:
            return "全部"
        }
    }

    var ghArgument: String {
        rawValue
    }
}

public enum WorkspaceGitHubIssueFilterState: String, CaseIterable, Identifiable, Sendable {
    case open
    case closed
    case all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .open:
            return "Open"
        case .closed:
            return "Closed"
        case .all:
            return "全部"
        }
    }

    var ghArgument: String {
        rawValue
    }
}

public enum WorkspaceGitHubReviewFilterState: String, CaseIterable, Identifiable, Sendable {
    case open
    case closed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .open:
            return "Open"
        case .closed:
            return "Closed"
        }
    }

    var ghArgument: String {
        rawValue
    }
}

public enum WorkspaceGitHubReviewScope: String, CaseIterable, Identifiable, Sendable {
    case requestedToMe
    case involvingMe

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .requestedToMe:
            return "请求我 Review"
        case .involvingMe:
            return "与我相关"
        }
    }
}

public struct WorkspaceGitHubPullFilter: Equatable, Sendable {
    public static let defaultLimit = 50

    public var limit: Int
    public var state: WorkspaceGitHubPullFilterState
    public var searchText: String
    public var author: String?
    public var assignee: String?
    public var labels: [String]
    public var baseBranch: String?
    public var headBranch: String?
    public var draftOnly: Bool
    public var authoredByMe: Bool
    public var assignedToMe: Bool

    public init(
        limit: Int = WorkspaceGitHubPullFilter.defaultLimit,
        state: WorkspaceGitHubPullFilterState = .open,
        searchText: String = "",
        author: String? = nil,
        assignee: String? = nil,
        labels: [String] = [],
        baseBranch: String? = nil,
        headBranch: String? = nil,
        draftOnly: Bool = false,
        authoredByMe: Bool = false,
        assignedToMe: Bool = false
    ) {
        self.limit = max(1, limit)
        self.state = state
        self.searchText = searchText
        self.author = author
        self.assignee = assignee
        self.labels = labels
        self.baseBranch = baseBranch
        self.headBranch = headBranch
        self.draftOnly = draftOnly
        self.authoredByMe = authoredByMe
        self.assignedToMe = assignedToMe
    }

    public var normalizedSearchText: String? {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var normalizedAuthor: String? {
        if authoredByMe {
            return "@me"
        }
        return author?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var normalizedAssignee: String? {
        if assignedToMe {
            return "@me"
        }
        return assignee?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var normalizedLabels: [String] {
        labels.compactMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
    }

    public var normalizedBaseBranch: String? {
        baseBranch?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var normalizedHeadBranch: String? {
        headBranch?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

public struct WorkspaceGitHubIssueFilter: Equatable, Sendable {
    public static let defaultLimit = 50

    public var limit: Int
    public var state: WorkspaceGitHubIssueFilterState
    public var searchText: String
    public var author: String?
    public var assignee: String?
    public var labels: [String]
    public var milestone: String?
    public var authoredByMe: Bool
    public var assignedToMe: Bool

    public init(
        limit: Int = WorkspaceGitHubIssueFilter.defaultLimit,
        state: WorkspaceGitHubIssueFilterState = .open,
        searchText: String = "",
        author: String? = nil,
        assignee: String? = nil,
        labels: [String] = [],
        milestone: String? = nil,
        authoredByMe: Bool = false,
        assignedToMe: Bool = false
    ) {
        self.limit = max(1, limit)
        self.state = state
        self.searchText = searchText
        self.author = author
        self.assignee = assignee
        self.labels = labels
        self.milestone = milestone
        self.authoredByMe = authoredByMe
        self.assignedToMe = assignedToMe
    }

    public var normalizedSearchText: String? {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var normalizedAuthor: String? {
        if authoredByMe {
            return "@me"
        }
        return author?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var normalizedAssignee: String? {
        if assignedToMe {
            return "@me"
        }
        return assignee?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var normalizedLabels: [String] {
        labels.compactMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
    }

    public var normalizedMilestone: String? {
        milestone?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

public struct WorkspaceGitHubReviewFilter: Equatable, Sendable {
    public static let defaultLimit = 50

    public var limit: Int
    public var state: WorkspaceGitHubReviewFilterState
    public var searchText: String
    public var author: String?
    public var labels: [String]
    public var scope: WorkspaceGitHubReviewScope

    public init(
        limit: Int = WorkspaceGitHubReviewFilter.defaultLimit,
        state: WorkspaceGitHubReviewFilterState = .open,
        searchText: String = "",
        author: String? = nil,
        labels: [String] = [],
        scope: WorkspaceGitHubReviewScope = .requestedToMe
    ) {
        self.limit = max(1, limit)
        self.state = state
        self.searchText = searchText
        self.author = author
        self.labels = labels
        self.scope = scope
    }

    public var normalizedSearchText: String? {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var normalizedAuthor: String? {
        author?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var normalizedLabels: [String] {
        labels.compactMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
