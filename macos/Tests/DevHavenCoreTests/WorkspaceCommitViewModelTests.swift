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

    func testSelectChangeLoadsDiffPreviewAndTracksSelection() async throws {
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
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.selectedChangePath, "Sources/App/Main.swift")
        XCTAssertEqual(viewModel.diffPreview.path, "Sources/App/Main.swift")
        XCTAssertFalse(viewModel.diffPreview.isLoading)
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

    func testToggleAllInclusionSelectsAndClearsAllVisibleChanges() {
        let recorder = WorkspaceCommitClientRecorder()
        recorder.snapshot = WorkspaceCommitChangesSnapshot(
            branchName: "main",
            changes: [
                WorkspaceCommitChange(
                    path: "README.md",
                    oldPath: nil,
                    status: .modified,
                    group: .staged,
                    isIncludedByDefault: true
                ),
                WorkspaceCommitChange(
                    path: "Sources/App/Main.swift",
                    oldPath: nil,
                    status: .added,
                    group: .unstaged,
                    isIncludedByDefault: false
                ),
            ]
        )
        let viewModel = makeWorkspaceCommitViewModel(recorder: recorder)
        viewModel.refreshChangesSnapshot()

        XCTAssertEqual(viewModel.includedPaths, Set(["README.md"]))

        viewModel.toggleAllInclusion()
        XCTAssertEqual(viewModel.includedPaths, Set(["README.md", "Sources/App/Main.swift"]))

        viewModel.toggleAllInclusion()
        XCTAssertTrue(viewModel.includedPaths.isEmpty)
    }

    func testSelectChangeSurfacesDiffPreviewErrorState() async throws {
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
        try await Task.sleep(for: .milliseconds(50))

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

    func testCommitPanelLegendSummarizesBranchIncludedAndExecutionState() {
        let recorder = WorkspaceCommitClientRecorder()
        recorder.snapshot = WorkspaceCommitChangesSnapshot(
            branchName: "feature/task6",
            changes: [
                WorkspaceCommitChange(
                    path: "README.md",
                    oldPath: nil,
                    status: .modified,
                    group: .staged,
                    isIncludedByDefault: true
                ),
            ]
        )
        let viewModel = makeWorkspaceCommitViewModel(recorder: recorder)
        viewModel.refreshChangesSnapshot()

        XCTAssertEqual(viewModel.commitStatusLegend, "分支 feature/task6 · Included 1 · 就绪")

        viewModel.executionState = .running(.commit)
        XCTAssertEqual(viewModel.commitStatusLegend, "分支 feature/task6 · Included 1 · 执行中")
    }

    func testCanExecuteCommitRequiresIncludedPathsMessageAndNonRunningState() {
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

        XCTAssertFalse(viewModel.canExecuteCommit(action: .commit))

        viewModel.toggleInclusion(for: "README.md")
        XCTAssertFalse(viewModel.canExecuteCommit(action: .commit))

        viewModel.updateCommitMessage("feat: add commit panel")
        XCTAssertTrue(viewModel.canExecuteCommit(action: .commit))

        viewModel.executionState = .running(.commit)
        XCTAssertFalse(viewModel.canExecuteCommit(action: .commit))
    }

    func testDraftUpdatesNormalizeOptionsAndResetStaleExecutionFeedback() {
        let recorder = WorkspaceCommitClientRecorder()
        let viewModel = makeWorkspaceCommitViewModel(recorder: recorder)
        viewModel.executionState = .failed("commit failed")
        viewModel.errorMessage = "commit failed"

        viewModel.updateCommitMessage("feat: add commit panel")
        XCTAssertEqual(viewModel.executionState, .idle)
        XCTAssertNil(viewModel.errorMessage)

        viewModel.executionState = .succeeded(.commit)
        viewModel.updateOptionAmend(true)
        XCTAssertTrue(viewModel.options.isAmend)
        XCTAssertEqual(viewModel.executionState, .idle)

        viewModel.executionState = .failed("failed again")
        viewModel.errorMessage = "failed again"
        viewModel.updateOptionSignOff(true)
        XCTAssertTrue(viewModel.options.isSignOff)
        XCTAssertEqual(viewModel.executionState, .idle)
        XCTAssertNil(viewModel.errorMessage)

        viewModel.updateOptionAuthor("  DevHaven Bot  ")
        XCTAssertEqual(viewModel.options.author, "DevHaven Bot")

        viewModel.updateOptionAuthor("   ")
        XCTAssertNil(viewModel.options.author)
    }

    func testExecuteCommitFailureSurfacesFailedState() {
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
        recorder.executeError = WorkspaceCommitViewModelTestError.fixture
        let viewModel = makeWorkspaceCommitViewModel(recorder: recorder)
        viewModel.refreshChangesSnapshot()
        viewModel.toggleInclusion(for: "README.md")
        viewModel.updateCommitMessage("feat: failing commit")

        viewModel.executeCommit(action: .commit)

        XCTAssertEqual(viewModel.executionState, .failed(WorkspaceCommitViewModelTestError.fixture.errorDescription ?? ""))
        XCTAssertEqual(viewModel.errorMessage, WorkspaceCommitViewModelTestError.fixture.errorDescription)
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
        viewModel.showWorkspaceSideToolWindow(.commit)
        viewModel.syncActiveWorkspaceToolWindowContext()
        let worktreeCommitViewModel = try XCTUnwrap(viewModel.activeWorkspaceCommitViewModel)

        XCTAssertEqual(worktreeCommitViewModel.repositoryContext.repositoryPath, rootPath)
        XCTAssertEqual(worktreeCommitViewModel.repositoryContext.executionPath, worktreePath)

        viewModel.activeWorkspaceProjectPath = rootPath
        viewModel.syncActiveWorkspaceToolWindowContext()
        let rootCommitViewModel = try XCTUnwrap(viewModel.activeWorkspaceCommitViewModel)
        XCTAssertTrue(worktreeCommitViewModel === rootCommitViewModel)
    }

    func testUpdateRepositoryContextRefreshesChangesSnapshotWhenExecutionPathChanges() {
        let recorder = WorkspaceCommitClientRecorder()
        recorder.snapshotsByExecutionPath["/tmp/root"] = WorkspaceCommitChangesSnapshot(
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
        recorder.snapshotsByExecutionPath["/tmp/root-worktree"] = WorkspaceCommitChangesSnapshot(
            branchName: "feature/demo",
            changes: [
                WorkspaceCommitChange(
                    path: "Sources/Feature.swift",
                    oldPath: nil,
                    status: .added,
                    group: .staged,
                    isIncludedByDefault: true
                ),
            ]
        )

        let viewModel = makeWorkspaceCommitViewModel(recorder: recorder)
        viewModel.refreshChangesSnapshot()

        XCTAssertEqual(viewModel.changesSnapshot?.changes.map(\.path), ["README.md"])
        XCTAssertEqual(viewModel.includedPaths, [])

        viewModel.updateRepositoryContext(
            WorkspaceCommitRepositoryContext(
                rootProjectPath: "/tmp/root",
                repositoryPath: "/tmp/root",
                executionPath: "/tmp/root-worktree"
            )
        )

        XCTAssertEqual(recorder.loadedExecutionPaths, ["/tmp/root", "/tmp/root-worktree"])
        XCTAssertEqual(viewModel.changesSnapshot?.branchName, "feature/demo")
        XCTAssertEqual(viewModel.changesSnapshot?.changes.map(\.path), ["Sources/Feature.swift"])
        XCTAssertEqual(viewModel.includedPaths, Set(["Sources/Feature.swift"]))
    }

    func testRefreshChangesSnapshotPreservesExistingInclusionAndSeedsDefaultsForNewChanges() {
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
                WorkspaceCommitChange(
                    path: "Sources/Keep.swift",
                    oldPath: nil,
                    status: .modified,
                    group: .staged,
                    isIncludedByDefault: true
                ),
            ]
        )
        let viewModel = makeWorkspaceCommitViewModel(recorder: recorder)
        viewModel.refreshChangesSnapshot()
        viewModel.setInclusion(for: "README.md", included: true)
        viewModel.setInclusion(for: "Sources/Keep.swift", included: false)

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
                WorkspaceCommitChange(
                    path: "Sources/Keep.swift",
                    oldPath: nil,
                    status: .modified,
                    group: .staged,
                    isIncludedByDefault: true
                ),
                WorkspaceCommitChange(
                    path: "Sources/New.swift",
                    oldPath: nil,
                    status: .added,
                    group: .staged,
                    isIncludedByDefault: true
                ),
            ]
        )

        viewModel.refreshChangesSnapshot()

        XCTAssertEqual(
            viewModel.includedPaths,
            Set(["README.md", "Sources/New.swift"]),
            "自动刷新不应覆盖用户对现有文件的 inclusion 选择，但应对新增文件继续采用默认 inclusion"
        )
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
            runConfigurations: [],
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
    var snapshotsByExecutionPath: [String: WorkspaceCommitChangesSnapshot] = [:]
    var diffByPath: [String: String] = [:]
    var diffErrorByPath: [String: Error] = [:]
    var executeError: Error?
    private(set) var loadedExecutionPaths: [String] = []
    private(set) var requests: [WorkspaceCommitExecutionRequest] = []

    var client: WorkspaceCommitViewModel.Client {
        .init(
            loadChangesSnapshot: { [weak self] executionPath in
                self?.loadedExecutionPaths.append(executionPath)
                if let snapshot = self?.snapshotsByExecutionPath[executionPath] {
                    return snapshot
                }
                return self?.snapshot ?? WorkspaceCommitChangesSnapshot(branchName: nil, changes: [])
            },
            loadDiffPreview: { [weak self] _, path in
                if let error = self?.diffErrorByPath[path] {
                    throw error
                }
                return self?.diffByPath[path] ?? ""
            },
            executeCommit: { [weak self] _, request in
                if let error = self?.executeError {
                    throw error
                }
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
