import Foundation

public enum WorkspaceGitLogColumn: String, CaseIterable, Identifiable, Sendable {
    case subject
    case author
    case date
    case hash

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .subject:
            return "提交"
        case .author:
            return "作者"
        case .date:
            return "时间"
        case .hash:
            return "哈希"
        }
    }

    public static var defaultColumns: [WorkspaceGitLogColumn] {
        [.subject, .author, .date, .hash]
    }
}

public struct WorkspaceGitLogDisplayOptions: Equatable, Sendable {
    public var visibleColumns: [WorkspaceGitLogColumn]
    public var showsDetails: Bool
    public var showsDiffPreview: Bool

    public init(
        visibleColumns: [WorkspaceGitLogColumn] = WorkspaceGitLogColumn.defaultColumns,
        showsDetails: Bool = true,
        showsDiffPreview: Bool = true
    ) {
        self.visibleColumns = visibleColumns
        self.showsDetails = showsDetails
        self.showsDiffPreview = showsDiffPreview
    }
}

public struct WorkspaceGitLogTableRow: Equatable, Sendable, Identifiable {
    public var id: String { commit.id }
    public var commit: WorkspaceGitCommitSummary
    public var graphRow: WorkspaceGitCommitGraphVisibleRow
    public var decorationBadges: [String]
    public var formattedDateText: String
    public var isHighlightedOnCurrentBranch: Bool

    public init(
        commit: WorkspaceGitCommitSummary,
        graphRow: WorkspaceGitCommitGraphVisibleRow,
        decorationBadges: [String] = [],
        formattedDateText: String = "",
        isHighlightedOnCurrentBranch: Bool = false
    ) {
        self.commit = commit
        self.graphRow = graphRow
        self.decorationBadges = decorationBadges
        self.formattedDateText = formattedDateText
        self.isHighlightedOnCurrentBranch = isHighlightedOnCurrentBranch
    }
}
