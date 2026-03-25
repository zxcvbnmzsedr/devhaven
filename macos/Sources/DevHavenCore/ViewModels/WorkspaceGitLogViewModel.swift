import Foundation
import Observation

@MainActor
@Observable
public final class WorkspaceGitLogViewModel {
    public struct Client: Sendable {
        public var loadLogSnapshot: @Sendable (String, WorkspaceGitLogQuery) throws -> WorkspaceGitLogSnapshot
        public var loadCommitDetail: @Sendable (String, String) throws -> WorkspaceGitCommitDetail
        public var loadFileDiffForCommit: @Sendable (String, String, String) throws -> String
        public var loadAuthorSuggestions: @Sendable (String, Int) throws -> [String]

        public init(
            loadLogSnapshot: @escaping @Sendable (String, WorkspaceGitLogQuery) throws -> WorkspaceGitLogSnapshot,
            loadCommitDetail: @escaping @Sendable (String, String) throws -> WorkspaceGitCommitDetail,
            loadFileDiffForCommit: @escaping @Sendable (String, String, String) throws -> String,
            loadAuthorSuggestions: @escaping @Sendable (String, Int) throws -> [String]
        ) {
            self.loadLogSnapshot = loadLogSnapshot
            self.loadCommitDetail = loadCommitDetail
            self.loadFileDiffForCommit = loadFileDiffForCommit
            self.loadAuthorSuggestions = loadAuthorSuggestions
        }

        public static func live(service: NativeGitRepositoryService) -> Client {
            Client(
                loadLogSnapshot: { try service.loadLogSnapshot(at: $0, query: $1) },
                loadCommitDetail: { try service.loadCommitDetail(at: $0, commitHash: $1) },
                loadFileDiffForCommit: { try service.loadDiffForCommitFile(at: $0, commitHash: $1, filePath: $2) },
                loadAuthorSuggestions: { try service.loadLogAuthors(at: $0, limit: $1) }
            )
        }
    }

    private struct ReadResult: Sendable {
        var snapshot: WorkspaceGitLogSnapshot
        var authors: [String]
    }

    @ObservationIgnored private let client: Client
    @ObservationIgnored private let graphVisibleModelBuilder: @Sendable ([WorkspaceGitCommitSummary]) -> WorkspaceGitCommitGraphVisibleModel
    @ObservationIgnored private var filterDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var readRevision = 0
    @ObservationIgnored private var commitDetailTask: Task<Void, Never>?
    @ObservationIgnored private var commitDetailRevision = 0
    @ObservationIgnored private var fileDiffTask: Task<Void, Never>?
    @ObservationIgnored private var fileDiffRevision = 0

    private nonisolated static let diffPreviewMaxBytes = 256 * 1024
    private nonisolated static let diffPreviewMaxLines = 2_000
    private nonisolated static let authorSuggestionLimit = 200

    public var repositoryContext: WorkspaceGitRepositoryContext
    public var displayOptions: WorkspaceGitLogDisplayOptions
    public var searchQuery: String
    public var debouncedSearchQuery: String
    public var pathFilterQuery: String
    public var debouncedPathFilterQuery: String
    public var selectedRevisionFilter: String?
    public var selectedAuthorFilter: String?
    public var selectedDateFilter: WorkspaceGitDateFilter
    public var availableAuthors: [String]
    public var logSnapshot: WorkspaceGitLogSnapshot
    public var graphVisibleModel: WorkspaceGitCommitGraphVisibleModel
    public var tableRows: [WorkspaceGitLogTableRow]
    public var preferredGraphWidth: Double
    public var selectedCommitHash: String?
    public var selectedCommitDetail: WorkspaceGitCommitDetail?
    public var selectedFilePath: String?
    public var selectedFileDiff: String
    public var selectedFileDiffNotice: String?
    public var isSelectedFileDiffTruncated: Bool
    public var isLoading: Bool
    public var isLoadingSelectedCommitDetail: Bool
    public var isLoadingSelectedFileDiff: Bool
    public var errorMessage: String?

    public init(
        repositoryContext: WorkspaceGitRepositoryContext,
        displayOptions: WorkspaceGitLogDisplayOptions = WorkspaceGitLogDisplayOptions(),
        client: Client,
        graphVisibleModelBuilder: @escaping @Sendable ([WorkspaceGitCommitSummary]) -> WorkspaceGitCommitGraphVisibleModel = WorkspaceGitCommitGraphBuilder.buildVisibleModel
    ) {
        self.client = client
        self.graphVisibleModelBuilder = graphVisibleModelBuilder
        self.repositoryContext = repositoryContext
        self.displayOptions = displayOptions
        self.searchQuery = ""
        self.debouncedSearchQuery = ""
        self.pathFilterQuery = ""
        self.debouncedPathFilterQuery = ""
        self.selectedRevisionFilter = nil
        self.selectedAuthorFilter = nil
        self.selectedDateFilter = .all
        self.availableAuthors = []
        let initialSnapshot = WorkspaceGitLogSnapshot(
            refs: WorkspaceGitRefsSnapshot(localBranches: [], remoteBranches: [], tags: []),
            commits: []
        )
        self.logSnapshot = initialSnapshot
        let initialGraphVisibleModel = graphVisibleModelBuilder(initialSnapshot.commits)
        self.graphVisibleModel = initialGraphVisibleModel
        self.tableRows = initialGraphVisibleModel.rows.map { row in
            WorkspaceGitLogTableRow(commit: row.commit, graphRow: row)
        }
        self.preferredGraphWidth = initialGraphVisibleModel.recommendedWidth
        self.selectedCommitHash = nil
        self.selectedCommitDetail = nil
        self.selectedFilePath = nil
        self.selectedFileDiff = ""
        self.selectedFileDiffNotice = nil
        self.isSelectedFileDiffTruncated = false
        self.isLoading = false
        self.isLoadingSelectedCommitDetail = false
        self.isLoadingSelectedFileDiff = false
        self.errorMessage = nil
    }

    deinit {
        filterDebounceTask?.cancel()
        readTask?.cancel()
        commitDetailTask?.cancel()
        fileDiffTask?.cancel()
    }

    public var filterState: WorkspaceGitLogFilterState {
        WorkspaceGitLogFilterState(
            searchText: debouncedSearchQuery,
            revision: selectedRevisionFilter,
            author: selectedAuthorFilter,
            dateFilter: selectedDateFilter,
            path: debouncedPathFilterQuery
        )
    }

    public func updateRepositoryContext(_ repositoryContext: WorkspaceGitRepositoryContext) {
        let pathChanged = self.repositoryContext.repositoryPath != repositoryContext.repositoryPath
        self.repositoryContext = repositoryContext
        guard pathChanged else {
            return
        }
        cancelPendingReads(resetSelection: true)
        refresh()
    }

    public func updateSearchQuery(_ query: String) {
        searchQuery = query
        scheduleFilterDebounce()
    }

    public func updatePathFilterQuery(_ query: String) {
        pathFilterQuery = query
        scheduleFilterDebounce()
    }

    public func selectRevisionFilter(_ revision: String?) {
        let normalized = Self.normalizedOptional(revision)
        guard selectedRevisionFilter != normalized else {
            return
        }
        selectedRevisionFilter = normalized
        refresh()
    }

    public func selectAuthorFilter(_ author: String?) {
        let normalized = Self.normalizedOptional(author)
        guard selectedAuthorFilter != normalized else {
            return
        }
        selectedAuthorFilter = normalized
        refresh()
    }

    public func selectDateFilter(_ filter: WorkspaceGitDateFilter) {
        guard selectedDateFilter != filter else {
            return
        }
        selectedDateFilter = filter
        refresh()
    }

    public func clearFilters() {
        filterDebounceTask?.cancel()
        searchQuery = ""
        debouncedSearchQuery = ""
        pathFilterQuery = ""
        debouncedPathFilterQuery = ""
        selectedRevisionFilter = nil
        selectedAuthorFilter = nil
        selectedDateFilter = .all
        refresh()
    }

    public func refresh() {
        beginRead()
    }

    public func toggleDetails(_ isVisible: Bool) {
        displayOptions.showsDetails = isVisible
    }

    public func toggleDiffPreview(_ isVisible: Bool) {
        displayOptions.showsDiffPreview = isVisible
    }

    public func selectCommit(_ hash: String?) {
        guard selectedCommitHash != hash else {
            return
        }
        selectedCommitHash = hash
        selectedCommitDetail = nil
        selectedFilePath = nil
        selectedFileDiff = ""
        selectedFileDiffNotice = nil
        isSelectedFileDiffTruncated = false
        guard let hash else {
            isLoadingSelectedCommitDetail = false
            isLoadingSelectedFileDiff = false
            commitDetailTask?.cancel()
            fileDiffTask?.cancel()
            return
        }
        loadCommitDetail(for: hash)
    }

    public func selectCommitFile(_ path: String?) {
        let normalized = Self.normalizedOptional(path)
        guard selectedFilePath != normalized else {
            return
        }
        selectedFilePath = normalized
        guard let normalized, let selectedCommitHash else {
            selectedFileDiff = ""
            selectedFileDiffNotice = nil
            isSelectedFileDiffTruncated = false
            isLoadingSelectedFileDiff = false
            fileDiffTask?.cancel()
            return
        }
        loadFileDiff(for: selectedCommitHash, filePath: normalized)
    }

    public func isCommitHighlightedOnCurrentBranch(_ commit: WorkspaceGitCommitSummary) -> Bool {
        guard selectedRevisionFilter == nil else {
            return false
        }
        guard let currentBranch = logSnapshot.refs.localBranches.first(where: \.isCurrent)?.name else {
            return false
        }
        let decorations = commit.decorations ?? ""
        return decorations.contains("HEAD -> \(currentBranch)") || decorations == currentBranch || decorations.contains(", \(currentBranch)")
    }

    public func cancelPendingReads(resetSelection: Bool) {
        filterDebounceTask?.cancel()
        readTask?.cancel()
        commitDetailTask?.cancel()
        fileDiffTask?.cancel()
        readRevision += 1
        commitDetailRevision += 1
        fileDiffRevision += 1
        isLoading = false
        isLoadingSelectedCommitDetail = false
        isLoadingSelectedFileDiff = false
        if resetSelection {
            selectedCommitHash = nil
            selectedCommitDetail = nil
            selectedFilePath = nil
            selectedFileDiff = ""
            selectedFileDiffNotice = nil
            isSelectedFileDiffTruncated = false
        }
    }

    private func scheduleFilterDebounce() {
        filterDebounceTask?.cancel()
        let nextQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextPath = pathFilterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        filterDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else {
                return
            }
            self.debouncedSearchQuery = nextQuery
            self.debouncedPathFilterQuery = nextPath
            self.refresh()
        }
    }

    private func beginRead() {
        readTask?.cancel()
        readRevision += 1
        let currentRevision = readRevision
        let repositoryPath = repositoryContext.repositoryPath
        let query = WorkspaceGitLogQuery(
            revision: selectedRevisionFilter,
            searchTerm: Self.normalizedOptional(debouncedSearchQuery),
            author: selectedAuthorFilter,
            since: selectedDateFilter.gitSinceExpression,
            path: Self.normalizedOptional(debouncedPathFilterQuery)
        )
        let authorSuggestionLimit = Self.authorSuggestionLimit
        isLoading = true
        errorMessage = nil

        readTask = Task { [client] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let snapshot = try client.loadLogSnapshot(repositoryPath, query)
                    let authors = try client.loadAuthorSuggestions(repositoryPath, authorSuggestionLimit)
                    return ReadResult(snapshot: snapshot, authors: authors)
                }.value
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self, self.readRevision == currentRevision else {
                        return
                    }
                    self.availableAuthors = result.authors
                    self.applyLogSnapshot(result.snapshot)
                    self.isLoading = false
                    if !result.snapshot.commits.contains(where: { $0.hash == self.selectedCommitHash }) {
                        self.selectCommit(result.snapshot.commits.first?.hash)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.readRevision == currentRevision else {
                        return
                    }
                    self.isLoading = false
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func loadCommitDetail(for hash: String) {
        commitDetailTask?.cancel()
        commitDetailRevision += 1
        let currentRevision = commitDetailRevision
        let repositoryPath = repositoryContext.repositoryPath
        isLoadingSelectedCommitDetail = true

        commitDetailTask = Task { [client] in
            do {
                let detail = try await Task.detached(priority: .userInitiated) {
                    try client.loadCommitDetail(repositoryPath, hash)
                }.value
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self,
                          self.commitDetailRevision == currentRevision,
                          self.selectedCommitHash == hash
                    else {
                        return
                    }
                    self.selectedCommitDetail = detail
                    self.isLoadingSelectedCommitDetail = false
                    let nextFile = self.selectedFilePath.flatMap { path in
                        detail.files.contains(where: { $0.path == path }) ? path : nil
                    } ?? detail.files.first?.path
                    self.selectCommitFile(nextFile)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    guard let self,
                          self.commitDetailRevision == currentRevision,
                          self.selectedCommitHash == hash
                    else {
                        return
                    }
                    self.isLoadingSelectedCommitDetail = false
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func loadFileDiff(for commitHash: String, filePath: String) {
        fileDiffTask?.cancel()
        fileDiffRevision += 1
        let currentRevision = fileDiffRevision
        let repositoryPath = repositoryContext.repositoryPath
        isLoadingSelectedFileDiff = true
        selectedFileDiff = ""
        selectedFileDiffNotice = nil
        isSelectedFileDiffTruncated = false

        fileDiffTask = Task { [client] in
            do {
                let diff = try await Task.detached(priority: .userInitiated) {
                    try client.loadFileDiffForCommit(repositoryPath, commitHash, filePath)
                }.value
                guard !Task.isCancelled else {
                    return
                }
                let truncated = Self.truncateDiff(diff)
                await MainActor.run { [weak self] in
                    guard let self,
                          self.fileDiffRevision == currentRevision,
                          self.selectedCommitHash == commitHash,
                          self.selectedFilePath == filePath
                    else {
                        return
                    }
                    self.selectedFileDiff = truncated.diff
                    self.selectedFileDiffNotice = truncated.notice
                    self.isSelectedFileDiffTruncated = truncated.truncated
                    self.isLoadingSelectedFileDiff = false
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    guard let self,
                          self.fileDiffRevision == currentRevision,
                          self.selectedCommitHash == commitHash,
                          self.selectedFilePath == filePath
                    else {
                        return
                    }
                    self.isLoadingSelectedFileDiff = false
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private nonisolated static func truncateDiff(_ diff: String) -> (diff: String, truncated: Bool, notice: String?) {
        guard !diff.isEmpty else {
            return (diff, false, nil)
        }

        let byteCappedDiff: String
        let bytesWereTruncated: Bool
        if diff.utf8.count > diffPreviewMaxBytes {
            let cappedData = Data(diff.utf8.prefix(diffPreviewMaxBytes))
            byteCappedDiff = String(decoding: cappedData, as: UTF8.self)
            bytesWereTruncated = true
        } else {
            byteCappedDiff = diff
            bytesWereTruncated = false
        }

        let lines = byteCappedDiff.split(separator: "\n", omittingEmptySubsequences: false)
        let linesWereTruncated = lines.count > diffPreviewMaxLines
        let visibleLines = linesWereTruncated ? Array(lines.prefix(diffPreviewMaxLines)) : lines
        let preview = visibleLines.joined(separator: "\n")

        guard bytesWereTruncated || linesWereTruncated else {
            return (preview, false, nil)
        }

        return (
            preview,
            true,
            "Diff 已截断：最多展示 256KB 或 2000 行，请回到终端查看完整补丁。"
        )
    }

    private nonisolated static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func applyLogSnapshot(_ snapshot: WorkspaceGitLogSnapshot) {
        let visibleModel = graphVisibleModelBuilder(snapshot.commits)
        logSnapshot = snapshot
        graphVisibleModel = visibleModel
        tableRows = visibleModel.rows.map { row in
            WorkspaceGitLogTableRow(commit: row.commit, graphRow: row)
        }
        preferredGraphWidth = visibleModel.recommendedWidth
    }
}
