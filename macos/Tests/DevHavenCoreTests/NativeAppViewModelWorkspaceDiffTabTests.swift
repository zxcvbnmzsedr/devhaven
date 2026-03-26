import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelWorkspaceDiffTabTests: XCTestCase {
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
                    filePath: "Package.swift"
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
                    filePath: "README.md"
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
                    filePath: "Package.swift"
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
            scripts: [],
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
