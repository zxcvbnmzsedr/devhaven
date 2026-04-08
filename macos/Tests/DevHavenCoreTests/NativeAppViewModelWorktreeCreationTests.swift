import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelWorktreeCreationTests: XCTestCase {
    func testCreateWorkspaceWorktreeFailureCleansResidualBranchAndDirectory() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        let branch = "feature/payment"
        let targetPath = try viewModel.managedWorktreePathPreview(for: fixture.repositoryURL.path, branch: branch)
        let targetURL = URL(fileURLWithPath: targetPath, isDirectory: true)
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try "stale".write(
            to: targetURL.appendingPathComponent("stale.txt"),
            atomically: true,
            encoding: .utf8
        )

        do {
            try await viewModel.createWorkspaceWorktree(
                from: fixture.repositoryURL.path,
                branch: branch,
                createBranch: true,
                baseBranch: "main",
                autoOpen: false,
                targetPath: targetPath
            )
            XCTFail("预期创建失败，但实际成功")
        } catch {
            // 预期失败：关键是验证失败后的 cleanup 是否生效。
        }

        let localBranch = try fixture.git(in: fixture.repositoryURL, ["branch", "--list", branch])
        XCTAssertTrue(localBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetPath))
        XCTAssertEqual(viewModel.snapshot.projects.first?.worktrees.map(\.path) ?? [], [])
    }

    func testCurrentBranchFallsBackToSymbolicRefForUnbornHead() throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "develop")

        let service = NativeGitWorktreeService(homeDirectoryURL: fixture.homeURL)
        let branch = try service.currentBranch(at: fixture.repositoryURL.path)
        XCTAssertEqual(branch, "develop")
    }

    func testEnterWorkspaceAutoRefreshesExternallyCreatedWorktree() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let existingWorktreeURL = fixture.rootURL.appendingPathComponent("external-feature-worktree", isDirectory: true)
        try fixture.git(
            in: fixture.repositoryURL,
            ["worktree", "add", existingWorktreeURL.path, "-b", "feature/external", "main"]
        )
        let expectedWorktreePath = existingWorktreeURL.resolvingSymlinksInPath().path

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        viewModel.enterWorkspace(fixture.repositoryURL.path)

        for _ in 0..<100 where viewModel.snapshot.projects.first?.worktrees.contains(where: {
            canonicalPath($0.path) == canonicalPath(expectedWorktreePath)
        }) != true {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertTrue(viewModel.snapshot.projects.first?.worktrees.contains(where: {
            canonicalPath($0.path) == canonicalPath(expectedWorktreePath)
        }) == true)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRefreshProjectWorktreesDoesNotFailForUnbornHead() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        try await viewModel.refreshProjectWorktrees(fixture.repositoryURL.path)

        XCTAssertEqual(viewModel.snapshot.projects.first?.worktrees.count, 0)
    }

    func testOpenWorkspaceWorktreeRefreshesMissingExternalWorktreeBeforeOpening() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let existingWorktreeURL = fixture.rootURL.appendingPathComponent("external-direct-open-worktree", isDirectory: true)
        try fixture.git(
            in: fixture.repositoryURL,
            ["worktree", "add", existingWorktreeURL.path, "-b", "feature/direct-open", "main"]
        )
        let expectedWorktreePath = existingWorktreeURL.resolvingSymlinksInPath().path

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        viewModel.openWorkspaceWorktree(expectedWorktreePath, from: fixture.repositoryURL.path)

        XCTAssertEqual(
            canonicalPath(try XCTUnwrap(viewModel.activeWorkspaceProjectPath)),
            canonicalPath(expectedWorktreePath)
        )
        XCTAssertTrue(viewModel.openWorkspaceSessions.contains(where: {
            canonicalPath($0.projectPath) == canonicalPath(expectedWorktreePath)
        }))
        XCTAssertTrue(viewModel.snapshot.projects.first?.worktrees.contains(where: {
            canonicalPath($0.path) == canonicalPath(expectedWorktreePath)
        }) == true)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadCanonicalizesTmpWorktreeRestoreSessionPath() throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        let store = LegacyCompatStore(homeDirectoryURL: fixture.homeURL)
        let restoreStore = WorkspaceRestoreStore(homeDirectoryURL: fixture.homeURL)
        let rawTmpPath = "/tmp/devhaven-restore-canonical-\(UUID().uuidString)"
        let canonicalTmpPath = "/private\(rawTmpPath)"

        var rootProject = fixture.makeProject()
        rootProject.worktrees = [
            ProjectWorktree(
                id: "worktree:\(canonicalTmpPath)",
                name: "devhaven-restore-canonical",
                path: canonicalTmpPath,
                branch: "feature/restore-canonical",
                baseBranch: "main",
                inheritConfig: true,
                created: Date().timeIntervalSinceReferenceDate
            )
        ]
        try store.updateProjects([rootProject])

        let selectedItem = WorkspacePaneItemRestoreSnapshot(
            surfaceId: "surface-1",
            terminalSessionId: "terminal-1",
            restoredWorkingDirectory: rawTmpPath,
            restoredTitle: rawTmpPath,
            agentSummary: nil,
            snapshotTextRef: nil,
            snapshotText: nil
        )
        let pane = WorkspacePaneRestoreSnapshot(
            paneId: "pane-1",
            selectedItemId: selectedItem.surfaceId,
            items: [selectedItem]
        )
        let tab = WorkspaceTabRestoreSnapshot(
            id: "tab-1",
            title: "Tab 1",
            focusedPaneId: pane.paneId,
            tree: WorkspacePaneTreeRestoreSnapshot(root: .leaf(pane), zoomedPaneId: nil)
        )
        let restoreSnapshot = WorkspaceRestoreSnapshot(
            activeProjectPath: rawTmpPath,
            selectedProjectPath: rawTmpPath,
            sessions: [
                ProjectWorkspaceRestoreSnapshot(
                    projectPath: rawTmpPath,
                    rootProjectPath: fixture.repositoryURL.path,
                    isQuickTerminal: false,
                    workspaceId: "workspace-1",
                    selectedTabId: tab.id,
                    nextTabNumber: 2,
                    nextPaneNumber: 2,
                    tabs: [tab]
                )
            ]
        )
        try restoreStore.saveSnapshot(restoreSnapshot)

        let viewModel = NativeAppViewModel(store: store)
        viewModel.load()

        XCTAssertEqual(viewModel.openWorkspaceSessions.count, 1)
        XCTAssertEqual(viewModel.openWorkspaceSessions.first?.projectPath, canonicalTmpPath)
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, canonicalTmpPath)
        XCTAssertEqual(viewModel.selectedProjectPath, canonicalTmpPath)
        XCTAssertEqual(viewModel.openWorkspaceProjects.first?.path, canonicalTmpPath)
    }

    func testCreateWorkspaceWorktreeSuccessPersistsRealWorktreeWithoutTransientStatus() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        try await viewModel.createWorkspaceWorktree(
            from: fixture.repositoryURL.path,
            branch: "feature/success",
            createBranch: true,
            baseBranch: "main",
            autoOpen: false
        )

        let worktree = try XCTUnwrap(viewModel.snapshot.projects.first?.worktrees.first)
        XCTAssertEqual(worktree.branch, "feature/success")
        XCTAssertEqual(worktree.baseBranch, "main")
        XCTAssertNil(worktree.status)
        XCTAssertNil(worktree.initStep)
        XCTAssertNil(worktree.initMessage)
        XCTAssertNil(worktree.initError)
    }

    func testListBaseBranchReferencesIncludesLocalAndRemoteEntries() throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let remoteURL = fixture.rootURL.appendingPathComponent("origin.git", isDirectory: true)
        try fixture.git(in: fixture.rootURL, ["init", "--bare", remoteURL.path])
        try fixture.git(in: fixture.repositoryURL, ["remote", "add", "origin", remoteURL.path])
        try fixture.git(in: fixture.repositoryURL, ["push", "-u", "origin", "main"])

        let service = NativeGitWorktreeService(homeDirectoryURL: fixture.homeURL)
        let references = try service.listBaseBranchReferences(at: fixture.repositoryURL.path)

        XCTAssertTrue(references.contains(where: { $0.name == "main" && $0.kind == .local }))
        XCTAssertTrue(references.contains(where: { $0.name == "origin/main" && $0.kind == .remote }))
        XCTAssertFalse(references.contains(where: { $0.name == "origin" && $0.kind == .remote }))
    }

    func testCreateWorkspaceWorktreeSupportsExplicitRemoteBaseBranch() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let remoteURL = fixture.rootURL.appendingPathComponent("origin.git", isDirectory: true)
        try fixture.git(in: fixture.rootURL, ["init", "--bare", remoteURL.path])
        try fixture.git(in: fixture.repositoryURL, ["remote", "add", "origin", remoteURL.path])
        try fixture.git(in: fixture.repositoryURL, ["push", "-u", "origin", "main"])
        try fixture.git(in: fixture.repositoryURL, ["push", "origin", "main:refs/heads/release/8.2"])

        let releaseCommit = try fixture.git(in: fixture.repositoryURL, ["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        try fixture.commit(fileName: "README.md", content: "hello v2")
        try fixture.git(in: fixture.repositoryURL, ["push", "origin", "main"])
        try fixture.git(in: fixture.repositoryURL, ["fetch", "origin", "main", "release/8.2"])

        let originMainCommit = try fixture.git(in: fixture.repositoryURL, ["rev-parse", "origin/main"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let originReleaseCommit = try fixture.git(in: fixture.repositoryURL, ["rev-parse", "origin/release/8.2"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(originReleaseCommit, releaseCommit)
        XCTAssertNotEqual(originMainCommit, originReleaseCommit)

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        try await viewModel.createWorkspaceWorktree(
            from: fixture.repositoryURL.path,
            branch: "feature/from-remote-base",
            createBranch: true,
            baseBranch: "origin/release/8.2",
            autoOpen: false
        )

        let worktree = try XCTUnwrap(viewModel.snapshot.projects.first?.worktrees.first)
        XCTAssertEqual(worktree.baseBranch, "origin/release/8.2")
        let worktreeHead = try fixture.git(
            in: URL(fileURLWithPath: worktree.path, isDirectory: true),
            ["rev-parse", "HEAD"]
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(worktreeHead, originReleaseCommit)
    }

    func testDeleteWorkspaceWorktreeRemovesCreatedLocalBranch() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        try await viewModel.createWorkspaceWorktree(
            from: fixture.repositoryURL.path,
            branch: "feature/delete-branch",
            createBranch: true,
            baseBranch: "main",
            autoOpen: false
        )

        let worktreePath = try XCTUnwrap(viewModel.snapshot.projects.first?.worktrees.first?.path)
        try await viewModel.deleteWorkspaceWorktree(worktreePath, from: fixture.repositoryURL.path)

        let localBranch = try fixture.git(in: fixture.repositoryURL, ["branch", "--list", "feature/delete-branch"])
        XCTAssertTrue(localBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testDeleteWorkspaceWorktreeForceRemovesCreatedBranchWithUnmergedCommit() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        try await viewModel.createWorkspaceWorktree(
            from: fixture.repositoryURL.path,
            branch: "feature/delete-branch-with-commit",
            createBranch: true,
            baseBranch: "main",
            autoOpen: false
        )

        let worktreePath = try XCTUnwrap(viewModel.snapshot.projects.first?.worktrees.first?.path)
        let worktreeURL = URL(fileURLWithPath: worktreePath, isDirectory: true)
        let fileURL = worktreeURL.appendingPathComponent("feature.txt")
        try "feature".write(to: fileURL, atomically: true, encoding: .utf8)
        try fixture.git(in: worktreeURL, ["add", "feature.txt"])
        try fixture.git(in: worktreeURL, ["commit", "-m", "feature work"])

        try await viewModel.deleteWorkspaceWorktree(worktreePath, from: fixture.repositoryURL.path)

        let localBranch = try fixture.git(in: fixture.repositoryURL, ["branch", "--list", "feature/delete-branch-with-commit"])
        XCTAssertTrue(localBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testDeleteWorkspaceWorktreeCleansPersistedRecordAfterManualDirectoryRemoval() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        try await viewModel.createWorkspaceWorktree(
            from: fixture.repositoryURL.path,
            branch: "feature/manual-remove",
            createBranch: true,
            baseBranch: "main",
            autoOpen: false
        )

        let worktreePath = try XCTUnwrap(viewModel.snapshot.projects.first?.worktrees.first?.path)
        let worktreeURL = URL(fileURLWithPath: worktreePath, isDirectory: true)
        try FileManager.default.removeItem(at: worktreeURL)
        _ = try fixture.git(in: fixture.repositoryURL, ["worktree", "prune"])

        XCTAssertNotNil(
            viewModel.workspaceWorktreeDeletePresentation(for: worktreePath, from: fixture.repositoryURL.path),
            "手动删除后，仍应允许用户在侧边栏清理这条 stale worktree 记录"
        )

        try await viewModel.deleteWorkspaceWorktree(worktreePath, from: fixture.repositoryURL.path)

        XCTAssertEqual(viewModel.snapshot.projects.first?.worktrees.count, 0)
        let remainingBranch = try fixture.git(in: fixture.repositoryURL, ["branch", "--list", "feature/manual-remove"])
        XCTAssertTrue(remainingBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCreateWorkspaceWorktreePreservesBaseBranchMetadataForLaterDelete() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        try await viewModel.createWorkspaceWorktree(
            from: fixture.repositoryURL.path,
            branch: "feature/preserve-base-branch",
            createBranch: true,
            baseBranch: "main",
            autoOpen: false
        )

        let worktree = try XCTUnwrap(viewModel.snapshot.projects.first?.worktrees.first)
        XCTAssertEqual(worktree.branch, "feature/preserve-base-branch")
        XCTAssertEqual(worktree.baseBranch, "main")
    }

    func testCreateWorkspaceWorktreeRejectsInvalidBranchName() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        do {
            try await viewModel.createWorkspaceWorktree(
                from: fixture.repositoryURL.path,
                branch: "bad branch",
                createBranch: true,
                baseBranch: "main",
                autoOpen: false
            )
            XCTFail("预期非法分支名被拒绝，但实际成功")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertTrue(message.contains("分支名"), "错误文案应提示分支名非法，实际：\(message)")
        }

        XCTAssertEqual(viewModel.snapshot.projects.first?.worktrees.count, 0)
        let previewPath = try viewModel.managedWorktreePathPreview(for: fixture.repositoryURL.path, branch: "bad branch")
        XCTAssertNil(
            viewModel.workspaceWorktreeDeletePresentation(for: previewPath, from: fixture.repositoryURL.path),
            "非法分支名不应留下 pending failed 记录"
        )
    }

    func testCreateWorkspaceWorktreeBootstrapWarningDoesNotFailRealWorktreeCreation() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel(
            worktreeEnvironmentService: StubWorktreeEnvironmentService(
                result: NativeWorktreeEnvironmentResult(
                    warning: "bootstrap warning"
                )
            )
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        try await viewModel.createWorkspaceWorktree(
            from: fixture.repositoryURL.path,
            branch: "feature/bootstrap-warning",
            createBranch: true,
            baseBranch: "main",
            autoOpen: false
        )

        let worktree = try XCTUnwrap(viewModel.snapshot.projects.first?.worktrees.first)
        XCTAssertEqual(worktree.branch, "feature/bootstrap-warning")
        XCTAssertEqual(viewModel.errorMessage, "bootstrap warning")
    }

    func testCreateWorkspaceWorktreeBootstrapWarningIncludesFailureContext() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel(
            worktreeEnvironmentService: StubWorktreeEnvironmentService(
                result: NativeWorktreeEnvironmentResult(
                    warning: "bootstrap warning",
                    executedCommands: ["pnpm install"],
                    failedCommand: "pnpm install",
                    latestOutputLines: [
                        "stderr | permission denied",
                        "stderr | retry with sudo"
                    ]
                )
            )
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        try await viewModel.createWorkspaceWorktree(
            from: fixture.repositoryURL.path,
            branch: "feature/bootstrap-warning-context",
            createBranch: true,
            baseBranch: "main",
            autoOpen: false
        )

        let worktree = try XCTUnwrap(viewModel.snapshot.projects.first?.worktrees.first)
        XCTAssertEqual(worktree.branch, "feature/bootstrap-warning-context")
        let message = try XCTUnwrap(viewModel.errorMessage)
        XCTAssertTrue(message.contains("bootstrap warning"))
        XCTAssertTrue(message.contains("失败命令："))
        XCTAssertTrue(message.contains("$ pnpm install"))
        XCTAssertTrue(message.contains("permission denied"))
        XCTAssertTrue(message.contains("retry with sudo"))
    }

    func testStartCreateWorkspaceWorktreeDefersOverlayUntilSheetCanDismiss() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        let previewPath = fixture.rootURL
            .appendingPathComponent("managed/feature/deferred-overlay", isDirectory: true)
            .path
        let worktreeService = BlockingWorktreeService(
            previewPath: previewPath,
            defaultBranch: "main"
        )
        let viewModel = NativeAppViewModel(
            store: LegacyCompatStore(homeDirectoryURL: fixture.homeURL),
            worktreeService: worktreeService,
            worktreeEnvironmentService: StubWorktreeEnvironmentService(result: NativeWorktreeEnvironmentResult())
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        try viewModel.startCreateWorkspaceWorktree(
            from: fixture.repositoryURL.path,
            branch: "feature/deferred-overlay",
            createBranch: true,
            baseBranch: "main",
            autoOpen: false
        )

        XCTAssertNil(
            viewModel.worktreeInteractionState,
            "startCreateWorkspaceWorktree 应先返回给 sheet，让弹窗先关闭，再显示全局进度面板"
        )

        for _ in 0..<20 where viewModel.worktreeInteractionState == nil {
            await Task.yield()
        }

        XCTAssertNotNil(viewModel.worktreeInteractionState)
        XCTAssertTrue(worktreeService.waitUntilCreateStarts())

        worktreeService.finishCreate()
        for _ in 0..<20 where viewModel.worktreeInteractionState != nil {
            await Task.yield()
        }

        XCTAssertNil(viewModel.worktreeInteractionState)
        XCTAssertEqual(viewModel.snapshot.projects.first?.worktrees.first?.path, previewPath)
    }

    func testWorkspaceWorktreeDeletePresentationUsesClearFailedCreationForPendingFailure() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        let branch = "feature/delete-pending"
        let targetPath = try viewModel.managedWorktreePathPreview(for: fixture.repositoryURL.path, branch: branch)
        let targetURL = URL(fileURLWithPath: targetPath, isDirectory: true)
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try "stale".write(
            to: targetURL.appendingPathComponent("stale.txt"),
            atomically: true,
            encoding: .utf8
        )

        do {
            try await viewModel.createWorkspaceWorktree(
                from: fixture.repositoryURL.path,
                branch: branch,
                createBranch: true,
                baseBranch: "main",
                autoOpen: false,
                targetPath: targetPath
            )
            XCTFail("预期创建失败，但实际成功")
        } catch {
            // expected
        }

        let presentation = try XCTUnwrap(
            viewModel.workspaceWorktreeDeletePresentation(for: targetPath, from: fixture.repositoryURL.path)
        )
        XCTAssertEqual(presentation.kind, .clearFailedCreation)
        XCTAssertEqual(presentation.actionTitle, "清除记录")
    }

    func testWorkspaceWorktreeDeletePresentationUsesDeleteForPersistedWorktree() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        try await viewModel.createWorkspaceWorktree(
            from: fixture.repositoryURL.path,
            branch: "feature/delete-real",
            createBranch: true,
            baseBranch: "main",
            autoOpen: false
        )

        let worktreePath = try XCTUnwrap(viewModel.snapshot.projects.first?.worktrees.first?.path)
        let presentation = try XCTUnwrap(
            viewModel.workspaceWorktreeDeletePresentation(for: worktreePath, from: fixture.repositoryURL.path)
        )
        XCTAssertEqual(presentation.kind, .deletePersistedWorktree)
        XCTAssertEqual(presentation.actionTitle, "删除")
    }

    func testDeleteWorkspaceWorktreeRemovesCreatedBranch() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        try await viewModel.createWorkspaceWorktree(
            from: fixture.repositoryURL.path,
            branch: "feature/delete-branch-too",
            createBranch: true,
            baseBranch: "main",
            autoOpen: false
        )

        let worktreePath = try XCTUnwrap(viewModel.snapshot.projects.first?.worktrees.first?.path)
        try await viewModel.deleteWorkspaceWorktree(worktreePath, from: fixture.repositoryURL.path)

        let remainingBranch = try fixture.git(in: fixture.repositoryURL, ["branch", "--list", "feature/delete-branch-too"])
        XCTAssertTrue(remainingBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertEqual(viewModel.snapshot.projects.first?.worktrees.count, 0)
    }

    func testOpenWorkspaceWorktreeKeepsWorkspacePresentedWhenExistingSessionHasTrailingSlash() throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        let viewModel = fixture.makeViewModel()
        let persistedWorktreePath = fixture.rootURL
            .appendingPathComponent("managed/fix/worktree", isDirectory: true)
            .path
        let restoredWorktreePath = persistedWorktreePath + "/"
        var rootProject = fixture.makeProject()
        rootProject.worktrees = [
            ProjectWorktree(
                id: "worktree:\(restoredWorktreePath)",
                name: "worktree",
                path: persistedWorktreePath,
                branch: "fix/worktree",
                baseBranch: "main",
                inheritConfig: true,
                created: Date().timeIntervalSinceReferenceDate
            )
        ]
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [rootProject]
        )
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: restoredWorktreePath,
                rootProjectPath: fixture.repositoryURL.path,
                controller: GhosttyWorkspaceController(projectPath: restoredWorktreePath)
            )
        ]

        viewModel.openWorkspaceWorktree(persistedWorktreePath, from: fixture.repositoryURL.path)

        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, persistedWorktreePath)
        XCTAssertEqual(viewModel.selectedProjectPath, persistedWorktreePath)
        XCTAssertNotNil(viewModel.activeWorkspaceController)
        XCTAssertEqual(viewModel.activeWorkspaceController?.projectPath, restoredWorktreePath)
        XCTAssertTrue(viewModel.isWorkspacePresented)
        XCTAssertEqual(viewModel.openWorkspaceSessions.count, 1)
    }

    func testCreateWorkspaceWorktreeRejectsUsingRepositoryRootAsTargetPath() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        do {
            try await viewModel.createWorkspaceWorktree(
                from: fixture.repositoryURL.path,
                branch: "feature/same-root",
                createBranch: true,
                baseBranch: "main",
                autoOpen: false,
                targetPath: fixture.repositoryURL.path
            )
            XCTFail("预期主仓库目录作为 targetPath 会被拒绝，但实际成功")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertTrue(message.contains("主仓库目录相同"), "错误文案应提示 targetPath 非法，实际：\(message)")
        }
    }

    func testCreateWorkspaceWorktreeRejectsRelativeExplicitTargetPath() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        do {
            try await viewModel.createWorkspaceWorktree(
                from: fixture.repositoryURL.path,
                branch: "feature/relative-path",
                createBranch: true,
                baseBranch: "main",
                autoOpen: false,
                targetPath: "relative/path"
            )
            XCTFail("预期相对路径 targetPath 会被拒绝，但实际成功")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertTrue(message.contains("绝对路径"), "错误文案应提示 targetPath 必须是绝对路径，实际：\(message)")
        }
    }

    func testCreateWorkspaceWorktreeRejectsAbsoluteTargetPathOutsideManagedRoot() async throws {
        let fixture = try GitWorktreeCreationFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        let externalPath = fixture.rootURL.appendingPathComponent("external-worktree", isDirectory: true).path
        do {
            try await viewModel.createWorkspaceWorktree(
                from: fixture.repositoryURL.path,
                branch: "feature/outside-managed-root",
                createBranch: true,
                baseBranch: "main",
                autoOpen: false,
                targetPath: externalPath
            )
            XCTFail("预期 managed root 外的绝对路径会被拒绝，但实际成功")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertTrue(message.contains("管理的 worktree 目录"), "错误文案应提示 targetPath 必须位于 managed root，实际：\(message)")
        }
    }

    func testWorkspaceSidebarWorktreeItemDoesNotFallbackToPersistedTransientStatus() {
        let now = Date().timeIntervalSinceReferenceDate
        let persistedWorktree = ProjectWorktree(
            id: "worktree:/tmp/legacy",
            name: "legacy",
            path: "/tmp/legacy",
            branch: "feature/legacy",
            inheritConfig: true,
            created: now,
            status: "failed",
            initStep: NativeWorktreeInitStep.failed.rawValue,
            initMessage: "legacy message",
            initError: "legacy error",
            updatedAt: now
        )

        let item = WorkspaceSidebarWorktreeItem(
            rootProjectPath: "/tmp/repo",
            worktree: persistedWorktree,
            isOpen: false,
            isActive: false
        )

        XCTAssertNil(item.status)
        XCTAssertNil(item.initStep)
        XCTAssertNil(item.initMessage)
        XCTAssertNil(item.initError)
        XCTAssertEqual(item.displayState, .normal)
    }
}

private enum GitWorktreeCreationFixtureError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message):
            message
        }
    }
}

private struct GitWorktreeCreationFixture {
    let rootURL: URL
    let homeURL: URL
    let repositoryURL: URL

    static func make() throws -> GitWorktreeCreationFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-worktree-creation-\(UUID().uuidString)", isDirectory: true)
        let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        let repositoryURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        return GitWorktreeCreationFixture(rootURL: rootURL, homeURL: homeURL, repositoryURL: repositoryURL)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func initializeRepository(defaultBranch: String) throws {
        try git(in: repositoryURL, ["init", "-b", defaultBranch])
        try git(in: repositoryURL, ["config", "user.name", "DevHaven Tests"])
        try git(in: repositoryURL, ["config", "user.email", "devhaven-tests@example.com"])
    }

    func commit(fileName: String, content: String) throws {
        let fileURL = repositoryURL.appendingPathComponent(fileName)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        try git(in: repositoryURL, ["add", fileName])
        try git(in: repositoryURL, ["commit", "-m", "init"])
    }

    @MainActor
    func makeViewModel(
        worktreeService: (any NativeWorktreeServicing)? = nil,
        worktreeEnvironmentService: (any NativeWorktreeEnvironmentServicing)? = nil
    ) -> NativeAppViewModel {
        NativeAppViewModel(
            store: LegacyCompatStore(homeDirectoryURL: homeURL),
            worktreeService: worktreeService ?? NativeGitWorktreeService(homeDirectoryURL: homeURL),
            worktreeEnvironmentService: worktreeEnvironmentService
        )
    }

    func makeProject() -> Project {
        let now = Date().timeIntervalSinceReferenceDate
        return Project(
            id: UUID().uuidString,
            name: repositoryURL.lastPathComponent,
            path: repositoryURL.path,
            tags: [],
            runConfigurations: [],
            worktrees: [],
            mtime: now,
            size: 0,
            checksum: UUID().uuidString,
            isGitRepository: true,
            gitCommits: 0,
            gitLastCommit: now,
            created: now,
            checked: now
        )
    }

    @discardableResult
    func git(in directoryURL: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directoryURL

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let message = [stdoutText, stderrText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "未知错误"
            throw GitWorktreeCreationFixtureError.commandFailed(
                "git \(arguments.joined(separator: " ")) 失败：\(message)"
            )
        }
        return stdoutText
    }
}

private struct StubWorktreeEnvironmentService: NativeWorktreeEnvironmentServicing {
    let result: NativeWorktreeEnvironmentResult

    func prepareEnvironment(
        mainRepositoryPath: String,
        worktreePath: String,
        workspaceName: String
    ) -> NativeWorktreeEnvironmentResult {
        result
    }
}

private final class BlockingWorktreeService: NativeWorktreeServicing, @unchecked Sendable {
    private let previewPath: String
    private let defaultBranch: String
    private let createStarted = DispatchSemaphore(value: 0)
    private let allowFinish = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var finishedBranches = [String: String]()

    init(previewPath: String, defaultBranch: String) {
        self.previewPath = previewPath
        self.defaultBranch = defaultBranch
    }

    func managedWorktreePath(for sourceProjectPath: String, branch: String) throws -> String {
        previewPath
    }

    func preflightCreateWorktree(_ request: NativeWorktreeCreateRequest) throws -> String {
        previewPath
    }

    func currentBranch(at projectPath: String) throws -> String {
        defaultBranch
    }

    func listBranches(at projectPath: String) throws -> [NativeGitBranch] {
        lock.lock()
        defer { lock.unlock() }
        let createdBranches = finishedBranches.values.sorted()
        let allBranches = [defaultBranch] + createdBranches
        return Array(Set(allBranches)).sorted().map { NativeGitBranch(name: $0, isMain: $0 == defaultBranch) }
    }

    func listWorktrees(at projectPath: String) throws -> [NativeGitWorktree] {
        lock.lock()
        defer { lock.unlock() }
        return finishedBranches.map { NativeGitWorktree(path: $0.key, branch: $0.value) }
    }

    func createWorktree(
        _ request: NativeWorktreeCreateRequest,
        progress: @escaping @Sendable (NativeWorktreeProgress) -> Void
    ) throws -> NativeWorktreeCreateResult {
        progress(
            NativeWorktreeProgress(
                worktreePath: previewPath,
                branch: request.branch,
                baseBranch: request.baseBranch,
                step: .checkingBranch,
                message: "执行中：校验分支与基线可用性..."
            )
        )
        createStarted.signal()
        allowFinish.wait()
        lock.lock()
        finishedBranches[previewPath] = request.branch
        lock.unlock()
        return NativeWorktreeCreateResult(
            worktreePath: previewPath,
            branch: request.branch,
            baseBranch: request.baseBranch
        )
    }

    func removeWorktree(_ request: NativeWorktreeRemoveRequest) throws -> NativeWorktreeRemoveResult {
        lock.lock()
        finishedBranches.removeValue(forKey: request.worktreePath)
        lock.unlock()
        return NativeWorktreeRemoveResult()
    }

    func cleanupFailedWorktreeCreate(_ request: NativeWorktreeCleanupRequest) throws -> NativeWorktreeCleanupResult {
        lock.lock()
        finishedBranches.removeValue(forKey: request.worktreePath)
        lock.unlock()
        return NativeWorktreeCleanupResult()
    }

    func waitUntilCreateStarts(timeout: TimeInterval = 1.0) -> Bool {
        createStarted.wait(timeout: .now() + timeout) == .success
    }

    func finishCreate() {
        allowFinish.signal()
    }
}

private func canonicalPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
}
