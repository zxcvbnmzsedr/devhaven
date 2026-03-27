import Foundation

public struct WorkspaceGitLogFilterState: Equatable, Sendable {
    public var searchText: String
    public var revision: String?
    public var author: String?
    public var dateFilter: WorkspaceGitDateFilter
    public var path: String?

    public init(
        searchText: String = "",
        revision: String? = nil,
        author: String? = nil,
        dateFilter: WorkspaceGitDateFilter = .all,
        path: String? = nil
    ) {
        self.searchText = searchText
        self.revision = revision
        self.author = author
        self.dateFilter = dateFilter
        self.path = path
    }

    public var hasActiveFilters: Bool {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !normalizedSearch.isEmpty
            || revision != nil
            || author != nil
            || dateFilter != .all
            || !normalizedPath.isEmpty
    }

    public var query: WorkspaceGitLogQuery {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return WorkspaceGitLogQuery(
            revision: revision,
            searchTerm: normalizedSearch.isEmpty ? nil : normalizedSearch,
            author: author,
            since: dateFilter.gitSinceExpression,
            path: normalizedPath.isEmpty ? nil : normalizedPath
        )
    }
}
