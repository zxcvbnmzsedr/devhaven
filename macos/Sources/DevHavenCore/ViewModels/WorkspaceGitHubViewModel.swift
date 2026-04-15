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
        public var addIssueComment: @Sendable (WorkspaceGitHubRepositoryContext, Int, String) throws -> Void
        public var closeIssue: @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> Void
        public var reopenIssue: @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> Void
        public var createLocalBranch: @Sendable (String, String, String?) throws -> Void
        public var checkoutLocalBranch: @Sendable (String, String) throws -> Void
        public var addPullComment: @Sendable (WorkspaceGitHubRepositoryContext, Int, String) throws -> Void
        public var closePull: @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> Void
        public var reopenPull: @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> Void
        public var mergePull: @Sendable (WorkspaceGitHubRepositoryContext, Int, WorkspaceGitHubPullMergeMethod) throws -> Void
        public var checkoutPullBranch: @Sendable (WorkspaceGitHubRepositoryContext, Int, String) throws -> Void
        public var submitReview: @Sendable (WorkspaceGitHubRepositoryContext, Int, WorkspaceGitHubReviewSubmissionEvent, String?) throws -> Void

        public init(
            resolveRepositoryContext: @escaping @Sendable (WorkspaceGitRepositoryContext) throws -> WorkspaceGitHubRepositoryContext,
            loadAuthStatus: @escaping @Sendable (WorkspaceGitHubRepositoryContext) -> WorkspaceGitHubAuthStatus,
            loadPulls: @escaping @Sendable (WorkspaceGitHubRepositoryContext, WorkspaceGitHubPullFilter) throws -> [WorkspaceGitHubPullSummary],
            loadIssues: @escaping @Sendable (WorkspaceGitHubRepositoryContext, WorkspaceGitHubIssueFilter) throws -> [WorkspaceGitHubIssueSummary],
            loadReviewRequests: @escaping @Sendable (WorkspaceGitHubRepositoryContext, WorkspaceGitHubReviewFilter) throws -> [WorkspaceGitHubReviewRequestSummary],
            loadPullDetail: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> WorkspaceGitHubPullDetail,
            loadIssueDetail: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> WorkspaceGitHubIssueDetail,
            addIssueComment: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int, String) throws -> Void,
            closeIssue: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> Void,
            reopenIssue: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> Void,
            createLocalBranch: @escaping @Sendable (String, String, String?) throws -> Void,
            checkoutLocalBranch: @escaping @Sendable (String, String) throws -> Void,
            addPullComment: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int, String) throws -> Void,
            closePull: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> Void,
            reopenPull: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> Void,
            mergePull: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int, WorkspaceGitHubPullMergeMethod) throws -> Void,
            checkoutPullBranch: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int, String) throws -> Void,
            submitReview: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int, WorkspaceGitHubReviewSubmissionEvent, String?) throws -> Void
        ) {
            self.resolveRepositoryContext = resolveRepositoryContext
            self.loadAuthStatus = loadAuthStatus
            self.loadPulls = loadPulls
            self.loadIssues = loadIssues
            self.loadReviewRequests = loadReviewRequests
            self.loadPullDetail = loadPullDetail
            self.loadIssueDetail = loadIssueDetail
            self.addIssueComment = addIssueComment
            self.closeIssue = closeIssue
            self.reopenIssue = reopenIssue
            self.createLocalBranch = createLocalBranch
            self.checkoutLocalBranch = checkoutLocalBranch
            self.addPullComment = addPullComment
            self.closePull = closePull
            self.reopenPull = reopenPull
            self.mergePull = mergePull
            self.checkoutPullBranch = checkoutPullBranch
            self.submitReview = submitReview
        }

        public static func live(
            githubService: NativeGitHubRepositoryService,
            gitService: NativeGitRepositoryService
        ) -> Client {
            Client(
                resolveRepositoryContext: {
                    try githubService.resolveRepositoryContext(
                        rootProjectPath: $0.rootProjectPath,
                        repositoryPath: $0.repositoryPath
                    )
                },
                loadAuthStatus: { (try? githubService.checkAuthStatus(host: $0.host)) ?? .unchecked(host: $0.host) },
                loadPulls: { try githubService.loadPulls(in: $0, filter: $1) },
                loadIssues: { try githubService.loadIssues(in: $0, filter: $1) },
                loadReviewRequests: { try githubService.loadReviewRequests(in: $0, filter: $1) },
                loadPullDetail: { try githubService.loadPullDetail(in: $0, number: $1) },
                loadIssueDetail: { try githubService.loadIssueDetail(in: $0, number: $1) },
                addIssueComment: { try githubService.addIssueComment(in: $0, number: $1, body: $2) },
                closeIssue: { try githubService.closeIssue(in: $0, number: $1) },
                reopenIssue: { try githubService.reopenIssue(in: $0, number: $1) },
                createLocalBranch: { try gitService.createBranch(name: $1, startPoint: $2, at: $0) },
                checkoutLocalBranch: { try gitService.checkoutBranch(name: $1, at: $0) },
                addPullComment: { try githubService.addPullComment(in: $0, number: $1, body: $2) },
                closePull: { try githubService.closePull(in: $0, number: $1) },
                reopenPull: { try githubService.reopenPull(in: $0, number: $1) },
                mergePull: { try githubService.mergePull(in: $0, number: $1, method: $2) },
                checkoutPullBranch: { try githubService.checkoutPullBranch(in: $0, number: $1, at: $2) },
                submitReview: { try githubService.submitReview(in: $0, number: $1, event: $2, body: $3) }
            )
        }
    }

    @ObservationIgnored private let client: Client
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshRevision = 0
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    @ObservationIgnored private var detailRevision = 0
    @ObservationIgnored private var mutationRevision = 0
    @ObservationIgnored private var pullDetailsByNumber: [Int: WorkspaceGitHubPullDetail] = [:]
    @ObservationIgnored private var issueDetailsByNumber: [Int: WorkspaceGitHubIssueDetail] = [:]

    public var repositoryContext: WorkspaceGitRepositoryContext
    public var executionPath: String
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
    public private(set) var isMutating: Bool
    public private(set) var activeMutation: WorkspaceGitHubMutationKind?
    public private(set) var lastSuccessfulMutation: WorkspaceGitHubMutationKind?
    public private(set) var successfulMutationToken: Int
    public var issueCommentDraft: String
    public var pullCommentDraft: String
    public var reviewCommentDraft: String
    public var errorMessage: String?
    public var detailErrorMessage: String?
    public var mutationErrorMessage: String?

    public init(
        repositoryContext: WorkspaceGitRepositoryContext,
        executionPath: String? = nil,
        section: WorkspaceGitHubSection = .pulls,
        client: Client
    ) {
        self.repositoryContext = repositoryContext
        self.executionPath = executionPath ?? repositoryContext.repositoryPath
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
        self.isMutating = false
        self.activeMutation = nil
        self.lastSuccessfulMutation = nil
        self.successfulMutationToken = 0
        self.issueCommentDraft = ""
        self.pullCommentDraft = ""
        self.reviewCommentDraft = ""
        self.errorMessage = nil
        self.detailErrorMessage = nil
        self.mutationErrorMessage = nil
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

    public func updateRepositoryContext(
        _ repositoryContext: WorkspaceGitRepositoryContext,
        executionPath: String? = nil
    ) {
        let nextExecutionPath = executionPath ?? repositoryContext.repositoryPath
        guard self.repositoryContext != repositoryContext || self.executionPath != nextExecutionPath else {
            return
        }
        mutationRevision += 1
        self.repositoryContext = repositoryContext
        self.executionPath = nextExecutionPath
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
        issueCommentDraft = ""
        pullCommentDraft = ""
        reviewCommentDraft = ""
        errorMessage = nil
        detailErrorMessage = nil
        mutationErrorMessage = nil
        lastSuccessfulMutation = nil
    }

    public func updateExecutionPath(_ executionPath: String) {
        let normalizedPath = executionPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty, self.executionPath != normalizedPath else {
            return
        }
        mutationRevision += 1
        self.executionPath = normalizedPath
    }

    public func setSection(_ section: WorkspaceGitHubSection) {
        guard self.section != section else {
            return
        }
        mutationRevision += 1
        self.section = section
        detailErrorMessage = nil
        mutationErrorMessage = nil
        lastSuccessfulMutation = nil
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
        mutationRevision += 1
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
        mutationRevision += 1
        selectedPullNumber = number
        selectedPullDetail = nil
        detailErrorMessage = nil
        mutationErrorMessage = nil
        lastSuccessfulMutation = nil
        pullCommentDraft = ""
        reviewCommentDraft = ""
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
        mutationRevision += 1
        selectedIssueNumber = number
        selectedIssueDetail = nil
        detailErrorMessage = nil
        mutationErrorMessage = nil
        lastSuccessfulMutation = nil
        issueCommentDraft = ""
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

    public func addCommentToSelectedIssue(body: String? = nil) {
        let draft = body ?? issueCommentDraft
        performIssueMutation(
            kind: .addIssueComment,
            refresh: .issue(number: selectedIssueNumber)
        ) { client, gitHubContext, number, _ in
            try client.addIssueComment(gitHubContext, number, draft)
        } onSuccess: { [weak self] in
            self?.issueCommentDraft = ""
        }
    }

    public func closeSelectedIssue() {
        performIssueMutation(
            kind: .closeIssue,
            refresh: .issue(number: selectedIssueNumber)
        ) { client, gitHubContext, number, _ in
            try client.closeIssue(gitHubContext, number)
        }
    }

    public func reopenSelectedIssue() {
        performIssueMutation(
            kind: .reopenIssue,
            refresh: .issue(number: selectedIssueNumber)
        ) { client, gitHubContext, number, _ in
            try client.reopenIssue(gitHubContext, number)
        }
    }

    public func createAndCheckoutBranchForSelectedIssue() {
        guard let detail = selectedIssueDetail ?? selectedIssueSummary.map(Self.makeIssueDetailFallback) else {
            mutationErrorMessage = "请先选择一个 Issue"
            return
        }
        let branchName = detail.suggestedBranchName
        performIssueMutation(
            kind: .createIssueBranch,
            refresh: .none
        ) { client, _, _, executionPath in
            try client.createLocalBranch(executionPath, branchName, nil)
            try client.checkoutLocalBranch(executionPath, branchName)
        }
    }

    public func addCommentToSelectedPull(body: String? = nil) {
        let draft = body ?? pullCommentDraft
        performPullMutation(
            kind: .addPullComment,
            refresh: .pull(number: selectedPullNumber)
        ) { client, gitHubContext, number, _ in
            try client.addPullComment(gitHubContext, number, draft)
        } onSuccess: { [weak self] in
            self?.pullCommentDraft = ""
        }
    }

    public func closeSelectedPull() {
        performPullMutation(
            kind: .closePull,
            refresh: .pull(number: selectedPullNumber)
        ) { client, gitHubContext, number, _ in
            try client.closePull(gitHubContext, number)
        }
    }

    public func reopenSelectedPull() {
        performPullMutation(
            kind: .reopenPull,
            refresh: .pull(number: selectedPullNumber)
        ) { client, gitHubContext, number, _ in
            try client.reopenPull(gitHubContext, number)
        }
    }

    public func mergeSelectedPull(method: WorkspaceGitHubPullMergeMethod = .merge) {
        performPullMutation(
            kind: .mergePull(method),
            refresh: .pull(number: selectedPullNumber)
        ) { client, gitHubContext, number, _ in
            try client.mergePull(gitHubContext, number, method)
        }
    }

    public func checkoutSelectedPullBranch() {
        performPullMutation(
            kind: .checkoutPullBranch,
            refresh: .none
        ) { client, gitHubContext, number, executionPath in
            try client.checkoutPullBranch(gitHubContext, number, executionPath)
        }
    }

    public func submitReviewForSelectedPull(
        event: WorkspaceGitHubReviewSubmissionEvent,
        body: String? = nil
    ) {
        let draft = body ?? reviewCommentDraft
        performPullMutation(
            kind: .submitReview(event),
            refresh: .pull(number: selectedPullNumber)
        ) { client, gitHubContext, number, _ in
            try client.submitReview(gitHubContext, number, event, draft)
        } onSuccess: { [weak self] in
            self?.reviewCommentDraft = ""
        }
    }

    public func reportMutationFailure(_ error: Error) {
        mutationRevision += 1
        isMutating = false
        activeMutation = nil
        mutationErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        lastSuccessfulMutation = nil
    }

    public func reportExternalMutationSuccess(_ kind: WorkspaceGitHubMutationKind) {
        mutationRevision += 1
        isMutating = false
        activeMutation = nil
        mutationErrorMessage = nil
        lastSuccessfulMutation = kind
        successfulMutationToken += 1
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

    private func performIssueMutation(
        kind: WorkspaceGitHubMutationKind,
        refresh: MutationRefreshRequest,
        _ mutation: @escaping @Sendable (Client, WorkspaceGitHubRepositoryContext, Int, String) throws -> Void,
        onSuccess: (@MainActor () -> Void)? = nil
    ) {
        guard let gitHubContext else {
            mutationErrorMessage = "GitHub 仓库上下文尚未就绪"
            return
        }
        guard let number = selectedIssueNumber else {
            mutationErrorMessage = "请先选择一个 Issue"
            return
        }
        performMutation(
            kind: kind,
            gitHubContext: gitHubContext,
            selectedIssueNumber: number,
            selectedPullNumber: nil,
            refresh: refresh,
            mutation: mutation,
            onSuccess: onSuccess
        )
    }

    private func performPullMutation(
        kind: WorkspaceGitHubMutationKind,
        refresh: MutationRefreshRequest,
        _ mutation: @escaping @Sendable (Client, WorkspaceGitHubRepositoryContext, Int, String) throws -> Void,
        onSuccess: (@MainActor () -> Void)? = nil
    ) {
        guard let gitHubContext else {
            mutationErrorMessage = "GitHub 仓库上下文尚未就绪"
            return
        }
        guard let number = selectedPullNumber else {
            mutationErrorMessage = "请先选择一个 Pull Request"
            return
        }
        performMutation(
            kind: kind,
            gitHubContext: gitHubContext,
            selectedIssueNumber: nil,
            selectedPullNumber: number,
            refresh: refresh,
            mutation: mutation,
            onSuccess: onSuccess
        )
    }

    private func performMutation(
        kind: WorkspaceGitHubMutationKind,
        gitHubContext: WorkspaceGitHubRepositoryContext,
        selectedIssueNumber: Int?,
        selectedPullNumber: Int?,
        refresh: MutationRefreshRequest,
        mutation: @escaping @Sendable (Client, WorkspaceGitHubRepositoryContext, Int, String) throws -> Void,
        onSuccess: (@MainActor () -> Void)?
    ) {
        guard !isMutating else {
            return
        }

        let currentRepositoryContext = self.repositoryContext
        let currentExecutionPath = self.executionPath
        let currentSection = self.section
        let currentPullFilter = self.pullFilter
        let currentIssueFilter = self.issueFilter
        let currentReviewFilter = self.reviewFilter

        mutationRevision += 1
        let revision = mutationRevision
        isMutating = true
        activeMutation = kind
        mutationErrorMessage = nil
        detailErrorMessage = nil
        lastSuccessfulMutation = nil

        Task { [client] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    let selectedNumber = selectedIssueNumber ?? selectedPullNumber ?? 0
                    try mutation(client, gitHubContext, selectedNumber, currentExecutionPath)
                }.value

                let refreshedPayload: MutationRefreshPayload?
                if refresh == .none {
                    refreshedPayload = nil
                } else {
                    refreshedPayload = try await Task.detached(priority: .userInitiated) {
                        try Self.loadMutationRefreshPayload(
                            refresh: refresh,
                            gitHubContext: gitHubContext,
                            pullFilter: currentPullFilter,
                            issueFilter: currentIssueFilter,
                            reviewFilter: currentReviewFilter,
                            client: client
                        )
                    }.value
                }

                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    guard self.mutationRevision == revision else {
                        self.isMutating = false
                        self.activeMutation = nil
                        return
                    }
                    guard self.repositoryContext == currentRepositoryContext,
                          self.executionPath == currentExecutionPath,
                          self.pullFilter == currentPullFilter,
                          self.issueFilter == currentIssueFilter,
                          self.reviewFilter == currentReviewFilter
                    else {
                        self.isMutating = false
                        self.activeMutation = nil
                        return
                    }

                    if let refreshedPayload {
                        self.applyMutationRefreshPayload(
                            refreshedPayload,
                            section: currentSection
                        )
                    }
                    self.isMutating = false
                    self.activeMutation = nil
                    self.mutationErrorMessage = nil
                    self.lastSuccessfulMutation = kind
                    self.successfulMutationToken += 1
                    onSuccess?()
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    self?.isMutating = false
                    self?.activeMutation = nil
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    guard self.mutationRevision == revision else {
                        self.isMutating = false
                        self.activeMutation = nil
                        return
                    }
                    self.isMutating = false
                    self.activeMutation = nil
                    self.mutationErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func applyMutationRefreshPayload(
        _ payload: MutationRefreshPayload,
        section: WorkspaceGitHubSection
    ) {
        guard section == self.section else {
            return
        }

        pulls = payload.pulls
        issues = payload.issues
        reviewRequests = payload.reviewRequests

        if let issueDetail = payload.issueDetail {
            issueDetailsByNumber[issueDetail.number] = issueDetail
        }
        if let pullDetail = payload.pullDetail {
            pullDetailsByNumber[pullDetail.number] = pullDetail
        }
        selectDefaultDetailIfNeeded(forceReloadFor: section)
    }

    private nonisolated static func loadMutationRefreshPayload(
        refresh: MutationRefreshRequest,
        gitHubContext: WorkspaceGitHubRepositoryContext,
        pullFilter: WorkspaceGitHubPullFilter,
        issueFilter: WorkspaceGitHubIssueFilter,
        reviewFilter: WorkspaceGitHubReviewFilter,
        client: Client
    ) throws -> MutationRefreshPayload {
        let pulls = try client.loadPulls(gitHubContext, pullFilter)
        let issues = try client.loadIssues(gitHubContext, issueFilter)
        let reviewRequests = try client.loadReviewRequests(gitHubContext, reviewFilter)

        switch refresh {
        case .none:
            return MutationRefreshPayload(
                pulls: pulls,
                issues: issues,
                reviewRequests: reviewRequests,
                pullDetail: nil,
                issueDetail: nil
            )
        case let .issue(number):
            guard let number else {
                return MutationRefreshPayload(
                    pulls: pulls,
                    issues: issues,
                    reviewRequests: reviewRequests,
                    pullDetail: nil,
                    issueDetail: nil
                )
            }
            let issueDetail = issues.contains(where: { $0.number == number })
                ? try client.loadIssueDetail(gitHubContext, number)
                : nil
            return MutationRefreshPayload(
                pulls: pulls,
                issues: issues,
                reviewRequests: reviewRequests,
                pullDetail: nil,
                issueDetail: issueDetail
            )
        case let .pull(number):
            guard let number else {
                return MutationRefreshPayload(
                    pulls: pulls,
                    issues: issues,
                    reviewRequests: reviewRequests,
                    pullDetail: nil,
                    issueDetail: nil
                )
            }
            let isVisibleInPullCollections = pulls.contains(where: { $0.number == number })
                || reviewRequests.contains(where: { $0.number == number })
            let pullDetail = isVisibleInPullCollections
                ? try client.loadPullDetail(gitHubContext, number)
                : nil
            return MutationRefreshPayload(
                pulls: pulls,
                issues: issues,
                reviewRequests: reviewRequests,
                pullDetail: pullDetail,
                issueDetail: nil
            )
        }
    }

    private nonisolated static func makeIssueDetailFallback(
        from summary: WorkspaceGitHubIssueSummary
    ) -> WorkspaceGitHubIssueDetail {
        WorkspaceGitHubIssueDetail(
            id: summary.id,
            number: summary.number,
            title: summary.title,
            state: summary.state,
            stateReason: summary.stateReason,
            author: summary.author,
            assignees: summary.assignees,
            labels: summary.labels,
            createdAt: summary.createdAt,
            updatedAt: summary.updatedAt,
            url: summary.url
        )
    }

    private struct RefreshPayload: Sendable {
        var gitHubContext: WorkspaceGitHubRepositoryContext
        var authStatus: WorkspaceGitHubAuthStatus
        var pulls: [WorkspaceGitHubPullSummary]
        var issues: [WorkspaceGitHubIssueSummary]
        var reviewRequests: [WorkspaceGitHubReviewRequestSummary]
    }

    private enum MutationRefreshRequest: Equatable, Sendable {
        case none
        case issue(number: Int?)
        case pull(number: Int?)
    }

    private struct MutationRefreshPayload: Sendable {
        var pulls: [WorkspaceGitHubPullSummary]
        var issues: [WorkspaceGitHubIssueSummary]
        var reviewRequests: [WorkspaceGitHubReviewRequestSummary]
        var pullDetail: WorkspaceGitHubPullDetail?
        var issueDetail: WorkspaceGitHubIssueDetail?
    }
}
