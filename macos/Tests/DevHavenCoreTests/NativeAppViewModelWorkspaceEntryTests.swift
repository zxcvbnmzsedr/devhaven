import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelWorkspaceEntryTests: XCTestCase {
    func testEnterWorkspaceTracksActiveProjectAndCreatesSingleTabSinglePaneSession() {
        let diagnostics = DiagnosticsCapture()
        let viewModel = makeViewModel(diagnostics: diagnostics.diagnostics)
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.isDetailPanelPresented = true

        viewModel.enterWorkspace(project.path)

        XCTAssertEqual(viewModel.selectedProjectPath, project.path)
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, project.path)
        XCTAssertEqual(viewModel.activeWorkspaceProject?.path, project.path)
        XCTAssertIdentical(viewModel.activeWorkspaceController, viewModel.openWorkspaceSessions.first?.controller)
        XCTAssertFalse(viewModel.isDetailPanelPresented)
        XCTAssertEqual(viewModel.activeWorkspaceState?.tabs.count, 1)
        XCTAssertEqual(viewModel.activeWorkspaceState?.selectedTab?.leaves.count, 1)
        XCTAssertEqual(viewModel.activeWorkspaceLaunchRequest?.projectPath, project.path)
        XCTAssertEqual(
            diagnostics.events,
            [
                .entryRequested(
                    workspaceId: try! XCTUnwrap(viewModel.activeWorkspaceState?.workspaceId),
                    projectPath: project.path,
                    openSessionCount: 1,
                    tabCount: 1,
                    paneCount: 1
                ),
            ]
        )
    }


    func testEnteringMultipleProjectsKeepsOpenWorkspaceListAndActivatesLatestProject() {
        let viewModel = makeViewModel()
        let alpha = makeProject(id: "project-1", name: "Alpha", path: "/tmp/alpha")
        let beta = makeProject(id: "project-2", name: "Beta", path: "/tmp/beta")
        viewModel.snapshot.projects = [alpha, beta]

        viewModel.enterWorkspace(alpha.path)
        viewModel.enterWorkspace(beta.path)

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [alpha.path, beta.path])
        XCTAssertEqual(viewModel.openWorkspaceProjects.map(\.path), [alpha.path, beta.path])
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, beta.path)
        XCTAssertEqual(viewModel.activeWorkspaceProject?.path, beta.path)
        XCTAssertEqual(viewModel.activeWorkspaceState?.projectPath, beta.path)
    }

    func testEnteringAlreadyOpenedProjectDoesNotDuplicateWorkspaceSession() {
        let viewModel = makeViewModel()
        let alpha = makeProject(id: "project-1", name: "Alpha", path: "/tmp/alpha")
        let beta = makeProject(id: "project-2", name: "Beta", path: "/tmp/beta")
        viewModel.snapshot.projects = [alpha, beta]

        viewModel.enterWorkspace(alpha.path)
        viewModel.enterWorkspace(beta.path)
        viewModel.enterWorkspace(alpha.path)

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [alpha.path, beta.path])
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, alpha.path)
    }

    func testWorkspaceAvailableProjectsExcludeAlreadyOpenedSessions() {
        let viewModel = makeViewModel()
        let alpha = makeProject(id: "project-1", name: "Alpha", path: "/tmp/alpha")
        let beta = makeProject(id: "project-2", name: "Beta", path: "/tmp/beta")
        let gamma = makeProject(id: "project-3", name: "Gamma", path: "/tmp/gamma")
        viewModel.snapshot.projects = [alpha, beta, gamma]

        viewModel.enterWorkspace(alpha.path)
        viewModel.enterWorkspace(beta.path)

        XCTAssertEqual(viewModel.availableWorkspaceProjects.map(\.path), [gamma.path])
    }

    func testSelectingAnotherProjectWhileWorkspaceIsOpenKeepsOpenedSessionsAlive() {
        let viewModel = makeViewModel()
        let alpha = makeProject(id: "project-1", name: "Alpha", path: "/tmp/alpha")
        let beta = makeProject(id: "project-2", name: "Beta", path: "/tmp/beta")
        let gamma = makeProject(id: "project-3", name: "Gamma", path: "/tmp/gamma")
        viewModel.snapshot.projects = [alpha, beta, gamma]

        viewModel.enterWorkspace(alpha.path)
        viewModel.enterWorkspace(beta.path)

        viewModel.selectProject(gamma.path)

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [alpha.path, beta.path])
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, beta.path)
        XCTAssertEqual(viewModel.selectedProjectPath, gamma.path)
        XCTAssertTrue(viewModel.isDetailPanelPresented)
    }

    func testSwitchingActiveWorkspaceProjectPreservesEachProjectsTopology() throws {
        let viewModel = makeViewModel()
        let alpha = makeProject(id: "project-1", name: "Alpha", path: "/tmp/alpha")
        let beta = makeProject(id: "project-2", name: "Beta", path: "/tmp/beta")
        viewModel.snapshot.projects = [alpha, beta]

        viewModel.enterWorkspace(alpha.path)
        viewModel.createWorkspaceTab()
        viewModel.selectWorkspaceTab(try XCTUnwrap(viewModel.activeWorkspaceState?.tabs.first?.id))
        viewModel.splitWorkspaceFocusedPane(direction: .right)
        let alphaTabCount = viewModel.activeWorkspaceState?.tabs.count
        let alphaPaneCount = viewModel.activeWorkspaceState?.selectedTab?.leaves.count

        viewModel.enterWorkspace(beta.path)
        XCTAssertEqual(viewModel.activeWorkspaceState?.projectPath, beta.path)
        XCTAssertEqual(viewModel.activeWorkspaceState?.tabs.count, 1)
        XCTAssertEqual(viewModel.activeWorkspaceState?.selectedTab?.leaves.count, 1)

        viewModel.activateWorkspaceProject(alpha.path)
        XCTAssertEqual(viewModel.activeWorkspaceState?.projectPath, alpha.path)
        XCTAssertEqual(viewModel.activeWorkspaceState?.tabs.count, alphaTabCount)
        XCTAssertEqual(viewModel.activeWorkspaceState?.selectedTab?.leaves.count, alphaPaneCount)
    }

    func testClosingWorkspaceProjectFallsBackToRemainingProjectAndLastCloseExitsWorkspace() {
        let viewModel = makeViewModel()
        let alpha = makeProject(id: "project-1", name: "Alpha", path: "/tmp/alpha")
        let beta = makeProject(id: "project-2", name: "Beta", path: "/tmp/beta")
        viewModel.snapshot.projects = [alpha, beta]

        viewModel.enterWorkspace(alpha.path)
        viewModel.enterWorkspace(beta.path)

        viewModel.closeWorkspaceProject(beta.path)
        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [alpha.path])
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, alpha.path)
        XCTAssertEqual(viewModel.activeWorkspaceState?.projectPath, alpha.path)

        viewModel.closeWorkspaceProject(alpha.path)
        XCTAssertTrue(viewModel.openWorkspaceProjectPaths.isEmpty)
        XCTAssertTrue(viewModel.openWorkspaceProjects.isEmpty)
        XCTAssertNil(viewModel.activeWorkspaceProjectPath)
        XCTAssertNil(viewModel.activeWorkspaceState)
        XCTAssertFalse(viewModel.isWorkspacePresented)
    }

    func testWorkspaceTabAndPaneActionsMutateActiveWorkspaceState() throws {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        let firstTabID = try XCTUnwrap(viewModel.activeWorkspaceState?.selectedTab?.id)
        let firstPaneID = try XCTUnwrap(viewModel.activeWorkspaceState?.selectedPane?.id)

        viewModel.createWorkspaceTab()
        let secondTabID = try XCTUnwrap(viewModel.activeWorkspaceState?.selectedTab?.id)
        XCTAssertNotEqual(secondTabID, firstTabID)
        XCTAssertEqual(viewModel.activeWorkspaceState?.tabs.count, 2)

        viewModel.selectWorkspaceTab(firstTabID)
        viewModel.splitWorkspaceFocusedPane(direction: .right)
        XCTAssertEqual(viewModel.activeWorkspaceState?.selectedTab?.leaves.count, 2)
        XCTAssertNotEqual(viewModel.activeWorkspaceState?.selectedTab?.focusedPaneId, firstPaneID)

        let focusedPaneID = try XCTUnwrap(viewModel.activeWorkspaceState?.selectedTab?.focusedPaneId)
        viewModel.closeWorkspacePane(focusedPaneID)
        XCTAssertEqual(viewModel.activeWorkspaceState?.selectedTab?.leaves.count, 1)
        XCTAssertEqual(viewModel.activeWorkspaceState?.selectedTab?.focusedPaneId, firstPaneID)
    }

    func testExitWorkspacePreservesOpenSessionsForLaterReentry() {
        let viewModel = makeViewModel()
        let alpha = makeProject(id: "project-1", name: "Alpha", path: "/tmp/alpha")
        let beta = makeProject(id: "project-2", name: "Beta", path: "/tmp/beta")
        viewModel.snapshot.projects = [alpha, beta]

        viewModel.enterWorkspace(alpha.path)
        viewModel.enterWorkspace(beta.path)

        viewModel.exitWorkspace()

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [alpha.path, beta.path])
        XCTAssertNil(viewModel.activeWorkspaceProjectPath)
        XCTAssertNil(viewModel.activeWorkspaceState)
        XCTAssertFalse(viewModel.isWorkspacePresented)

        viewModel.selectProject(alpha.path)
        XCTAssertFalse(viewModel.isWorkspacePresented)
        XCTAssertTrue(viewModel.isDetailPanelPresented)

        viewModel.enterWorkspace(alpha.path)
        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [alpha.path, beta.path])
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, alpha.path)
        XCTAssertEqual(viewModel.activeWorkspaceState?.projectPath, alpha.path)
        XCTAssertTrue(viewModel.isWorkspacePresented)
    }

    func testExitWorkspaceKeepsSingleProjectSessionAvailableForReentry() {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        viewModel.exitWorkspace()

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [project.path])
        XCTAssertEqual(viewModel.openWorkspaceProjects.map(\.path), [project.path])
        XCTAssertNil(viewModel.activeWorkspaceProjectPath)
        XCTAssertNil(viewModel.activeWorkspaceProject)
        XCTAssertNil(viewModel.activeWorkspaceState)
        XCTAssertNil(viewModel.activeWorkspaceLaunchRequest)
        XCTAssertFalse(viewModel.isWorkspacePresented)
    }

    func testSplitActiveWorkspaceRightAddsPaneToSelectedTab() {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        viewModel.splitActiveWorkspaceRight()

        XCTAssertEqual(viewModel.activeWorkspaceState?.selectedTab?.leaves.count, 2)
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
        diagnostics: WorkspaceLaunchDiagnostics = .shared,
        terminalCommandRunner: @escaping @Sendable (String, [String]) throws -> Void = { _, _ in }
    ) -> NativeAppViewModel {
        NativeAppViewModel(
            store: LegacyCompatStore(homeDirectoryURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)),
            projectDocumentLoader: { _ in ProjectDocumentSnapshot(notes: nil, todoItems: [], readmeFallback: nil) },
            gitDailyCollector: { _, _ in [] },
            gitDailyCollectorAsync: { _, _, _ in [] },
            workspaceLaunchDiagnostics: diagnostics,
            terminalCommandRunner: terminalCommandRunner
        )
    }

    private func makeProject(
        id: String = "project-1",
        name: String = "DevHaven",
        path: String = "/tmp/devhaven"
    ) -> Project {
        Project(
            id: id,
            name: name,
            path: path,
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

@MainActor
private final class DiagnosticsCapture {
    var events = [WorkspaceLaunchDiagnosticEvent]()

    lazy var diagnostics = WorkspaceLaunchDiagnostics(
        now: { 1_000 },
        logSink: { _ in },
        eventSink: { [weak self] event in
            self?.events.append(event)
        }
    )
}
