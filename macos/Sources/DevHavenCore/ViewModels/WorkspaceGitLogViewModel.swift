import Foundation
import Observation

@MainActor
@Observable
public final class WorkspaceGitLogViewModel {
    public struct Client: Sendable {
        public var loadLogSnapshot: @Sendable (String, WorkspaceGitLogQuery) throws -> WorkspaceGitLogSnapshot
        public var loadCommitSummary: @Sendable (String, String) throws -> WorkspaceGitCommitDetail
        public var loadFileDiffForCommit: @Sendable (String, String, String) throws -> String
        public var loadAuthorSuggestions: @Sendable (String, Int) throws -> [String]

        public init(
            loadLogSnapshot: @escaping @Sendable (String, WorkspaceGitLogQuery) throws -> WorkspaceGitLogSnapshot,
            loadCommitSummary: @escaping @Sendable (String, String) throws -> WorkspaceGitCommitDetail,
            loadFileDiffForCommit: @escaping @Sendable (String, String, String) throws -> String,
            loadAuthorSuggestions: @escaping @Sendable (String, Int) throws -> [String]
        ) {
            self.loadLogSnapshot = loadLogSnapshot
            self.loadCommitSummary = loadCommitSummary
            self.loadFileDiffForCommit = loadFileDiffForCommit
            self.loadAuthorSuggestions = loadAuthorSuggestions
        }

        public static func live(service: NativeGitRepositoryService) -> Client {
            Client(
                loadLogSnapshot: { try service.loadLogSnapshot(at: $0, query: $1) },
                loadCommitSummary: { try service.loadCommitSummary(at: $0, commitHash: $1) },
                loadFileDiffForCommit: { try service.loadDiffForCommitFile(at: $0, commitHash: $1, filePath: $2) },
                loadAuthorSuggestions: { try service.loadLogAuthors(at: $0, limit: $1) }
            )
        }
    }

    private struct ReadResult: Sendable {
        var snapshot: WorkspaceGitLogSnapshot
        var authors: [String]
        var visibleModel: WorkspaceGitCommitGraphVisibleModel
        var tableRows: [WorkspaceGitLogTableRow]
        var preferredGraphWidth: Double
    }

    @ObservationIgnored private let client: Client
    @ObservationIgnored private let graphVisibleModelBuilder: @Sendable ([WorkspaceGitCommitSummary]) -> WorkspaceGitCommitGraphVisibleModel
    @ObservationIgnored private var filterDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var readRevision = 0
    @ObservationIgnored private var hasAttemptedInitialRefresh = false
    @ObservationIgnored private var commitDetailTask: Task<Void, Never>?
    @ObservationIgnored private var commitDetailRevision = 0
    @ObservationIgnored private var fileDiffTask: Task<Void, Never>?
    @ObservationIgnored private var fileDiffRevision = 0
    @ObservationIgnored private var cachedAuthorSuggestionsByRepositoryPath: [String: [String]] = [:]

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
            WorkspaceGitLogTableRow(
                commit: row.commit,
                graphRow: row,
                decorationBadges: Self.decorationBadges(for: row.commit.decorations),
                formattedDateText: Self.formattedCommitTimestamp(row.commit.authorTimestamp),
                isHighlightedOnCurrentBranch: false
            )
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
        hasAttemptedInitialRefresh = true
        beginRead()
    }

    public func refreshIfNeeded() {
        guard !hasAttemptedInitialRefresh else {
            return
        }
        refresh()
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

    public func selectCommitFile(
        _ path: String?,
        loadDiffPreview: Bool = true
    ) {
        let normalized = Self.normalizedOptional(path)
        if selectedFilePath == normalized {
            guard loadDiffPreview,
                  let normalized,
                  let selectedCommitHash,
                  selectedFileDiff.isEmpty,
                  !isLoadingSelectedFileDiff
            else {
                return
            }
            loadFileDiff(for: selectedCommitHash, filePath: normalized)
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
        guard loadDiffPreview else {
            selectedFileDiff = ""
            selectedFileDiffNotice = nil
            isSelectedFileDiffTruncated = false
            isLoadingSelectedFileDiff = false
            fileDiffTask?.cancel()
            return
        }
        loadFileDiff(for: selectedCommitHash, filePath: normalized)
    }

    public func resolveFileChangeForOpeningDiff(
        commitHash: String
    ) async -> WorkspaceGitCommitFileChange? {
        if selectedCommitHash != commitHash {
            selectCommit(commitHash)
        } else if selectedCommitDetail?.hash != commitHash && !isLoadingSelectedCommitDetail {
            loadCommitDetail(for: commitHash)
        }

        if selectedCommitDetail?.hash != commitHash {
            await commitDetailTask?.value
        }

        guard selectedCommitHash == commitHash,
              let detail = selectedCommitDetail,
              detail.hash == commitHash
        else {
            return nil
        }

        let preferredFile = preferredFileForOpeningDiff(in: detail)
        selectCommitFile(preferredFile?.path, loadDiffPreview: false)
        return preferredFile
    }

    public func isCommitHighlightedOnCurrentBranch(_ commit: WorkspaceGitCommitSummary) -> Bool {
        guard selectedRevisionFilter == nil else {
            return false
        }
        return Self.isCommitHighlightedOnCurrentBranch(
            commit,
            currentBranchName: logSnapshot.refs.localBranches.first(where: \.isCurrent)?.name
        )
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
        let cachedAuthors = cachedAuthorSuggestionsByRepositoryPath[repositoryPath]
        let graphVisibleModelBuilder = self.graphVisibleModelBuilder
        isLoading = true
        errorMessage = nil

        readTask = Task { [client] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let snapshot = try client.loadLogSnapshot(repositoryPath, query)
                    let authors = try cachedAuthors ?? client.loadAuthorSuggestions(repositoryPath, authorSuggestionLimit)
                    let visibleModel = graphVisibleModelBuilder(snapshot.commits)
                    let currentBranchName = snapshot.refs.localBranches.first(where: \.isCurrent)?.name
                    let tableRows = visibleModel.rows.map { row in
                        WorkspaceGitLogTableRow(
                            commit: row.commit,
                            graphRow: row,
                            decorationBadges: Self.decorationBadges(for: row.commit.decorations),
                            formattedDateText: Self.formattedCommitTimestamp(row.commit.authorTimestamp),
                            isHighlightedOnCurrentBranch: Self.isCommitHighlightedOnCurrentBranch(
                                row.commit,
                                currentBranchName: currentBranchName
                            )
                        )
                    }
                    return ReadResult(
                        snapshot: snapshot,
                        authors: authors,
                        visibleModel: visibleModel,
                        tableRows: tableRows,
                        preferredGraphWidth: visibleModel.recommendedWidth
                    )
                }.value
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self, self.readRevision == currentRevision else {
                        return
                    }
                    self.availableAuthors = result.authors
                    self.cachedAuthorSuggestionsByRepositoryPath[repositoryPath] = result.authors
                    self.applyLogSnapshot(
                        result.snapshot,
                        visibleModel: result.visibleModel,
                        tableRows: result.tableRows,
                        preferredGraphWidth: result.preferredGraphWidth
                    )
                    self.isLoading = false
                    if !result.snapshot.commits.contains(where: { $0.hash == self.selectedCommitHash }) {
                        self.selectCommit(nil)
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
                    try client.loadCommitSummary(repositoryPath, hash)
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
                    self.selectCommitFile(nextFile, loadDiffPreview: false)
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

    private nonisolated static func formattedCommitTimestamp(_ authorTimestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: authorTimestamp)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }

    private nonisolated static func decorationBadges(for decorations: String?) -> [String] {
        guard let decorations = decorations?
            .trimmingCharacters(in: CharacterSet(charactersIn: "() ").union(.whitespacesAndNewlines)),
              !decorations.isEmpty
        else {
            return []
        }
        return decorations
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private nonisolated static func isCommitHighlightedOnCurrentBranch(
        _ commit: WorkspaceGitCommitSummary,
        currentBranchName: String?
    ) -> Bool {
        guard let currentBranchName else {
            return false
        }
        let decorations = commit.decorations ?? ""
        return decorations.contains("HEAD -> \(currentBranchName)") ||
            decorations == currentBranchName ||
            decorations.contains(", \(currentBranchName)")
    }

    private func preferredFileForOpeningDiff(
        in detail: WorkspaceGitCommitDetail
    ) -> WorkspaceGitCommitFileChange? {
        if let selectedFilePath,
           let selectedFile = detail.files.first(where: { $0.path == selectedFilePath }) {
            return selectedFile
        }
        return detail.files.first
    }

    private func applyLogSnapshot(
        _ snapshot: WorkspaceGitLogSnapshot,
        visibleModel: WorkspaceGitCommitGraphVisibleModel,
        tableRows: [WorkspaceGitLogTableRow],
        preferredGraphWidth: Double
    ) {
        logSnapshot = snapshot
        graphVisibleModel = visibleModel
        self.tableRows = tableRows
        self.preferredGraphWidth = preferredGraphWidth
    }
}
