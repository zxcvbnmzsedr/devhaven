import Foundation
import XCTest
@testable import DevHavenCore

final class WorkspaceGitHubViewModelTests: XCTestCase {
    @MainActor
    func testAddCommentToSelectedIssueRefreshesDetailAndClearsDraft() async throws {
        let now = Date(timeIntervalSince1970: 1_716_000_000)
        let recorder = GitHubActionRecorder()
        let issueSummary = Self.makeIssueSummary(number: 56, title: "Fix login bug", commentsCount: 0, updatedAt: now)
        let refreshedIssueSummary = Self.makeIssueSummary(number: 56, title: "Fix login bug", commentsCount: 1, updatedAt: now.addingTimeInterval(60))
        let initialIssueDetail = Self.makeIssueDetail(
            number: 56,
            title: "Fix login bug",
            comments: [],
            updatedAt: now
        )
        let refreshedIssueDetail = Self.makeIssueDetail(
            number: 56,
            title: "Fix login bug",
            comments: [
                WorkspaceGitHubComment(
                    id: "comment-1",
                    author: WorkspaceGitHubActor(login: "tester"),
                    body: "ship it",
                    createdAt: now.addingTimeInterval(60),
                    url: "https://example.com/comment-1"
                )
            ],
            updatedAt: now.addingTimeInterval(60)
        )
        let issueDetails = LockedState([initialIssueDetail, refreshedIssueDetail])
        let issueSummaries = LockedState([issueSummary, refreshedIssueSummary])

        let viewModel = WorkspaceGitHubViewModel(
            repositoryContext: Self.repositoryContext,
            executionPath: "/tmp/devhaven-worktree",
            section: .issues,
            client: Self.makeClient(
                loadIssues: { _, _ in [issueSummaries.next()] },
                loadIssueDetail: { _, _ in issueDetails.next() },
                addIssueComment: { _, number, body in
                    recorder.issueCommentNumber = number
                    recorder.issueCommentBody = body
                }
            )
        )

        viewModel.refresh()
        let didLoadDetail = await waitUntil(timeout: 1) { viewModel.selectedIssueDetail?.number == 56 }
        XCTAssertTrue(didLoadDetail)

        viewModel.issueCommentDraft = "ship it"
        viewModel.addCommentToSelectedIssue()

        let didRefreshComment = await waitUntil(timeout: 1) {
            recorder.issueCommentBody == "ship it"
                && viewModel.lastSuccessfulMutation == .addIssueComment
                && viewModel.issueCommentDraft.isEmpty
                && viewModel.selectedIssueDetail?.commentsCount == 1
        }
        XCTAssertTrue(didRefreshComment)
        XCTAssertEqual(recorder.issueCommentNumber, 56)
        XCTAssertNil(viewModel.mutationErrorMessage)
    }

    @MainActor
    func testCreateAndCheckoutBranchForSelectedIssueUsesExecutionPath() async throws {
        let issueDetail = Self.makeIssueDetail(number: 56, title: "Fix login bug", comments: [], updatedAt: Self.now)
        let recorder = GitHubActionRecorder()

        let viewModel = WorkspaceGitHubViewModel(
            repositoryContext: Self.repositoryContext,
            executionPath: "/tmp/devhaven-worktree",
            section: .issues,
            client: Self.makeClient(
                loadIssues: { _, _ in [Self.makeIssueSummary(number: 56, title: "Fix login bug", commentsCount: 0, updatedAt: Self.now)] },
                loadIssueDetail: { _, _ in issueDetail },
                createLocalBranch: { path, name, startPoint in
                    recorder.createdBranchPath = path
                    recorder.createdBranchName = name
                    recorder.createdBranchStartPoint = startPoint
                },
                checkoutLocalBranch: { path, name in
                    recorder.checkedOutBranchPath = path
                    recorder.checkedOutBranchName = name
                }
            )
        )

        viewModel.refresh()
        let didLoadDetail = await waitUntil(timeout: 1) { viewModel.selectedIssueDetail?.number == 56 }
        XCTAssertTrue(didLoadDetail)

        viewModel.createAndCheckoutBranchForSelectedIssue()

        let didCreateBranch = await waitUntil(timeout: 1) {
            recorder.createdBranchName == "issue/56-fix-login-bug"
                && recorder.checkedOutBranchName == "issue/56-fix-login-bug"
                && viewModel.lastSuccessfulMutation == .createIssueBranch
        }
        XCTAssertTrue(didCreateBranch)
        XCTAssertEqual(recorder.createdBranchPath, "/tmp/devhaven-worktree")
        XCTAssertEqual(recorder.checkedOutBranchPath, "/tmp/devhaven-worktree")
        XCTAssertNil(recorder.createdBranchStartPoint)
    }

    @MainActor
    func testMergeSelectedPullRefreshesPullDetail() async throws {
        let recorder = GitHubActionRecorder()
        let initialSummary = Self.makePullSummary(number: 42, state: .open, updatedAt: Self.now)
        let refreshedSummary = Self.makePullSummary(number: 42, state: .merged, updatedAt: Self.now.addingTimeInterval(60))
        let pullSummaries = LockedState([initialSummary, refreshedSummary])
        let pullDetails = LockedState([
            Self.makePullDetail(number: 42, state: .open, reviewDecision: .reviewRequired, updatedAt: Self.now),
            Self.makePullDetail(number: 42, state: .merged, reviewDecision: .approved, updatedAt: Self.now.addingTimeInterval(60)),
        ])

        let viewModel = WorkspaceGitHubViewModel(
            repositoryContext: Self.repositoryContext,
            executionPath: "/tmp/devhaven-root",
            section: .pulls,
            client: Self.makeClient(
                loadPulls: { _, _ in [pullSummaries.next()] },
                loadPullDetail: { _, _ in pullDetails.next() },
                mergePull: { _, number, method in
                    recorder.mergedPullNumber = number
                    recorder.mergeMethod = method
                }
            )
        )

        viewModel.refresh()
        let didLoadDetail = await waitUntil(timeout: 1) { viewModel.selectedPullDetail?.number == 42 }
        XCTAssertTrue(didLoadDetail)

        viewModel.mergeSelectedPull()

        let didMergePull = await waitUntil(timeout: 1) {
            recorder.mergedPullNumber == 42
                && recorder.mergeMethod == .merge
                && viewModel.selectedPullDetail?.state == .merged
                && viewModel.lastSuccessfulMutation == .mergePull(.merge)
        }
        XCTAssertTrue(didMergePull)
    }

    @MainActor
    func testSubmitReviewForSelectedPullRefreshesReviewSection() async throws {
        let recorder = GitHubActionRecorder()
        let reviews = LockedState([
            Self.makeReviewSummary(number: 9, state: .open, updatedAt: Self.now),
            Self.makeReviewSummary(number: 9, state: .open, updatedAt: Self.now.addingTimeInterval(60)),
        ])
        let pullDetails = LockedState([
            Self.makePullDetail(number: 9, state: .open, reviewDecision: .reviewRequired, updatedAt: Self.now),
            Self.makePullDetail(number: 9, state: .open, reviewDecision: .changesRequested, updatedAt: Self.now.addingTimeInterval(60)),
        ])

        let viewModel = WorkspaceGitHubViewModel(
            repositoryContext: Self.repositoryContext,
            executionPath: "/tmp/devhaven-worktree",
            section: .reviews,
            client: Self.makeClient(
                loadReviewRequests: { _, _ in [reviews.next()] },
                loadPullDetail: { _, _ in pullDetails.next() },
                submitReview: { _, number, event, body in
                    recorder.reviewPullNumber = number
                    recorder.reviewEvent = event
                    recorder.reviewBody = body
                }
            )
        )

        viewModel.refresh()
        let didLoadDetail = await waitUntil(timeout: 1) { viewModel.selectedPullDetail?.number == 9 }
        XCTAssertTrue(didLoadDetail)

        viewModel.reviewCommentDraft = "please fix the failing test"
        viewModel.submitReviewForSelectedPull(event: .requestChanges)

        let didSubmitReview = await waitUntil(timeout: 1) {
            recorder.reviewPullNumber == 9
                && recorder.reviewEvent == .requestChanges
                && recorder.reviewBody == "please fix the failing test"
                && viewModel.reviewCommentDraft.isEmpty
                && viewModel.selectedPullDetail?.reviewDecision == .changesRequested
                && viewModel.lastSuccessfulMutation == .submitReview(.requestChanges)
        }
        XCTAssertTrue(didSubmitReview)
    }

    private static func makeClient(
        loadPulls: @escaping @Sendable (WorkspaceGitHubRepositoryContext, WorkspaceGitHubPullFilter) throws -> [WorkspaceGitHubPullSummary] = { _, _ in [] },
        loadIssues: @escaping @Sendable (WorkspaceGitHubRepositoryContext, WorkspaceGitHubIssueFilter) throws -> [WorkspaceGitHubIssueSummary] = { _, _ in [] },
        loadReviewRequests: @escaping @Sendable (WorkspaceGitHubRepositoryContext, WorkspaceGitHubReviewFilter) throws -> [WorkspaceGitHubReviewRequestSummary] = { _, _ in [] },
        loadPullDetail: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> WorkspaceGitHubPullDetail = { _, number in
            makePullDetail(number: number, state: .open, reviewDecision: .none, updatedAt: now)
        },
        loadIssueDetail: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> WorkspaceGitHubIssueDetail = { _, number in
            makeIssueDetail(number: number, title: "Issue \(number)", comments: [], updatedAt: now)
        },
        addIssueComment: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int, String) throws -> Void = { _, _, _ in },
        closeIssue: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> Void = { _, _ in },
        reopenIssue: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> Void = { _, _ in },
        createLocalBranch: @escaping @Sendable (String, String, String?) throws -> Void = { _, _, _ in },
        checkoutLocalBranch: @escaping @Sendable (String, String) throws -> Void = { _, _ in },
        addPullComment: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int, String) throws -> Void = { _, _, _ in },
        closePull: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> Void = { _, _ in },
        reopenPull: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int) throws -> Void = { _, _ in },
        mergePull: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int, WorkspaceGitHubPullMergeMethod) throws -> Void = { _, _, _ in },
        checkoutPullBranch: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int, String) throws -> Void = { _, _, _ in },
        submitReview: @escaping @Sendable (WorkspaceGitHubRepositoryContext, Int, WorkspaceGitHubReviewSubmissionEvent, String?) throws -> Void = { _, _, _, _ in }
    ) -> WorkspaceGitHubViewModel.Client {
        WorkspaceGitHubViewModel.Client(
            resolveRepositoryContext: { _ in repositoryGitHubContext },
            loadAuthStatus: { _ in WorkspaceGitHubAuthStatus(host: "github.com", state: .authenticated, activeLogin: "tester") },
            loadPulls: loadPulls,
            loadIssues: loadIssues,
            loadReviewRequests: loadReviewRequests,
            loadPullDetail: loadPullDetail,
            loadIssueDetail: loadIssueDetail,
            addIssueComment: addIssueComment,
            closeIssue: closeIssue,
            reopenIssue: reopenIssue,
            createLocalBranch: createLocalBranch,
            checkoutLocalBranch: checkoutLocalBranch,
            addPullComment: addPullComment,
            closePull: closePull,
            reopenPull: reopenPull,
            mergePull: mergePull,
            checkoutPullBranch: checkoutPullBranch,
            submitReview: submitReview
        )
    }

    private static func makeIssueSummary(
        number: Int,
        title: String,
        commentsCount: Int,
        updatedAt: Date
    ) -> WorkspaceGitHubIssueSummary {
        WorkspaceGitHubIssueSummary(
            id: "issue-\(number)",
            number: number,
            title: title,
            state: .open,
            author: WorkspaceGitHubActor(login: "tester"),
            commentsCount: commentsCount,
            createdAt: now,
            updatedAt: updatedAt,
            url: "https://example.com/issues/\(number)"
        )
    }

    private static func makeIssueDetail(
        number: Int,
        title: String,
        comments: [WorkspaceGitHubComment],
        updatedAt: Date
    ) -> WorkspaceGitHubIssueDetail {
        WorkspaceGitHubIssueDetail(
            id: "issue-\(number)",
            number: number,
            title: title,
            state: .open,
            author: WorkspaceGitHubActor(login: "tester"),
            body: "Issue body",
            createdAt: now,
            updatedAt: updatedAt,
            url: "https://example.com/issues/\(number)",
            comments: comments
        )
    }

    private static func makePullSummary(
        number: Int,
        state: WorkspaceGitHubPullState,
        updatedAt: Date
    ) -> WorkspaceGitHubPullSummary {
        WorkspaceGitHubPullSummary(
            id: "pull-\(number)",
            number: number,
            title: "PR \(number)",
            state: state,
            isDraft: false,
            author: WorkspaceGitHubActor(login: "tester"),
            createdAt: now,
            updatedAt: updatedAt,
            url: "https://example.com/pulls/\(number)",
            headRefName: "feature/\(number)",
            baseRefName: "main"
        )
    }

    private static func makeReviewSummary(
        number: Int,
        state: WorkspaceGitHubPullState,
        updatedAt: Date
    ) -> WorkspaceGitHubReviewRequestSummary {
        WorkspaceGitHubReviewRequestSummary(
            id: "review-\(number)",
            number: number,
            title: "Review \(number)",
            state: state,
            isDraft: false,
            author: WorkspaceGitHubActor(login: "reviewer"),
            createdAt: now,
            updatedAt: updatedAt,
            url: "https://example.com/reviews/\(number)"
        )
    }

    private static func makePullDetail(
        number: Int,
        state: WorkspaceGitHubPullState,
        reviewDecision: WorkspaceGitHubReviewDecision,
        updatedAt: Date
    ) -> WorkspaceGitHubPullDetail {
        WorkspaceGitHubPullDetail(
            id: "pull-\(number)",
            number: number,
            title: "PR \(number)",
            state: state,
            isDraft: false,
            author: WorkspaceGitHubActor(login: "tester"),
            reviewDecision: reviewDecision,
            mergeStateStatus: state == .open ? .clean : .blocked,
            body: "Pull body",
            createdAt: now,
            updatedAt: updatedAt,
            mergedAt: state == .merged ? updatedAt : nil,
            mergedBy: state == .merged ? WorkspaceGitHubActor(login: "merger") : nil,
            url: "https://example.com/pulls/\(number)",
            headRefName: "feature/\(number)",
            baseRefName: "main",
            changedFiles: 3,
            comments: [],
            commits: []
        )
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    private static let now = Date(timeIntervalSince1970: 1_716_000_000)
    private static let repositoryContext = WorkspaceGitRepositoryContext(
        rootProjectPath: "/tmp/devhaven-root",
        repositoryPath: "/tmp/devhaven-root"
    )
    private static let repositoryGitHubContext = WorkspaceGitHubRepositoryContext(
        rootProjectPath: "/tmp/devhaven-root",
        repositoryPath: "/tmp/devhaven-root",
        remoteName: "origin",
        remoteURL: "git@github.com:octo/devhaven.git",
        host: "github.com",
        owner: "octo",
        name: "devhaven"
    )
}

private final class GitHubActionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storageIssueCommentBody: String?
    private var storageIssueCommentNumber: Int?
    private var storageCreatedBranchPath: String?
    private var storageCreatedBranchName: String?
    private var storageCreatedBranchStartPoint: String?
    private var storageCheckedOutBranchPath: String?
    private var storageCheckedOutBranchName: String?
    private var storageMergedPullNumber: Int?
    private var storageMergeMethod: WorkspaceGitHubPullMergeMethod?
    private var storageReviewPullNumber: Int?
    private var storageReviewEvent: WorkspaceGitHubReviewSubmissionEvent?
    private var storageReviewBody: String?

    var issueCommentBody: String? {
        get { withLock { storageIssueCommentBody } }
        set { withLock { storageIssueCommentBody = newValue } }
    }

    var issueCommentNumber: Int? {
        get { withLock { storageIssueCommentNumber } }
        set { withLock { storageIssueCommentNumber = newValue } }
    }

    var createdBranchPath: String? {
        get { withLock { storageCreatedBranchPath } }
        set { withLock { storageCreatedBranchPath = newValue } }
    }

    var createdBranchName: String? {
        get { withLock { storageCreatedBranchName } }
        set { withLock { storageCreatedBranchName = newValue } }
    }

    var createdBranchStartPoint: String? {
        get { withLock { storageCreatedBranchStartPoint } }
        set { withLock { storageCreatedBranchStartPoint = newValue } }
    }

    var checkedOutBranchPath: String? {
        get { withLock { storageCheckedOutBranchPath } }
        set { withLock { storageCheckedOutBranchPath = newValue } }
    }

    var checkedOutBranchName: String? {
        get { withLock { storageCheckedOutBranchName } }
        set { withLock { storageCheckedOutBranchName = newValue } }
    }

    var mergedPullNumber: Int? {
        get { withLock { storageMergedPullNumber } }
        set { withLock { storageMergedPullNumber = newValue } }
    }

    var mergeMethod: WorkspaceGitHubPullMergeMethod? {
        get { withLock { storageMergeMethod } }
        set { withLock { storageMergeMethod = newValue } }
    }

    var reviewPullNumber: Int? {
        get { withLock { storageReviewPullNumber } }
        set { withLock { storageReviewPullNumber = newValue } }
    }

    var reviewEvent: WorkspaceGitHubReviewSubmissionEvent? {
        get { withLock { storageReviewEvent } }
        set { withLock { storageReviewEvent = newValue } }
    }

    var reviewBody: String? {
        get { withLock { storageReviewBody } }
        set { withLock { storageReviewBody = newValue } }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class LockedState<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [T]

    init(_ values: [T]) {
        self.values = values
    }

    func next() -> T {
        lock.lock()
        defer { lock.unlock() }
        if values.count > 1 {
            return values.removeFirst()
        }
        guard let last = values.last else {
            fatalError("LockedState 至少需要一个值")
        }
        return last
    }
}
