import XCTest
import Observation
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelWorkspaceDiffTabTests: XCTestCase {
    private final class ObservationCounter: @unchecked Sendable {
        var count = 0
    }

    func testOpenWorkspaceDiffTabCreatesRuntimeDiffTabAndSelectsIt() {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        let request = WorkspaceDiffOpenRequest(
            projectPath: project.path,
            source: .gitLogCommitFile(
                repositoryPath: project.path,
                commitHash: "abc1234",
                filePath: "README.md"
            ),
            preferredTitle: "Commit: README.md"
        )

        let opened = viewModel.openWorkspaceDiffTab(request)

        XCTAssertEqual(viewModel.activeWorkspaceDiffTabs.count, 1)
        XCTAssertEqual(viewModel.activeWorkspaceDiffTabs.first?.id, opened.id)
        XCTAssertEqual(viewModel.activeWorkspaceDiffTabs.first?.title, "Commit: README.md")
        XCTAssertEqual(viewModel.activeWorkspaceSelectedPresentedTab, .diff(opened.id))
    }

    func testOpenWorkspaceDiffTabReusesExistingTabForSameIdentity() {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        let request = WorkspaceDiffOpenRequest(
            projectPath: project.path,
            source: .gitLogCommitFile(
                repositoryPath: project.path,
                commitHash: "abc1234",
                filePath: "README.md"
            ),
            preferredTitle: "Commit: README.md"
        )

        let first = viewModel.openWorkspaceDiffTab(request)
        let second = viewModel.openWorkspaceDiffTab(request)

        XCTAssertEqual(viewModel.activeWorkspaceDiffTabs.count, 1)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(viewModel.activeWorkspaceSelectedPresentedTab, .diff(first.id))
    }

    func testCloseWorkspaceDiffTabDoesNotAffectTerminalTabs() throws {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)
        viewModel.createWorkspaceTab()
        let terminalTabCount = try XCTUnwrap(viewModel.activeWorkspaceState?.tabs.count)

        let first = viewModel.openWorkspaceDiffTab(
            WorkspaceDiffOpenRequest(
                projectPath: project.path,
                source: .gitLogCommitFile(
                    repositoryPath: project.path,
                    commitHash: "abc1234",
                    filePath: "README.md"
                ),
                preferredTitle: "Commit: README.md"
            )
        )
        _ = viewModel.openWorkspaceDiffTab(
            WorkspaceDiffOpenRequest(
                projectPath: project.path,
                source: .workingTreeChange(
                    repositoryPath: project.path,
                    executionPath: project.path,
                    filePath: "Package.swift",
                    group: nil,
                    status: nil,
                    oldPath: nil
                ),
                preferredTitle: "Changes: Package.swift"
            )
        )

        viewModel.closeWorkspaceDiffTab(first.id)

        XCTAssertEqual(viewModel.activeWorkspaceState?.tabs.count, terminalTabCount)
        XCTAssertEqual(viewModel.activeWorkspaceDiffTabs.count, 1)
    }

    func testOpenActiveWorkspaceDiffTabUsesCurrentActiveWorkspaceProjectPath() throws {
        let viewModel = makeViewModel()
        let rootProject = makeProject(
            path: "/tmp/devhaven-root",
            worktrees: [
                ProjectWorktree(
                    id: "worktree-1",
                    name: "feature",
                    path: "/tmp/devhaven-root-feature",
                    branch: "feature/diff",
                    inheritConfig: true,
                    created: 1
                )
            ]
        )
        viewModel.snapshot.projects = [rootProject]
        viewModel.openWorkspaceWorktree("/tmp/devhaven-root-feature", from: rootProject.path)

        let opened = try XCTUnwrap(
            viewModel.openActiveWorkspaceDiffTab(
                source: .workingTreeChange(
                    repositoryPath: rootProject.path,
                    executionPath: "/tmp/devhaven-root-feature",
                    filePath: "README.md",
                    group: nil,
                    status: nil,
                    oldPath: nil
                ),
                preferredTitle: "Changes: README.md"
            )
        )

        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, "/tmp/devhaven-root-feature")
        XCTAssertEqual(
            viewModel.workspacePresentedTabs(for: "/tmp/devhaven-root-feature").last?.selection,
            .diff(opened.id)
        )
        XCTAssertTrue(viewModel.workspacePresentedTabs(for: rootProject.path).isEmpty)
    }

    func testOpenActiveWorkspaceDiffTabSwitchesFocusToDiffAndCloseRestoresGitOriginContext() throws {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)
        let originTerminalTabID = try XCTUnwrap(viewModel.activeWorkspaceState?.selectedTab?.id)
        viewModel.setWorkspaceFocusedArea(.bottomToolWindow(.git))

        let opened = try XCTUnwrap(
            viewModel.openActiveWorkspaceDiffTab(
                source: .gitLogCommitFile(
                    repositoryPath: project.path,
                    commitHash: "abc1234",
                    filePath: "README.md"
                ),
                preferredTitle: "Commit: README.md"
            )
        )

        XCTAssertEqual(viewModel.activeWorkspaceSelectedPresentedTab, .diff(opened.id))
        XCTAssertEqual(viewModel.workspaceFocusedArea, .diffTab(opened.id))

        viewModel.closeWorkspaceDiffTab(opened.id)

        XCTAssertEqual(viewModel.activeWorkspaceSelectedPresentedTab, .terminal(originTerminalTabID))
        XCTAssertEqual(viewModel.workspaceFocusedArea, .bottomToolWindow(.git))
    }

    func testOpenActiveWorkspaceDiffTabSwitchesFocusToDiffAndCloseRestoresCommitOriginContext() throws {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)
        let originTerminalTabID = try XCTUnwrap(viewModel.activeWorkspaceState?.selectedTab?.id)
        viewModel.setWorkspaceFocusedArea(.sideToolWindow(.commit))

        let opened = try XCTUnwrap(
            viewModel.openActiveWorkspaceDiffTab(
                source: .workingTreeChange(
                    repositoryPath: project.path,
                    executionPath: project.path,
                    filePath: "Package.swift",
                    group: nil,
                    status: nil,
                    oldPath: nil
                ),
                preferredTitle: "Changes: Package.swift"
            )
        )

        XCTAssertEqual(viewModel.activeWorkspaceSelectedPresentedTab, .diff(opened.id))
        XCTAssertEqual(viewModel.workspaceFocusedArea, .diffTab(opened.id))

        viewModel.closeWorkspaceDiffTab(opened.id)

        XCTAssertEqual(viewModel.activeWorkspaceSelectedPresentedTab, .terminal(originTerminalTabID))
        XCTAssertEqual(viewModel.workspaceFocusedArea, .sideToolWindow(.commit))
    }

    func testOpenActiveWorkspaceCommitDiffPreviewReusesSinglePreviewTabAndUpdatesSource() throws {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        let first = try XCTUnwrap(
            viewModel.openActiveWorkspaceCommitDiffPreview(
                repositoryPath: project.path,
                executionPath: project.path,
                filePath: "README.md",
                group: .unstaged,
                status: .modified,
                oldPath: nil,
                preferredTitle: "Changes: README.md"
            )
        )
        let second = try XCTUnwrap(
            viewModel.openActiveWorkspaceCommitDiffPreview(
                repositoryPath: project.path,
                executionPath: project.path,
                filePath: "Package.swift",
                group: .unstaged,
                status: .modified,
                oldPath: nil,
                preferredTitle: "Changes: Package.swift"
            )
        )

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(viewModel.activeWorkspaceDiffTabs.count, 1)
        XCTAssertEqual(viewModel.activeWorkspaceDiffTabs.first?.title, "Changes: Package.swift")
        XCTAssertEqual(
            viewModel.activeWorkspaceDiffTabs.first?.identity,
            "commit-preview|/tmp/devhaven"
        )
        XCTAssertEqual(
            viewModel.activeWorkspaceDiffTabs.first?.source,
            .workingTreeChange(
                repositoryPath: project.path,
                executionPath: project.path,
                filePath: "Package.swift",
                group: .unstaged,
                status: .modified,
                oldPath: nil
            )
        )
        XCTAssertEqual(viewModel.activeWorkspaceSelectedPresentedTab, .diff(first.id))
        XCTAssertEqual(viewModel.workspaceFocusedArea, .diffTab(first.id))
    }

    func testOpenActiveWorkspaceCommitDiffPreviewBuildsRequestChainFromSnapshot() throws {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)
        viewModel.prepareActiveWorkspaceCommitViewModel()
        let commitViewModel = try XCTUnwrap(viewModel.activeWorkspaceCommitViewModel)
        commitViewModel.changesSnapshot = WorkspaceCommitChangesSnapshot(
            branchName: "main",
            changes: [
                WorkspaceCommitChange(
                    path: "README.md",
                    status: .modified,
                    group: .unstaged,
                    isIncludedByDefault: false
                ),
                WorkspaceCommitChange(
                    path: "Package.swift",
                    oldPath: "Package.old.swift",
                    status: .renamed,
                    group: .conflicted,
                    isIncludedByDefault: false
                ),
            ]
        )

        _ = try XCTUnwrap(
            viewModel.openActiveWorkspaceCommitDiffPreview(
                repositoryPath: project.path,
                executionPath: project.path,
                filePath: "Package.swift",
                group: .conflicted,
                status: .renamed,
                oldPath: "Package.old.swift",
                allChanges: commitViewModel.changesSnapshot?.changes,
                preferredTitle: "Changes: Package.swift"
            )
        )

        let chain = try XCTUnwrap(viewModel.activeWorkspaceDiffTabs.first?.requestChain)
        XCTAssertEqual(chain.items.count, 2)
        XCTAssertEqual(chain.activeIndex, 1)
        XCTAssertEqual(
            chain.items.map(\.source),
            [
                .workingTreeChange(
                    repositoryPath: project.path,
                    executionPath: project.path,
                    filePath: "README.md",
                    group: .unstaged,
                    status: .modified,
                    oldPath: nil
                ),
                .workingTreeChange(
                    repositoryPath: project.path,
                    executionPath: project.path,
                    filePath: "Package.swift",
                    group: .conflicted,
                    status: .renamed,
                    oldPath: "Package.old.swift"
                ),
            ]
        )
    }

    func testGitLogOpenDiffBuildsRequestChainFromCommitChanges() throws {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)
        viewModel.prepareActiveWorkspaceGitViewModel()
        let gitViewModel = try XCTUnwrap(viewModel.activeWorkspaceGitViewModel)
        gitViewModel.logViewModel.selectedCommitHash = "abc1234"
        gitViewModel.logViewModel.selectedCommitDetail = WorkspaceGitCommitDetail(
            hash: "abc1234",
            shortHash: "abc1234",
            parentHashes: ["def5678"],
            authorName: "DevHaven",
            authorEmail: "devhaven@example.com",
            authorTimestamp: 1_774_582_000,
            subject: "feat: diff session",
            body: nil,
            decorations: nil,
            changedFiles: [
                WorkspaceGitCommitFileChange(path: "README.md", status: .modified),
                WorkspaceGitCommitFileChange(path: "Package.swift", oldPath: "Package.old.swift", status: .renamed),
            ]
        )

        _ = try XCTUnwrap(
            viewModel.openActiveWorkspaceDiffTab(
                source: .gitLogCommitFile(
                    repositoryPath: project.path,
                    commitHash: "abc1234",
                    filePath: "Package.swift"
                ),
                preferredTitle: "Commit: Package.swift"
            )
        )

        let chain = try XCTUnwrap(viewModel.activeWorkspaceDiffTabs.first?.requestChain)
        XCTAssertEqual(chain.items.count, 2)
        XCTAssertEqual(chain.activeIndex, 1)
        XCTAssertEqual(
            chain.items.map(\.source),
            [
                .gitLogCommitFile(
                    repositoryPath: project.path,
                    commitHash: "abc1234",
                    filePath: "README.md"
                ),
                .gitLogCommitFile(
                    repositoryPath: project.path,
                    commitHash: "abc1234",
                    filePath: "Package.swift"
                ),
            ]
        )
        XCTAssertEqual(chain.items[1].paneMetadataSeeds.last?.oldPath, "Package.old.swift")
        XCTAssertEqual(chain.items[1].paneMetadataSeeds.last?.hash, "abc1234")
    }

    func testCommitPreviewIdentityStillReusesSingleRuntimeTabWhileSwitchingSessionItem() throws {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)
        viewModel.prepareActiveWorkspaceCommitViewModel()
        let commitViewModel = try XCTUnwrap(viewModel.activeWorkspaceCommitViewModel)
        commitViewModel.changesSnapshot = WorkspaceCommitChangesSnapshot(
            branchName: "main",
            changes: [
                WorkspaceCommitChange(
                    path: "README.md",
                    status: .modified,
                    group: .unstaged,
                    isIncludedByDefault: false
                ),
                WorkspaceCommitChange(
                    path: "Package.swift",
                    status: .modified,
                    group: .unstaged,
                    isIncludedByDefault: false
                ),
            ]
        )

        let first = try XCTUnwrap(
            viewModel.openActiveWorkspaceCommitDiffPreview(
                repositoryPath: project.path,
                executionPath: project.path,
                filePath: "README.md",
                group: .unstaged,
                status: .modified,
                oldPath: nil,
                allChanges: commitViewModel.changesSnapshot?.changes,
                preferredTitle: "Changes: README.md"
            )
        )
        let second = try XCTUnwrap(
            viewModel.openActiveWorkspaceCommitDiffPreview(
                repositoryPath: project.path,
                executionPath: project.path,
                filePath: "Package.swift",
                group: .unstaged,
                status: .modified,
                oldPath: nil,
                allChanges: commitViewModel.changesSnapshot?.changes,
                preferredTitle: "Changes: Package.swift"
            )
        )

        XCTAssertEqual(first.id, second.id)
        let chain = try XCTUnwrap(viewModel.activeWorkspaceDiffTabs.first?.requestChain)
        XCTAssertEqual(chain.items.count, 2)
        XCTAssertEqual(chain.activeIndex, 1)
        XCTAssertEqual(viewModel.activeWorkspaceDiffTabs.first?.identity, "commit-preview|/tmp/devhaven")
        XCTAssertEqual(viewModel.activeWorkspaceDiffTabs.first?.title, "Changes: Package.swift")
    }

    func testSyncActiveWorkspaceCommitDiffPreviewIfNeededDoesNotCreateTabWhenPreviewAbsent() {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)
        let originalSelection = viewModel.activeWorkspaceSelectedPresentedTab
        let originalFocus = viewModel.workspaceFocusedArea

        viewModel.syncActiveWorkspaceCommitDiffPreviewIfNeeded(
            repositoryPath: project.path,
            executionPath: project.path,
            filePath: "README.md",
            group: .unstaged,
            status: .modified,
            oldPath: nil,
            preferredTitle: "Changes: README.md"
        )

        XCTAssertTrue(viewModel.activeWorkspaceDiffTabs.isEmpty)
        XCTAssertEqual(viewModel.activeWorkspaceSelectedPresentedTab, originalSelection)
        XCTAssertEqual(viewModel.workspaceFocusedArea, originalFocus)
    }

    func testSyncActiveWorkspaceCommitDiffPreviewIfNeededUpdatesExistingPreviewWithoutChangingSelection() throws {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)
        let terminalTabID = try XCTUnwrap(viewModel.activeWorkspaceState?.selectedTab?.id)

        let opened = try XCTUnwrap(
            viewModel.openActiveWorkspaceCommitDiffPreview(
                repositoryPath: project.path,
                executionPath: project.path,
                filePath: "README.md",
                group: .unstaged,
                status: .modified,
                oldPath: nil,
                preferredTitle: "Changes: README.md"
            )
        )

        viewModel.selectWorkspacePresentedTab(.terminal(terminalTabID))
        viewModel.setWorkspaceFocusedArea(.sideToolWindow(.commit))

        viewModel.syncActiveWorkspaceCommitDiffPreviewIfNeeded(
            repositoryPath: project.path,
            executionPath: project.path,
            filePath: "Package.swift",
            group: .conflicted,
            status: .unmerged,
            oldPath: "Package.old.swift",
            preferredTitle: "Changes: Package.swift"
        )

        XCTAssertEqual(viewModel.activeWorkspaceDiffTabs.count, 1)
        XCTAssertEqual(viewModel.activeWorkspaceDiffTabs.first?.id, opened.id)
        XCTAssertEqual(viewModel.activeWorkspaceDiffTabs.first?.title, "Changes: Package.swift")
        XCTAssertEqual(
            viewModel.activeWorkspaceDiffTabs.first?.source,
            .workingTreeChange(
                repositoryPath: project.path,
                executionPath: project.path,
                filePath: "Package.swift",
                group: .conflicted,
                status: .unmerged,
                oldPath: "Package.old.swift"
            )
        )
        XCTAssertEqual(viewModel.activeWorkspaceSelectedPresentedTab, .terminal(terminalTabID))
        XCTAssertEqual(viewModel.workspaceFocusedArea, .sideToolWindow(.commit))
    }

    func testWorkspaceDiffTabViewModelGetterDoesNotInvalidateExistingDiffViewModel() throws {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        let opened = viewModel.openWorkspaceDiffTab(
            WorkspaceDiffOpenRequest(
                projectPath: project.path,
                source: .gitLogCommitFile(
                    repositoryPath: project.path,
                    commitHash: "abc1234",
                    filePath: "README.md"
                ),
                preferredTitle: "Commit: README.md"
            )
        )
        let diffViewModel = try XCTUnwrap(
            viewModel.workspaceDiffTabViewModel(for: project.path, tabID: opened.id)
        )
        let counter = ObservationCounter()

        withObservationTracking {
            _ = diffViewModel.tab
            _ = diffViewModel.documentState.title
            _ = diffViewModel.documentState.viewerMode
            _ = diffViewModel.documentState.loadState
        } onChange: {
            counter.count += 1
        }

        let sameViewModel = viewModel.workspaceDiffTabViewModel(for: project.path, tabID: opened.id)

        XCTAssertTrue(diffViewModel === sameViewModel, "getter 应复用同一实例")
        XCTAssertEqual(counter.count, 0, "纯 getter 不应触发 diff view model 的观察失效")
    }

    private func makeViewModel() -> NativeAppViewModel {
        NativeAppViewModel(
            store: LegacyCompatStore(homeDirectoryURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)),
            projectDocumentLoader: { _ in ProjectDocumentSnapshot(notes: nil, todoItems: [], readmeFallback: nil) },
            gitDailyCollector: { _, _ in [] },
            gitDailyCollectorAsync: { _, _, _ in [] },
            terminalCommandRunner: { _, _ in }
        )
    }

    private func makeProject(
        id: String = "project-1",
        name: String = "DevHaven",
        path: String = "/tmp/devhaven",
        worktrees: [ProjectWorktree] = []
    ) -> Project {
        Project(
            id: id,
            name: name,
            path: path,
            tags: [],
            runConfigurations: [],
            worktrees: worktrees,
            mtime: 1,
            size: 0,
            checksum: "checksum",
            isGitRepository: true,
            gitCommits: 10,
            gitLastCommit: 1,
            gitLastCommitMessage: "feat: workspace",
            gitDaily: nil,
            created: 1,
            checked: 1
        )
    }
}
