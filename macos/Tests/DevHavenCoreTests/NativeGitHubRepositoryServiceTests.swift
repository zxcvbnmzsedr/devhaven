import XCTest
@testable import DevHavenCore

final class NativeGitHubRepositoryServiceTests: XCTestCase {
    func testAddIssueCommentRejectsEmptyBody() throws {
        let service = makeService { _, _, _, _ in
            XCTFail("空评论不应触发 gh 命令")
            return .init(command: [], stdout: "", stderr: "", exitCode: 0)
        }

        XCTAssertThrowsError(
            try service.addIssueComment(in: Self.repositoryContext, number: 42, body: "   \n")
        ) { error in
            XCTAssertEqual(
                error as? WorkspaceGitHubCommandError,
                .operationRejected("评论内容不能为空")
            )
        }
    }

    func testMergePullRunsMergeCommand() throws {
        let capture = CommandCapture()
        let service = makeService { arguments, repositoryPath, _, _ in
            capture.record(arguments: arguments, repositoryPath: repositoryPath)
            return .init(command: ["/usr/bin/env", "gh"] + arguments, stdout: "", stderr: "", exitCode: 0)
        }

        try service.mergePull(in: Self.repositoryContext, number: 108)

        XCTAssertEqual(capture.arguments, ["pr", "merge", "108", "-R", "octo/devhaven", "--merge"])
        XCTAssertEqual(capture.repositoryPath, "/tmp/devhaven-root")
    }

    func testCheckoutPullBranchUsesExecutionPath() throws {
        let capture = CommandCapture()
        let service = makeService { arguments, repositoryPath, _, _ in
            capture.record(arguments: arguments, repositoryPath: repositoryPath)
            return .init(command: ["/usr/bin/env", "gh"] + arguments, stdout: "", stderr: "", exitCode: 0)
        }

        try service.checkoutPullBranch(
            in: Self.repositoryContext,
            number: 9,
            at: "/tmp/devhaven-worktree"
        )

        XCTAssertEqual(capture.arguments, ["pr", "checkout", "9", "-R", "octo/devhaven"])
        XCTAssertEqual(capture.repositoryPath, "/tmp/devhaven-worktree")
    }

    func testSubmitReviewRequestChangesRejectsEmptyBody() throws {
        let service = makeService { _, _, _, _ in
            XCTFail("空 review 说明不应触发 gh 命令")
            return .init(command: [], stdout: "", stderr: "", exitCode: 0)
        }

        XCTAssertThrowsError(
            try service.submitReview(
                in: Self.repositoryContext,
                number: 13,
                event: .requestChanges,
                body: "   "
            )
        ) { error in
            XCTAssertEqual(
                error as? WorkspaceGitHubCommandError,
                .operationRejected("请求修改时请填写说明")
            )
        }
    }

    func testSubmitApproveReviewAllowsEmptyBody() throws {
        let capture = CommandCapture()
        let service = makeService { arguments, repositoryPath, _, _ in
            capture.record(arguments: arguments, repositoryPath: repositoryPath)
            return .init(command: ["/usr/bin/env", "gh"] + arguments, stdout: "", stderr: "", exitCode: 0)
        }

        try service.submitReview(
            in: Self.repositoryContext,
            number: 21,
            event: .approve,
            body: nil
        )

        XCTAssertEqual(capture.arguments, ["pr", "review", "21", "-R", "octo/devhaven", "--approve"])
        XCTAssertEqual(capture.repositoryPath, "/tmp/devhaven-root")
    }

    private func makeService(
        _ executeOverride: @escaping NativeGitHubCommandRunner.Execution
    ) -> NativeGitHubRepositoryService {
        NativeGitHubRepositoryService(
            runner: NativeGitHubCommandRunner(executeOverride: executeOverride)
        )
    }

    private static let repositoryContext = WorkspaceGitHubRepositoryContext(
        rootProjectPath: "/tmp/devhaven-root",
        repositoryPath: "/tmp/devhaven-root",
        remoteName: "origin",
        remoteURL: "git@github.com:octo/devhaven.git",
        host: "github.com",
        owner: "octo",
        name: "devhaven"
    )
}

private final class CommandCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storageArguments = [String]()
    private var storageRepositoryPath = ""

    var arguments: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storageArguments
    }

    var repositoryPath: String {
        lock.lock()
        defer { lock.unlock() }
        return storageRepositoryPath
    }

    func record(arguments: [String], repositoryPath: String) {
        lock.lock()
        storageArguments = arguments
        storageRepositoryPath = repositoryPath
        lock.unlock()
    }
}
