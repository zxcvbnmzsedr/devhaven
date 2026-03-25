import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceCommitViewModelTests: XCTestCase {
    func testRefreshChangesSnapshotSeedsInclusionStateFromDefaultFlags() {
        let recorder = WorkspaceCommitClientRecorder()
        recorder.snapshot = WorkspaceCommitChangesSnapshot(
            branchName: "main",
            changes: [
                WorkspaceCommitChange(
                    path: "Sources/App/Main.swift",
                    oldPath: nil,
                    status: .modified,
                    group: .staged,
                    isIncludedByDefault: true
                ),
                WorkspaceCommitChange(
                    path: "README.md",
                    oldPath: nil,
                    status: .modified,
                    group: .unstaged,
                    isIncludedByDefault: false
                ),
            ]
        )
        let viewModel = makeWorkspaceCommitViewModel(recorder: recorder)

        viewModel.refreshChangesSnapshot()

        XCTAssertEqual(viewModel.changesSnapshot?.changes.count, 2)
        XCTAssertEqual(viewModel.includedPaths, Set(["Sources/App/Main.swift"]))
    }

    func testSelectChangeLoadsDiffPreviewAndTracksSelection() {
        let recorder = WorkspaceCommitClientRecorder()
        recorder.snapshot = WorkspaceCommitChangesSnapshot(
            branchName: "main",
            changes: [
                WorkspaceCommitChange(
                    path: "Sources/App/Main.swift",
                    oldPath: nil,
                    status: .modified,
                    group: .unstaged,
                    isIncludedByDefault: false
                ),
            ]
        )
        recorder.diffByPath["Sources/App/Main.swift"] = "diff --git a/Sources/App/Main.swift b/Sources/App/Main.swift\n+line\n"
        let viewModel = makeWorkspaceCommitViewModel(recorder: recorder)
        viewModel.refreshChangesSnapshot()

        viewModel.selectChange("Sources/App/Main.swift")

        XCTAssertEqual(viewModel.selectedChangePath, "Sources/App/Main.swift")
        XCTAssertEqual(viewModel.diffPreview.path, "Sources/App/Main.swift")
        XCTAssertTrue(viewModel.diffPreview.content.contains("diff --git"))
    }

    func testToggleInclusionUpdatesIncludedPathsSet() {
        let recorder = WorkspaceCommitClientRecorder()
        recorder.snapshot = WorkspaceCommitChangesSnapshot(
            branchName: "main",
            changes: [
                WorkspaceCommitChange(
                    path: "README.md",
                    oldPath: nil,
                    status: .modified,
                    group: .unstaged,
                    isIncludedByDefault: false
                ),
            ]
        )
        let viewModel = makeWorkspaceCommitViewModel(recorder: recorder)
        viewModel.refreshChangesSnapshot()

        viewModel.toggleInclusion(for: "README.md")
        XCTAssertEqual(viewModel.includedPaths, Set(["README.md"]))

        viewModel.toggleInclusion(for: "README.md")
        XCTAssertTrue(viewModel.includedPaths.isEmpty)
    }

    func testSelectChangeSurfacesDiffPreviewErrorState() {
        let recorder = WorkspaceCommitClientRecorder()
        recorder.snapshot = WorkspaceCommitChangesSnapshot(
            branchName: "main",
            changes: [
                WorkspaceCommitChange(
                    path: "Sources/App/Main.swift",
                    oldPath: nil,
                    status: .modified,
                    group: .unstaged,
                    isIncludedByDefault: false
                ),
            ]
        )
        recorder.diffErrorByPath["Sources/App/Main.swift"] = WorkspaceCommitViewModelTestError.fixture
        let viewModel = makeWorkspaceCommitViewModel(recorder: recorder)
        viewModel.refreshChangesSnapshot()

        viewModel.selectChange("Sources/App/Main.swift")

        XCTAssertEqual(viewModel.selectedChangePath, "Sources/App/Main.swift")
        XCTAssertEqual(viewModel.diffPreview.path, "Sources/App/Main.swift")
        XCTAssertEqual(viewModel.diffPreview.content, "")
        XCTAssertFalse(viewModel.diffPreview.isLoading)
        XCTAssertEqual(viewModel.diffPreview.errorMessage, WorkspaceCommitViewModelTestError.fixture.errorDescription)
    }

    func testDraftOptionsAndExecutionStateAreMaintainedIndependently() {
        let recorder = WorkspaceCommitClientRecorder()
        recorder.snapshot = WorkspaceCommitChangesSnapshot(
            branchName: "main",
            changes: [
                WorkspaceCommitChange(
                    path: "README.md",
                    oldPath: nil,
                    status: .modified,
                    group: .unstaged,
                    isIncludedByDefault: false
                ),
            ]
        )
        let viewModel = makeWorkspaceCommitViewModel(recorder: recorder)
        viewModel.refreshChangesSnapshot()
        viewModel.setInclusion(for: "README.md", included: true)
        viewModel.updateCommitMessage("feat: add readme updates")
        viewModel.updateOptions(
            WorkspaceCommitOptionsState(
                isAmend: true,
                isSignOff: true,
                author: "DevHaven Bot"
            )
        )

        viewModel.executeCommit(action: .commitAndPush)

        XCTAssertEqual(viewModel.commitMessage, "feat: add readme updates")
        XCTAssertEqual(viewModel.options.author, "DevHaven Bot")
        XCTAssertEqual(viewModel.executionState, .succeeded(.commitAndPush))
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(recorder.requests.first?.includedPaths, ["README.md"])
        XCTAssertEqual(recorder.requests.first?.action, .commitAndPush)
    }

    func testNativeAppViewModelPreparesDedicatedCommitViewModelCacheByRootProjectPath() throws {
        let viewModel = makeNativeAppViewModel()
        let rootPath = "/tmp/root"
        let worktreePath = "/tmp/root-worktree"

        viewModel.snapshot = NativeAppSnapshot(projects: [
            makeProject(
                path: rootPath,
                isGitRepository: true,
                worktrees: [
                    ProjectWorktree(
                        id: "wt",
                        name: "root-worktree",
                        path: worktreePath,
                        branch: "feature/demo",
                        inheritConfig: true,
                        created: 1
                    ),
                ]
            ),
        ])
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: rootPath,
                rootProjectPath: rootPath,
                controller: GhosttyWorkspaceController(projectPath: rootPath)
            ),
            OpenWorkspaceSessionState(
                projectPath: worktreePath,
                rootProjectPath: rootPath,
                controller: GhosttyWorkspaceController(projectPath: worktreePath)
            ),
        ]

        viewModel.activeWorkspaceProjectPath = worktreePath
        viewModel.workspaceToolWindowState.activeKind = .commit
        viewModel.syncActiveWorkspaceToolWindowContext()
        let worktreeCommitViewModel = try XCTUnwrap(viewModel.activeWorkspaceCommitViewModel)

        XCTAssertEqual(worktreeCommitViewModel.repositoryContext.repositoryPath, rootPath)
        XCTAssertEqual(worktreeCommitViewModel.repositoryContext.executionPath, worktreePath)

        viewModel.activeWorkspaceProjectPath = rootPath
        viewModel.syncActiveWorkspaceToolWindowContext()
        let rootCommitViewModel = try XCTUnwrap(viewModel.activeWorkspaceCommitViewModel)
        XCTAssertTrue(worktreeCommitViewModel === rootCommitViewModel)
    }

    private func makeWorkspaceCommitViewModel(recorder: WorkspaceCommitClientRecorder) -> WorkspaceCommitViewModel {
        WorkspaceCommitViewModel(
            repositoryContext: WorkspaceCommitRepositoryContext(
                rootProjectPath: "/tmp/root",
                repositoryPath: "/tmp/root",
                executionPath: "/tmp/root"
            ),
            client: recorder.client
        )
    }

    private func makeNativeAppViewModel() -> NativeAppViewModel {
        NativeAppViewModel(
            store: LegacyCompatStore(homeDirectoryURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)),
            projectDocumentLoader: { _ in
                ProjectDocumentSnapshot(notes: nil, todoItems: [], readmeFallback: nil)
            },
            gitDailyCollector: { _, _ in [] },
            gitDailyCollectorAsync: { _, _, _ in [] }
        )
    }

    private func makeProject(path: String, isGitRepository: Bool, worktrees: [ProjectWorktree] = []) -> Project {
        Project(
            id: "project-\(path)",
            name: URL(fileURLWithPath: path).lastPathComponent,
            path: path,
            tags: [],
            scripts: [],
            worktrees: worktrees,
            mtime: 1,
            size: 0,
            checksum: "checksum",
            isGitRepository: isGitRepository,
            gitCommits: 0,
            gitLastCommit: 0,
            created: 1,
            checked: 1
        )
    }
}

private final class WorkspaceCommitClientRecorder: @unchecked Sendable {
    var snapshot = WorkspaceCommitChangesSnapshot(branchName: nil, changes: [])
    var diffByPath: [String: String] = [:]
    var diffErrorByPath: [String: Error] = [:]
    private(set) var requests: [WorkspaceCommitExecutionRequest] = []

    var client: WorkspaceCommitViewModel.Client {
        .init(
            loadChangesSnapshot: { [weak self] _ in
                self?.snapshot ?? WorkspaceCommitChangesSnapshot(branchName: nil, changes: [])
            },
            loadDiffPreview: { [weak self] _, path in
                if let error = self?.diffErrorByPath[path] {
                    throw error
                }
                return self?.diffByPath[path] ?? ""
            },
            executeCommit: { [weak self] _, request in
                self?.requests.append(request)
            }
        )
    }
}

private enum WorkspaceCommitViewModelTestError: LocalizedError {
    case fixture

    var errorDescription: String? {
        switch self {
        case .fixture:
            return "fixture diff error"
        }
    }
}
