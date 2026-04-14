import Foundation
import Observation

@MainActor
@Observable
public final class WorkspaceGitHubViewModel {
    public struct Client: Sendable {
        public var resolveRepositoryContext: @Sendable (WorkspaceGitRepositoryContext) throws -> WorkspaceGitHubRepositoryContext
        public var loadAuthStatus: @Sendable (WorkspaceGitHubRepositoryContext) -> WorkspaceGitHubAuthStatus
        public var loadPulls: @Sendable (WorkspaceGitHubRepositoryContext, WorkspaceGitHubPullFilter) throws -> [WorkspaceGitHubPullSummary]
        public var loadIssues: @Sendable (WorkspaceGitHubRepositoryContext, WorkspaceGitHubIssueFilter) throws -> [WorkspaceGitHubIssueSummary]
        public var loadReviewRequests: @Sendable (WorkspaceGitHubRepositoryContext, WorkspaceGitHubReviewFilter) throws -> [WorkspaceGitHubReviewRequestSummary]
        public var loadPullDetail: @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> WorkspaceGitHubPullDetail
        public var loadIssueDetail: @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> WorkspaceGitHubIssueDetail

        public init(
            resolveRepositoryContext: @escaping @Sendable (WorkspaceGitRepositoryContext) throws -> WorkspaceGitHubRepositoryContext,
            loadAuthStatus: @escaping @Sendable (WorkspaceGitHubRepositoryContext) -> WorkspaceGitHubAuthStatus,
            loadPulls: @escaping @Sendable (WorkspaceGitHubRepositoryContext, WorkspaceGitHubPullFilter) throws -> [WorkspaceGitHubPullSummary],
            loadIssues: @escaping @Sendable (WorkspaceGitHubRepositoryContext, WorkspaceGitHubIssueFilter) throws -> [WorkspaceGitHubIssueSummary],
            loadReviewRequests: @escaping @Sendable (WorkspaceGitHubRepositoryContext, WorkspaceGitHubReviewFilter) throws -> [WorkspaceGitHubReviewRequestSummary],
            loadPullDetail: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> WorkspaceGitHubPullDetail,
            loadIssueDetail: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> WorkspaceGitHubIssueDetail
        ) {
            self.resolveRepositoryContext = resolveRepositoryContext
            self.loadAuthStatus = loadAuthStatus
            self.loadPulls = loadPulls
            self.loadIssues = loadIssues
            self.loadReviewRequests = loadReviewRequests
            self.loadPullDetail = loadPullDetail
            self.loadIssueDetail = loadIssueDetail
        }

        public static func live(service: NativeGitHubRepositoryService) -> Client {
            Client(
                resolveRepositoryContext: {
                    try service.resolveRepositoryContext(
                        rootProjectPath: $0.rootProjectPath,
                        repositoryPath: $0.repositoryPath
                    )
                },
                loadAuthStatus: { (try? service.checkAuthStatus(host: $0.host)) ?? .unchecked(host: $0.host) },
                loadPulls: { try service.loadPulls(in: $0, filter: $1) },
                loadIssues: { try service.loadIssues(in: $0, filter: $1) },
                loadReviewRequests: { try service.loadReviewRequests(in: $0, filter: $1) },
                loadPullDetail: { try service.loadPullDetail(in: $0, number: $1) },
                loadIssueDetail: { try service.loadIssueDetail(in: $0, number: $1) }
            )
        }
    }

    @ObservationIgnored private let client: Client
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshRevision = 0
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    @ObservationIgnored private var detailRevision = 0
    @ObservationIgnored private var pullDetailsByNumber: [Int: WorkspaceGitHubPullDetail] = [:]
    @ObservationIgnored private var issueDetailsByNumber: [Int: WorkspaceGitHubIssueDetail] = [:]

    public var repositoryContext: WorkspaceGitRepositoryContext
    public private(set) var gitHubContext: WorkspaceGitHubRepositoryContext?
    public private(set) var authStatus: WorkspaceGitHubAuthStatus
    public var section: WorkspaceGitHubSection
    public var pullFilter: WorkspaceGitHubPullFilter
    public var issueFilter: WorkspaceGitHubIssueFilter
    public var reviewFilter: WorkspaceGitHubReviewFilter
    public private(set) var pulls: [WorkspaceGitHubPullSummary]
    public private(set) var issues: [WorkspaceGitHubIssueSummary]
    public private(set) var reviewRequests: [WorkspaceGitHubReviewRequestSummary]
    public private(set) var selectedPullNumber: Int?
    public private(set) var selectedIssueNumber: Int?
    public private(set) var selectedPullDetail: WorkspaceGitHubPullDetail?
    public private(set) var selectedIssueDetail: WorkspaceGitHubIssueDetail?
    public private(set) var isLoading: Bool
    public private(set) var isLoadingDetail: Bool
    public var errorMessage: String?
    public var detailErrorMessage: String?

    public init(
        repositoryContext: WorkspaceGitRepositoryContext,
        section: WorkspaceGitHubSection = .pulls,
        client: Client
    ) {
        self.repositoryContext = repositoryContext
        self.client = client
        self.gitHubContext = nil
        self.authStatus = .unchecked(host: "github.com")
        self.section = section
        self.pullFilter = WorkspaceGitHubPullFilter()
        self.issueFilter = WorkspaceGitHubIssueFilter()
        self.reviewFilter = WorkspaceGitHubReviewFilter()
        self.pulls = []
        self.issues = []
        self.reviewRequests = []
        self.selectedPullNumber = nil
        self.selectedIssueNumber = nil
        self.selectedPullDetail = nil
        self.selectedIssueDetail = nil
        self.isLoading = false
        self.isLoadingDetail = false
        self.errorMessage = nil
        self.detailErrorMessage = nil
    }

    deinit {
        refreshTask?.cancel()
        detailTask?.cancel()
    }

    public var displayRepositoryTitle: String {
        gitHubContext?.repositoryFullName ?? repositoryContext.repositoryPath
    }

    public var hasUsableRepositoryContext: Bool {
        gitHubContext != nil
    }

    public var selectedPullSummary: WorkspaceGitHubPullSummary? {
        pulls.first(where: { $0.number == selectedPullNumber })
    }

    public var selectedReviewRequestSummary: WorkspaceGitHubReviewRequestSummary? {
        reviewRequests.first(where: { $0.number == selectedPullNumber })
    }

    public var selectedIssueSummary: WorkspaceGitHubIssueSummary? {
        issues.first(where: { $0.number == selectedIssueNumber })
    }

    public func updateRepositoryContext(_ repositoryContext: WorkspaceGitRepositoryContext) {
        guard self.repositoryContext != repositoryContext else {
            return
        }
        self.repositoryContext = repositoryContext
        gitHubContext = nil
        authStatus = .unchecked(host: "github.com")
        pulls = []
        issues = []
        reviewRequests = []
        selectedPullNumber = nil
        selectedIssueNumber = nil
        selectedPullDetail = nil
        selectedIssueDetail = nil
        pullDetailsByNumber.removeAll()
        issueDetailsByNumber.removeAll()
        errorMessage = nil
        detailErrorMessage = nil
    }

    public func setSection(_ section: WorkspaceGitHubSection) {
        guard self.section != section else {
            return
        }
        self.section = section
        detailErrorMessage = nil
        refreshIfNeeded()
    }

    public func refreshIfNeeded() {
        switch section {
        case .pulls where pulls.isEmpty:
            refresh()
        case .issues where issues.isEmpty:
            refresh()
        case .reviews where reviewRequests.isEmpty:
            refresh()
        default:
            selectDefaultDetailIfNeeded()
        }
    }

    public func refresh() {
        refreshTask?.cancel()
        refreshRevision += 1
        let revision = refreshRevision
        let repositoryContext = repositoryContext
        let section = section
        let pullFilter = self.pullFilter
        let issueFilter = self.issueFilter
        let reviewFilter = self.reviewFilter
        errorMessage = nil
        isLoading = true

        refreshTask = Task { [client] in
            do {
                let payload = try await Task.detached(priority: .userInitiated) {
                    let gitHubContext = try client.resolveRepositoryContext(repositoryContext)
                    let authStatus = client.loadAuthStatus(gitHubContext)
                    guard authStatus.isAuthenticated else {
                        return RefreshPayload(
                            gitHubContext: gitHubContext,
                            authStatus: authStatus,
                            pulls: [],
                            issues: [],
                            reviewRequests: []
                        )
                    }

                    let pulls = try client.loadPulls(gitHubContext, pullFilter)
                    let issues = try client.loadIssues(gitHubContext, issueFilter)
                    let reviews = try client.loadReviewRequests(gitHubContext, reviewFilter)
                    return RefreshPayload(
                        gitHubContext: gitHubContext,
                        authStatus: authStatus,
                        pulls: pulls,
                        issues: issues,
                        reviewRequests: reviews
                    )
                }.value

                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self, self.refreshRevision == revision else {
                        return
                    }
                    self.gitHubContext = payload.gitHubContext
                    self.authStatus = payload.authStatus
                    self.pulls = payload.pulls
                    self.issues = payload.issues
                    self.reviewRequests = payload.reviewRequests
                    self.isLoading = false
                    self.selectDefaultDetailIfNeeded(forceReloadFor: section)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.refreshRevision == revision else {
                        return
                    }
                    self.isLoading = false
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    public func selectPull(number: Int?) {
        guard selectedPullNumber != number else {
            return
        }
        selectedPullNumber = number
        selectedPullDetail = nil
        detailErrorMessage = nil
        guard let number else {
            isLoadingDetail = false
            detailTask?.cancel()
            return
        }
        if let cachedDetail = pullDetailsByNumber[number] {
            selectedPullDetail = cachedDetail
            return
        }
        loadSelectedPullDetail(number)
    }

    public func selectIssue(number: Int?) {
        guard selectedIssueNumber != number else {
            return
        }
        selectedIssueNumber = number
        selectedIssueDetail = nil
        detailErrorMessage = nil
        guard let number else {
            isLoadingDetail = false
            detailTask?.cancel()
            return
        }
        if let cachedDetail = issueDetailsByNumber[number] {
            selectedIssueDetail = cachedDetail
            return
        }
        loadSelectedIssueDetail(number)
    }

    private func selectDefaultDetailIfNeeded(forceReloadFor section: WorkspaceGitHubSection? = nil) {
        switch section ?? self.section {
        case .pulls:
            let availableNumbers = Set(pulls.map(\.number))
            let nextNumber = availableNumbers.contains(selectedPullNumber ?? -1) ? selectedPullNumber : pulls.first?.number
            if selectedPullNumber != nextNumber {
                selectPull(number: nextNumber)
            } else if let nextNumber {
                loadSelectedPullDetail(nextNumber, useCacheIfAvailable: true)
            }
        case .reviews:
            let availableNumbers = Set(reviewRequests.map(\.number))
            let nextNumber = availableNumbers.contains(selectedPullNumber ?? -1) ? selectedPullNumber : reviewRequests.first?.number
            if selectedPullNumber != nextNumber {
                selectPull(number: nextNumber)
            } else if let nextNumber {
                loadSelectedPullDetail(nextNumber, useCacheIfAvailable: true)
            }
        case .issues:
            let availableNumbers = Set(issues.map(\.number))
            let nextNumber = availableNumbers.contains(selectedIssueNumber ?? -1) ? selectedIssueNumber : issues.first?.number
            if selectedIssueNumber != nextNumber {
                selectIssue(number: nextNumber)
            } else if let nextNumber {
                loadSelectedIssueDetail(nextNumber, useCacheIfAvailable: true)
            }
        }
    }

    private func loadSelectedPullDetail(_ number: Int, useCacheIfAvailable: Bool = false) {
        guard let gitHubContext else {
            return
        }
        if useCacheIfAvailable, let cachedDetail = pullDetailsByNumber[number] {
            selectedPullDetail = cachedDetail
            return
        }

        detailTask?.cancel()
        detailRevision += 1
        let revision = detailRevision
        isLoadingDetail = true

        detailTask = Task { [client] in
            do {
                let detail = try await Task.detached(priority: .userInitiated) {
                    try client.loadPullDetail(gitHubContext, number)
                }.value
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self, self.detailRevision == revision, self.selectedPullNumber == number else {
                        return
                    }
                    self.pullDetailsByNumber[number] = detail
                    self.selectedPullDetail = detail
                    self.isLoadingDetail = false
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.detailRevision == revision, self.selectedPullNumber == number else {
                        return
                    }
                    self.isLoadingDetail = false
                    self.detailErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func loadSelectedIssueDetail(_ number: Int, useCacheIfAvailable: Bool = false) {
        guard let gitHubContext else {
            return
        }
        if useCacheIfAvailable, let cachedDetail = issueDetailsByNumber[number] {
            selectedIssueDetail = cachedDetail
            return
        }

        detailTask?.cancel()
        detailRevision += 1
        let revision = detailRevision
        isLoadingDetail = true

        detailTask = Task { [client] in
            do {
                let detail = try await Task.detached(priority: .userInitiated) {
                    try client.loadIssueDetail(gitHubContext, number)
                }.value
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self, self.detailRevision == revision, self.selectedIssueNumber == number else {
                        return
                    }
                    self.issueDetailsByNumber[number] = detail
                    self.selectedIssueDetail = detail
                    self.isLoadingDetail = false
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.detailRevision == revision, self.selectedIssueNumber == number else {
                        return
                    }
                    self.isLoadingDetail = false
                    self.detailErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private struct RefreshPayload: Sendable {
        var gitHubContext: WorkspaceGitHubRepositoryContext
        var authStatus: WorkspaceGitHubAuthStatus
        var pulls: [WorkspaceGitHubPullSummary]
        var issues: [WorkspaceGitHubIssueSummary]
        var reviewRequests: [WorkspaceGitHubReviewRequestSummary]
    }
}
