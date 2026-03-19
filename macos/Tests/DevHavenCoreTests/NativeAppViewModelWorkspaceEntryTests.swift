import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelWorkspaceEntryTests: XCTestCase {
    func testEnterWorkspaceTracksActiveProjectAndClosesDetailPanel() {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.isDetailPanelPresented = true

        viewModel.enterWorkspace(project.path)

        XCTAssertEqual(viewModel.selectedProjectPath, project.path)
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, project.path)
        XCTAssertEqual(viewModel.activeWorkspaceProject?.path, project.path)
        XCTAssertFalse(viewModel.isDetailPanelPresented)
    }

    func testExitWorkspaceClearsActiveWorkspaceProject() {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        viewModel.exitWorkspace()

        XCTAssertNil(viewModel.activeWorkspaceProjectPath)
        XCTAssertNil(viewModel.activeWorkspaceProject)
    }

    func testOpenWorkspaceInTerminalRunsOpenCommandForActiveProjectPath() throws {
        let capture = CommandCapture()
        let viewModel = makeViewModel { executable, arguments in
            capture.executable = executable
            capture.arguments = arguments
        }
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        try viewModel.openActiveWorkspaceInTerminal()

        XCTAssertEqual(capture.executable, "/usr/bin/open")
        XCTAssertEqual(capture.arguments, ["-a", "Terminal", project.path])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testOpenWorkspaceInTerminalStoresErrorMessageWhenCommandFails() {
        let viewModel = makeViewModel { _, _ in
            throw TestTerminalRunnerError.launchFailed
        }
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        XCTAssertThrowsError(try viewModel.openActiveWorkspaceInTerminal())
        XCTAssertEqual(viewModel.errorMessage, "terminal launch failed")
    }

    private func makeViewModel(
        terminalCommandRunner: @escaping @Sendable (String, [String]) throws -> Void = { _, _ in }
    ) -> NativeAppViewModel {
        NativeAppViewModel(
            store: LegacyCompatStore(homeDirectoryURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)),
            projectDocumentLoader: { _ in ProjectDocumentSnapshot(notes: nil, todoItems: [], readmeFallback: nil) },
            gitDailyCollector: { _, _ in [] },
            gitDailyCollectorAsync: { _, _, _ in [] },
            terminalCommandRunner: terminalCommandRunner
        )
    }

    private func makeProject() -> Project {
        Project(
            id: "project-1",
            name: "DevHaven",
            path: "/tmp/devhaven",
            tags: [],
            scripts: [],
            worktrees: [],
            mtime: 1,
            size: 0,
            checksum: "checksum",
            gitCommits: 10,
            gitLastCommit: 1,
            gitLastCommitMessage: "feat: workspace",
            gitDaily: nil,
            created: 1,
            checked: 1
        )
    }
}

private final class CommandCapture: @unchecked Sendable {
    var executable: String?
    var arguments: [String] = []
}

private enum TestTerminalRunnerError: LocalizedError {
    case launchFailed

    var errorDescription: String? {
        switch self {
        case .launchFailed:
            return "terminal launch failed"
        }
    }
}
