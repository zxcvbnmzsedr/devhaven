import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceGitViewModelTests: XCTestCase {
    func testWorkspaceGitModelsSourceContractSeparatesCommitSideAndGitBottomPlacements() throws {
        let source = try String(contentsOf: workspaceGitModelsSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("case commit"), "WorkspaceToolWindowKind 应新增 commit")
        XCTAssertTrue(source.contains("case side"), "WorkspaceToolWindowPlacement 应显式支持侧边工具窗停靠")
        XCTAssertTrue(source.contains("case bottom"), "WorkspaceToolWindowPlacement 应继续支持底部工具窗停靠")
        XCTAssertTrue(source.contains("case .commit:\n            return .side"), "Commit 工具窗的默认停靠位置应为侧边")
        XCTAssertTrue(source.contains("case .git:\n            return .bottom"), "Git 工具窗的默认停靠位置应为底部")
        XCTAssertFalse(source.contains("case changes"), "WorkspaceGitSection 不应继续包含 changes")
    }

    func testNativeAppViewModelReplacesPrimaryModeWithSideAndBottomToolWindowRuntimeStateSourceContract() throws {
        let source = try String(contentsOf: nativeAppViewModelSourceFileURL(), encoding: .utf8)
        let modelsSource = try String(contentsOf: workspaceGitModelsSourceFileURL(), encoding: .utf8)

        XCTAssertFalse(source.contains("public var workspacePrimaryMode"), "NativeAppViewModel 不应继续暴露 workspacePrimaryMode 成员")
        XCTAssertFalse(source.contains("self.workspacePrimaryMode ="), "NativeAppViewModel 初始化时不应继续写入旧的 primary mode 真相源")
        XCTAssertTrue(source.contains("workspaceSideToolWindowState"), "NativeAppViewModel 应提供侧边 tool window runtime state")
        XCTAssertTrue(source.contains("workspaceBottomToolWindowState"), "NativeAppViewModel 应提供底部 tool window runtime state")
        XCTAssertTrue(source.contains("WorkspaceFocusedArea"), "NativeAppViewModel 应提供 focused area 真相源")
        XCTAssertTrue(modelsSource.contains("case sideToolWindow("), "WorkspaceFocusedArea 应显式表示侧边工具窗焦点")
        XCTAssertTrue(modelsSource.contains("case bottomToolWindow("), "WorkspaceFocusedArea 应显式表示底部工具窗焦点")
    }

    func testNativeAppViewModelProvidesSideAndBottomToolWindowEntryPointsSourceContract() throws {
        let source = try String(contentsOf: nativeAppViewModelSourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("toggleWorkspaceToolWindow("))
        XCTAssertTrue(source.contains("showWorkspaceSideToolWindow("))
        XCTAssertTrue(source.contains("hideWorkspaceSideToolWindow()"))
        XCTAssertTrue(source.contains("updateWorkspaceSideToolWindowWidth("))
        XCTAssertTrue(source.contains("showWorkspaceBottomToolWindow("))
        XCTAssertTrue(source.contains("hideWorkspaceBottomToolWindow()"))
        XCTAssertTrue(source.contains("updateWorkspaceBottomToolWindowHeight("))
    }

    func testSearchQueryDebounce300MillisecondsOnlyAppliesLatestQuery() async throws {
        let recorder = WorkspaceGitClientRecorder()
        let viewModel = makeWorkspaceGitViewModel(recorder: recorder)

        viewModel.updateSearchQuery("fe")
        try await Task.sleep(for: .milliseconds(120))
        viewModel.updateSearchQuery("feat")

        try await Task.sleep(for: .milliseconds(220))
        XCTAssertTrue(recorder.logQueries.isEmpty, "300ms 防抖窗口内不应提前触发读取")

        try await Task.sleep(for: .milliseconds(140))
        XCTAssertEqual(recorder.logQueries, ["feat"])
    }

    func testSwitchingSectionCancelsPreviousReadAndPreventsStaleWriteBack() async throws {
        let recorder = WorkspaceGitClientRecorder()
        recorder.logDelayMilliseconds = 520
        let viewModel = makeWorkspaceGitViewModel(recorder: recorder)

        viewModel.refreshForCurrentSection()
        try await Task.sleep(for: .milliseconds(60))
        viewModel.setSection(.branches)

        try await Task.sleep(for: .milliseconds(760))

        XCTAssertEqual(recorder.readSections, [.log, .branches])
        XCTAssertTrue(viewModel.logSnapshot.commits.isEmpty, "过期 log 结果不应覆盖当前 section 的状态")
    }

    func testNativeAppViewModelCachesWorkspaceGitViewModelByRootProjectPath() throws {
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
        viewModel.prepareActiveWorkspaceGitViewModel()
        let worktreeGitViewModel = try XCTUnwrap(viewModel.activeWorkspaceGitViewModel)

        XCTAssertEqual(worktreeGitViewModel.repositoryContext.repositoryPath, rootPath)
        XCTAssertEqual(worktreeGitViewModel.selectedExecutionWorktree?.path, worktreePath)

        viewModel.activeWorkspaceProjectPath = rootPath
        viewModel.prepareActiveWorkspaceGitViewModel()
        let rootGitViewModel = try XCTUnwrap(viewModel.activeWorkspaceGitViewModel)
        XCTAssertTrue(worktreeGitViewModel === rootGitViewModel)
    }

    func testWorkspaceGitViewModelKeepsIdeaLogViewModelContextInSync() {
        let recorder = WorkspaceGitClientRecorder()
        let viewModel = makeWorkspaceGitViewModel(recorder: recorder)

        XCTAssertEqual(viewModel.logViewModel.repositoryContext.repositoryPath, "/tmp/root")

        viewModel.updateRepositoryContext(
            WorkspaceGitRepositoryContext(
                rootProjectPath: "/tmp/other-root",
                repositoryPath: "/tmp/other-root"
            ),
            executionWorktrees: [
                WorkspaceGitWorktreeContext(
                    path: "/tmp/other-root",
                    displayName: "other-root",
                    branchName: "main",
                    isRootProject: true
                ),
            ]
        )

        XCTAssertEqual(viewModel.logViewModel.repositoryContext.repositoryPath, "/tmp/other-root")
    }

    func testPrepareActiveWorkspaceGitViewModelSkipsQuickTerminalAndNonGitProject() {
        let viewModel = makeNativeAppViewModel()
        let quickPath = "/tmp/home"

        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: quickPath,
                rootProjectPath: quickPath,
                controller: GhosttyWorkspaceController(projectPath: quickPath),
                isQuickTerminal: true
            ),
        ]
        viewModel.activeWorkspaceProjectPath = quickPath
        viewModel.prepareActiveWorkspaceGitViewModel()

        XCTAssertNil(viewModel.activeWorkspaceGitViewModel)

        let nonGitPath = "/tmp/non-git"
        viewModel.snapshot = NativeAppSnapshot(projects: [
            makeProject(path: nonGitPath, isGitRepository: false),
        ])
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: nonGitPath,
                rootProjectPath: nonGitPath,
                controller: GhosttyWorkspaceController(projectPath: nonGitPath)
            ),
        ]
        viewModel.activeWorkspaceProjectPath = nonGitPath
        viewModel.prepareActiveWorkspaceGitViewModel()

        XCTAssertNil(viewModel.activeWorkspaceGitViewModel)
    }

    func testSelectingCommitLoadsCommitDetailAndDiff() async throws {
        let recorder = WorkspaceGitClientRecorder()
        let viewModel = makeWorkspaceGitViewModel(recorder: recorder)

        viewModel.refreshForCurrentSection()
        try await Task.sleep(for: .milliseconds(120))
        viewModel.selectCommit("hash-log")
        try await Task.sleep(for: .milliseconds(160))

        XCTAssertEqual(recorder.loadedCommitHashes, ["hash-log"])
        XCTAssertEqual(viewModel.selectedCommitDetail?.hash, "hash-log")
        XCTAssertTrue(viewModel.selectedCommitDetail?.diff.contains("diff --git") ?? false)
    }

    func testSelectingRevisionFilterRefreshesLogUsingRevisionScope() async throws {
        let recorder = WorkspaceGitClientRecorder()
        let viewModel = makeWorkspaceGitViewModel(recorder: recorder)

        viewModel.selectRevisionFilter("refs/heads/main")
        try await Task.sleep(for: .milliseconds(140))

        XCTAssertEqual(viewModel.selectedRevisionFilter, "refs/heads/main")
        XCTAssertEqual(recorder.logRevisions.last, "refs/heads/main")
    }

    func testSelectingAuthorFilterRefreshesLogUsingAuthorScope() async throws {
        let recorder = WorkspaceGitClientRecorder()
        let viewModel = makeWorkspaceGitViewModel(recorder: recorder)

        viewModel.selectAuthorFilter("DevHaven")
        try await Task.sleep(for: .milliseconds(140))

        XCTAssertEqual(viewModel.selectedAuthorFilter, "DevHaven")
        XCTAssertEqual(recorder.logAuthors.last, "DevHaven")
    }

    func testSelectingDateFilterRefreshesLogUsingSinceScope() async throws {
        let recorder = WorkspaceGitClientRecorder()
        let viewModel = makeWorkspaceGitViewModel(recorder: recorder)

        viewModel.selectDateFilter(.last7Days)
        try await Task.sleep(for: .milliseconds(140))

        XCTAssertEqual(viewModel.selectedDateFilter, .last7Days)
        XCTAssertEqual(recorder.logSinceFilters.last, WorkspaceGitDateFilter.last7Days.gitSinceExpression)
    }

    func testPathFilterDebounceAppliesLatestPathQuery() async throws {
        let recorder = WorkspaceGitClientRecorder()
        let viewModel = makeWorkspaceGitViewModel(recorder: recorder)

        viewModel.updatePathFilterQuery("Source")
        try await Task.sleep(for: .milliseconds(120))
        viewModel.updatePathFilterQuery("Sources/App")

        try await Task.sleep(for: .milliseconds(220))
        XCTAssertTrue(recorder.logPaths.isEmpty, "300ms 防抖窗口内不应提前触发 path 读取")

        try await Task.sleep(for: .milliseconds(140))
        XCTAssertEqual(viewModel.debouncedPathFilterQuery, "Sources/App")
        XCTAssertEqual(recorder.logPaths.last, "Sources/App")
    }

    func testSelectingCommitAutoSelectsFirstChangedFile() async throws {
        let recorder = WorkspaceGitClientRecorder()
        recorder.commitChangedFiles = [
            WorkspaceGitCommitFileChange(path: "Sources/App/Main.swift", status: .modified),
            WorkspaceGitCommitFileChange(path: "Tests/AppTests/MainTests.swift", status: .added),
        ]
        let viewModel = makeWorkspaceGitViewModel(recorder: recorder)

        viewModel.selectCommit("hash-log")
        try await Task.sleep(for: .milliseconds(160))

        XCTAssertEqual(viewModel.selectedFilePath, "Sources/App/Main.swift")

        viewModel.selectCommitFile("Tests/AppTests/MainTests.swift")
        XCTAssertEqual(viewModel.selectedFilePath, "Tests/AppTests/MainTests.swift")
    }

    func testSelectedCommitDiffIsTruncatedBeyondConfiguredLimits() async throws {
        let recorder = WorkspaceGitClientRecorder()
        recorder.commitDiff = Self.largeDiff(lineCount: 2_400)
        let viewModel = makeWorkspaceGitViewModel(recorder: recorder)

        viewModel.selectCommit("hash-log")
        try await Task.sleep(for: .milliseconds(160))

        XCTAssertEqual(viewModel.selectedCommitDetail?.hash, "hash-log")
        XCTAssertTrue(viewModel.isSelectedCommitDiffTruncated)
        XCTAssertNotNil(viewModel.selectedCommitDiffNotice)
        XCTAssertLessThanOrEqual(viewModel.selectedCommitDetail?.diff.split(separator: "\n", omittingEmptySubsequences: false).count ?? 0, 2_000)
    }

    func testUpdateRepositoryContextRefreshesOperationSectionWhenExecutionPathChanges() async throws {
        let recorder = WorkspaceGitClientRecorder()
        recorder.aheadBehindSnapshotsByPath = [
            "/tmp/root": WorkspaceGitAheadBehindSnapshot(upstream: "origin/main", ahead: 0, behind: 1),
            "/tmp/root-worktree": WorkspaceGitAheadBehindSnapshot(upstream: "origin/main", ahead: 2, behind: 3),
        ]
        let viewModel = makeWorkspaceGitViewModel(
            recorder: recorder,
            executionWorktrees: [
                WorkspaceGitWorktreeContext(
                    path: "/tmp/root",
                    displayName: "root",
                    branchName: "main",
                    isRootProject: true
                ),
                WorkspaceGitWorktreeContext(
                    path: "/tmp/root-worktree",
                    displayName: "feature",
                    branchName: "feature/demo",
                    isRootProject: false
                ),
            ]
        )

        viewModel.setSection(.operations)
        try await Task.sleep(for: .milliseconds(140))

        viewModel.updateRepositoryContext(
            WorkspaceGitRepositoryContext(rootProjectPath: "/tmp/root", repositoryPath: "/tmp/root"),
            executionWorktrees: [
                WorkspaceGitWorktreeContext(
                    path: "/tmp/root",
                    displayName: "root",
                    branchName: "main",
                    isRootProject: true
                ),
                WorkspaceGitWorktreeContext(
                    path: "/tmp/root-worktree",
                    displayName: "feature",
                    branchName: "feature/demo",
                    isRootProject: false
                ),
            ],
            preferredExecutionWorktreePath: "/tmp/root-worktree"
        )
        try await Task.sleep(for: .milliseconds(180))

        XCTAssertEqual(viewModel.selectedExecutionWorktree?.path, "/tmp/root-worktree")
        XCTAssertEqual(viewModel.aheadBehindSnapshot.behind, 3)
        XCTAssertGreaterThanOrEqual(recorder.aheadBehindReadCount, 2)
    }

    func testSwitchingExecutionWorktreeRefreshesOperationSnapshot() async throws {
        let recorder = WorkspaceGitClientRecorder()
        recorder.remoteSnapshots = [
            WorkspaceGitRemoteSnapshot(
                name: "origin",
                fetchURL: "git@example.com:demo.git",
                pushURL: "git@example.com:demo.git"
            ),
        ]
        recorder.aheadBehindSnapshotsByPath = [
            "/tmp/root": WorkspaceGitAheadBehindSnapshot(upstream: "origin/main", ahead: 0, behind: 0),
            "/tmp/root-worktree": WorkspaceGitAheadBehindSnapshot(upstream: "origin/main", ahead: 0, behind: 5),
        ]
        let viewModel = makeWorkspaceGitViewModel(
            recorder: recorder,
            executionWorktrees: [
                WorkspaceGitWorktreeContext(
                    path: "/tmp/root",
                    displayName: "root",
                    branchName: "main",
                    isRootProject: true
                ),
                WorkspaceGitWorktreeContext(
                    path: "/tmp/root-worktree",
                    displayName: "feature",
                    branchName: "feature/demo",
                    isRootProject: false
                ),
            ]
        )

        viewModel.setSection(.operations)
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertEqual(viewModel.aheadBehindSnapshot.behind, 0)

        viewModel.selectExecutionWorktree("/tmp/root-worktree")
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(viewModel.selectedExecutionWorktree?.path, "/tmp/root-worktree")
        XCTAssertEqual(viewModel.aheadBehindSnapshot.behind, 5)
    }

    func testCreateBranchMutationUsesSelectedExecutionWorktreeAndRefreshesChangesRefsAndLog() async throws {
        let recorder = WorkspaceGitClientRecorder()
        let viewModel = makeWorkspaceGitViewModel(
            recorder: recorder,
            executionWorktrees: [
                WorkspaceGitWorktreeContext(
                    path: "/tmp/root",
                    displayName: "root",
                    branchName: "main",
                    isRootProject: true
                ),
                WorkspaceGitWorktreeContext(
                    path: "/tmp/root-worktree",
                    displayName: "feature",
                    branchName: "feature/demo",
                    isRootProject: false
                ),
            ]
        )

        viewModel.selectExecutionWorktree("/tmp/root-worktree")
        viewModel.createBranch(name: "feature/task4", startPoint: nil)
        try await Task.sleep(for: .milliseconds(280))

        XCTAssertEqual(recorder.createdBranches.last?.path, "/tmp/root-worktree")
        XCTAssertEqual(recorder.createdBranches.last?.name, "feature/task4")
        XCTAssertTrue(viewModel.logSnapshot.refs.localBranches.contains(where: { $0.name == "feature/task4" }))
        XCTAssertGreaterThan(recorder.changesReadCount, 0, "mutation 成功后应刷新 changes")
        XCTAssertGreaterThan(recorder.logReadCount, 0, "mutation 成功后应刷新 log/refs")
    }

    func testDeleteCurrentBranchMutationIsRejectedWithoutCallingClient() {
        let recorder = WorkspaceGitClientRecorder()
        let viewModel = makeWorkspaceGitViewModel(recorder: recorder)

        viewModel.logSnapshot = WorkspaceGitLogSnapshot(
            refs: WorkspaceGitRefsSnapshot(
                localBranches: [
                    WorkspaceGitBranchSnapshot(
                        name: "main",
                        fullName: "refs/heads/main",
                        hash: "hash-main",
                        kind: .local,
                        isCurrent: true
                    ),
                ],
                remoteBranches: [],
                tags: []
            ),
            commits: []
        )

        viewModel.deleteLocalBranch(name: "main")

        XCTAssertTrue(recorder.deletedBranches.isEmpty)
        XCTAssertTrue(viewModel.mutationErrorMessage?.contains("当前分支") == true)
    }

    func testFetchMutationUsesSelectedExecutionWorktreeAndRefreshesOperationsAndLog() async throws {
        let recorder = WorkspaceGitClientRecorder()
        recorder.remoteSnapshots = [
            WorkspaceGitRemoteSnapshot(
                name: "origin",
                fetchURL: "git@example.com:demo.git",
                pushURL: "git@example.com:demo.git"
            ),
        ]
        recorder.aheadBehindSnapshot = WorkspaceGitAheadBehindSnapshot(upstream: "origin/main", ahead: 0, behind: 1)
        let viewModel = makeWorkspaceGitViewModel(
            recorder: recorder,
            executionWorktrees: [
                WorkspaceGitWorktreeContext(
                    path: "/tmp/root",
                    displayName: "root",
                    branchName: "main",
                    isRootProject: true
                ),
                WorkspaceGitWorktreeContext(
                    path: "/tmp/root-worktree",
                    displayName: "feature",
                    branchName: "feature/demo",
                    isRootProject: false
                ),
            ]
        )

        viewModel.setSection(.operations)
        try await Task.sleep(for: .milliseconds(120))
        viewModel.selectExecutionWorktree("/tmp/root-worktree")
        recorder.aheadBehindSnapshot = WorkspaceGitAheadBehindSnapshot(upstream: "origin/main", ahead: 0, behind: 0)

        viewModel.fetch()
        try await Task.sleep(for: .milliseconds(220))

        XCTAssertEqual(recorder.fetchedPaths.last, "/tmp/root-worktree")
        XCTAssertEqual(viewModel.aheadBehindSnapshot.behind, 0)
        XCTAssertEqual(viewModel.remotes.first?.name, "origin")
        XCTAssertGreaterThan(recorder.logReadCount, 0, "operations mutation 成功后应补刷 log/refs")
        XCTAssertGreaterThan(recorder.remotesReadCount, 0, "operations mutation 成功后应刷新 remote 列表")
        XCTAssertGreaterThan(recorder.aheadBehindReadCount, 0, "operations mutation 成功后应刷新 ahead/behind")
    }

    func testOperationsMutationBusyStateAndFailureDoNotReuseReadLoadingState() async throws {
        let recorder = WorkspaceGitClientRecorder()
        recorder.fetchDelayMilliseconds = 260
        let viewModel = makeWorkspaceGitViewModel(recorder: recorder)

        viewModel.fetch()
        XCTAssertTrue(viewModel.isMutating)
        XCTAssertTrue(viewModel.isMutatingOperations)
        XCTAssertEqual(viewModel.activeMutation, .fetch)
        XCTAssertFalse(viewModel.isLoading, "mutation busy state 不应复用 read loading")

        try await Task.sleep(for: .milliseconds(340))
        XCTAssertFalse(viewModel.isMutatingOperations)

        recorder.pullError = WorkspaceGitCommandError.interactionRequired(
            command: "git pull --ff-only",
            reason: "需要认证"
        )
        viewModel.pull()
        try await Task.sleep(for: .milliseconds(160))

        XCTAssertTrue(viewModel.mutationErrorMessage?.contains("需要交互处理") == true)
        XCTAssertNil(viewModel.errorMessage, "mutation 错误不应污染 read error channel")
    }

    func testChangingExecutionContextDuringMutationPreventsStaleWriteBack() async throws {
        let recorder = WorkspaceGitClientRecorder()
        recorder.fetchDelayMilliseconds = 260
        recorder.aheadBehindSnapshotsByPath = [
            "/tmp/root": WorkspaceGitAheadBehindSnapshot(upstream: "origin/main", ahead: 0, behind: 0),
            "/tmp/root-worktree": WorkspaceGitAheadBehindSnapshot(upstream: "origin/main", ahead: 0, behind: 7),
        ]
        let viewModel = makeWorkspaceGitViewModel(
            recorder: recorder,
            executionWorktrees: [
                WorkspaceGitWorktreeContext(
                    path: "/tmp/root",
                    displayName: "root",
                    branchName: "main",
                    isRootProject: true
                ),
                WorkspaceGitWorktreeContext(
                    path: "/tmp/root-worktree",
                    displayName: "feature",
                    branchName: "feature/demo",
                    isRootProject: false
                ),
            ]
        )

        viewModel.setSection(.operations)
        try await Task.sleep(for: .milliseconds(120))

        viewModel.fetch()
        try await Task.sleep(for: .milliseconds(40))
        viewModel.selectExecutionWorktree("/tmp/root-worktree")

        try await Task.sleep(for: .milliseconds(360))

        XCTAssertEqual(viewModel.selectedExecutionWorktree?.path, "/tmp/root-worktree")
        XCTAssertEqual(viewModel.aheadBehindSnapshot.behind, 7, "mutation 完成后的旧 executionPath 结果不应覆盖当前 worktree 的 operation 状态")
        XCTAssertNil(viewModel.workingTreeSnapshot, "operations section 下切换 execution context 后，不应被旧 mutation 回写 tracked snapshot")
    }

    private func makeWorkspaceGitViewModel(
        recorder: WorkspaceGitClientRecorder,
        executionWorktrees: [WorkspaceGitWorktreeContext] = [
            WorkspaceGitWorktreeContext(
                path: "/tmp/root",
                displayName: "root",
                branchName: "main",
                isRootProject: true
            ),
        ]
    ) -> WorkspaceGitViewModel {
        WorkspaceGitViewModel(
            repositoryContext: WorkspaceGitRepositoryContext(
                rootProjectPath: "/tmp/root",
                repositoryPath: "/tmp/root"
            ),
            executionWorktrees: executionWorktrees,
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

    private nonisolated static func largeDiff(lineCount: Int) -> String {
        var lines = ["diff --git a/README.md b/README.md", "@@ -1,1 +1,\(lineCount) @@"]
        lines.append(contentsOf: (0..<lineCount).map { "+line-\($0)" })
        return lines.joined(separator: "\n")
    }

    private func nativeAppViewModelSourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenCore/ViewModels/NativeAppViewModel.swift")
    }

    private func workspaceGitModelsSourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenCore/Models/WorkspaceGitModels.swift")
    }
}

private final class WorkspaceGitClientRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var rawReadSections: [WorkspaceGitSection] = []
    private var rawLogQueries: [String] = []
    private var rawLoadedCommitHashes: [String] = []
    private var rawLogRevisions: [String?] = []
    private var rawLogAuthors: [String?] = []
    private var rawLogSinceFilters: [String?] = []
    private var rawLogPaths: [String?] = []
    private var rawChangesReadPaths: [String] = []
    private var rawLogReadCount = 0
    private var rawChangesReadCount = 0
    private var rawCreatedBranches: [(path: String, name: String, startPoint: String?)] = []
    private var rawDeletedBranches: [(path: String, name: String)] = []
    private var rawCheckedOutBranches: [(path: String, name: String)] = []
    private var rawStagedAllPaths: [String] = []
    private var rawFetchedPaths: [String] = []
    private var rawPulledPaths: [String] = []
    private var rawPushedPaths: [String] = []
    private var rawAbortedPaths: [String] = []
    private var rawRemotesReadCount = 0
    private var rawAheadBehindReadCount = 0
    private var rawOperationStateReadCount = 0
    private var localBranchNames = ["main"]
    private var currentBranch = "main"
    var remoteSnapshots: [WorkspaceGitRemoteSnapshot] = []
    var aheadBehindSnapshot = WorkspaceGitAheadBehindSnapshot(upstream: nil, ahead: 0, behind: 0)
    var aheadBehindSnapshotsByPath: [String: WorkspaceGitAheadBehindSnapshot] = [:]
    var operationState: WorkspaceGitOperationState = .idle
    var logDelayMilliseconds: UInt64 = 0
    var changesDelayMilliseconds: UInt64 = 0
    var fetchDelayMilliseconds: UInt64 = 0
    var commitDiff = "diff --git a/README.md b/README.md\n+demo\n"
    var commitChangedFiles: [WorkspaceGitCommitFileChange] = []
    var pullError: Error?

    var readSections: [WorkspaceGitSection] {
        lock.withLock { rawReadSections }
    }

    var logQueries: [String] {
        lock.withLock { rawLogQueries }
    }

    var loadedCommitHashes: [String] {
        lock.withLock { rawLoadedCommitHashes }
    }

    var logRevisions: [String?] {
        lock.withLock { rawLogRevisions }
    }

    var logAuthors: [String?] {
        lock.withLock { rawLogAuthors }
    }

    var logSinceFilters: [String?] {
        lock.withLock { rawLogSinceFilters }
    }

    var logPaths: [String?] {
        lock.withLock { rawLogPaths }
    }

    var changesReadPaths: [String] {
        lock.withLock { rawChangesReadPaths }
    }

    var logReadCount: Int {
        lock.withLock { rawLogReadCount }
    }

    var changesReadCount: Int {
        lock.withLock { rawChangesReadCount }
    }

    var createdBranches: [(path: String, name: String, startPoint: String?)] {
        lock.withLock { rawCreatedBranches }
    }

    var deletedBranches: [(path: String, name: String)] {
        lock.withLock { rawDeletedBranches }
    }

    var fetchedPaths: [String] {
        lock.withLock { rawFetchedPaths }
    }

    var remotesReadCount: Int {
        lock.withLock { rawRemotesReadCount }
    }

    var aheadBehindReadCount: Int {
        lock.withLock { rawAheadBehindReadCount }
    }

    var client: WorkspaceGitViewModel.Client {
        WorkspaceGitViewModel.Client(
            loadRefs: { [weak self] _ in
                self?.lock.withLock {
                    self?.rawReadSections.append(.branches)
                }
                return WorkspaceGitRefsSnapshot(localBranches: [], remoteBranches: [], tags: [])
            },
            loadLogSnapshot: { [weak self] _, query in
                guard let self else {
                    return WorkspaceGitLogSnapshot(refs: WorkspaceGitRefsSnapshot(localBranches: [], remoteBranches: [], tags: []), commits: [])
                }
                self.lock.withLock {
                    self.rawReadSections.append(.log)
                    self.rawLogReadCount += 1
                }
                if let searchTerm = query.searchTerm, !searchTerm.isEmpty {
                    self.lock.withLock {
                        self.rawLogQueries.append(searchTerm)
                    }
                }
                self.lock.withLock {
                    self.rawLogRevisions.append(query.revision)
                    self.rawLogAuthors.append(query.author)
                    self.rawLogSinceFilters.append(query.since)
                    self.rawLogPaths.append(query.path)
                }
                if self.logDelayMilliseconds > 0 {
                    Thread.sleep(forTimeInterval: TimeInterval(self.logDelayMilliseconds) / 1000)
                }
                let refs = self.lock.withLock {
                    WorkspaceGitRefsSnapshot(
                        localBranches: self.localBranchNames.map { name in
                            WorkspaceGitBranchSnapshot(
                                name: name,
                                fullName: "refs/heads/\(name)",
                                hash: "hash-\(name)",
                                kind: .local,
                                isCurrent: self.currentBranch == name
                            )
                        },
                        remoteBranches: [],
                        tags: []
                    )
                }
                return WorkspaceGitLogSnapshot(
                    refs: refs,
                    commits: [
                        WorkspaceGitCommitSummary(
                            hash: "hash-log",
                            shortHash: "hash",
                            graphPrefix: "*",
                            parentHashes: [],
                            authorName: "DevHaven",
                            authorEmail: "devhaven@example.com",
                            authorTimestamp: 1,
                            subject: "log",
                            decorations: nil
                        ),
                    ]
                )
            },
            loadCommitDetail: { [weak self] _, commitHash in
                self?.lock.withLock {
                    self?.rawLoadedCommitHashes.append(commitHash)
                }
                return WorkspaceGitCommitDetail(
                    hash: commitHash,
                    shortHash: "hash",
                    parentHashes: [],
                    authorName: "DevHaven",
                    authorEmail: "devhaven@example.com",
                    authorTimestamp: 1,
                    subject: "log",
                    body: nil,
                    decorations: nil,
                    changedFiles: self?.commitChangedFiles ?? [],
                    diff: self?.commitDiff ?? ""
                )
            },
            loadDiffForCommit: { _, _ in "" },
            loadChanges: { [weak self] path in
                if let self {
                    self.lock.withLock {
                        self.rawChangesReadPaths.append(path)
                        self.rawChangesReadCount += 1
                    }
                    if self.changesDelayMilliseconds > 0 {
                        Thread.sleep(forTimeInterval: TimeInterval(self.changesDelayMilliseconds) / 1000)
                    }
                }
                return WorkspaceGitWorkingTreeSnapshot(
                    headOID: nil,
                    branchName: path.hasSuffix("root-worktree") ? "feature/demo" : "main",
                    isDetachedHead: false,
                    isEmptyRepository: false,
                    upstreamBranch: nil,
                    aheadCount: 0,
                    behindCount: 0,
                    staged: [],
                    unstaged: [],
                    untracked: [],
                    conflicted: []
                )
            },
            loadRemotes: { [weak self] _ in
                self?.lock.withLock {
                    self?.rawRemotesReadCount += 1
                }
                return self?.remoteSnapshots ?? []
            },
            loadAheadBehind: { [weak self] path in
                self?.lock.withLock {
                    self?.rawAheadBehindReadCount += 1
                }
                if let snapshot = self?.aheadBehindSnapshotsByPath[path] {
                    return snapshot
                }
                return self?.aheadBehindSnapshot ?? WorkspaceGitAheadBehindSnapshot(upstream: nil, ahead: 0, behind: 0)
            },
            loadOperationState: { [weak self] _ in
                self?.lock.withLock {
                    self?.rawOperationStateReadCount += 1
                }
                return self?.operationState ?? .idle
            },
            stage: { _, _ in },
            unstage: { _, _ in },
            stageAll: { [weak self] path in
                self?.lock.withLock {
                    self?.rawStagedAllPaths.append(path)
                }
            },
            unstageAll: { _ in },
            discard: { _, _ in },
            commit: { _, _ in },
            amend: { _, _ in },
            createBranch: { [weak self] path, name, startPoint in
                self?.lock.withLock {
                    self?.rawCreatedBranches.append((path: path, name: name, startPoint: startPoint))
                    if self?.localBranchNames.contains(name) == false {
                        self?.localBranchNames.append(name)
                    }
                }
            },
            checkoutBranch: { [weak self] path, name in
                self?.lock.withLock {
                    self?.rawCheckedOutBranches.append((path: path, name: name))
                    self?.currentBranch = name
                }
            },
            deleteLocalBranch: { [weak self] path, name in
                self?.lock.withLock {
                    self?.rawDeletedBranches.append((path: path, name: name))
                    self?.localBranchNames.removeAll(where: { $0 == name })
                }
            },
            fetch: { [weak self] path in
                if let delay = self?.fetchDelayMilliseconds, delay > 0 {
                    Thread.sleep(forTimeInterval: TimeInterval(delay) / 1000)
                }
                self?.lock.withLock {
                    self?.rawFetchedPaths.append(path)
                }
            },
            pull: { [weak self] path in
                self?.lock.withLock {
                    self?.rawPulledPaths.append(path)
                }
                if let pullError = self?.pullError {
                    throw pullError
                }
            },
            push: { [weak self] path in
                self?.lock.withLock {
                    self?.rawPushedPaths.append(path)
                }
            },
            abortOperation: { [weak self] path in
                self?.lock.withLock {
                    self?.rawAbortedPaths.append(path)
                    self?.operationState = .idle
                }
            }
        )
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
