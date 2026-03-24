import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelWorkspaceRunTests: XCTestCase {
    func testSelectionDefaultsToFirstProjectConfigurationAndRunCreatesVisibleSession() throws {
        let runManager = TestWorkspaceRunManager()
        let viewModel = makeViewModel(runManager: runManager)
        let project = makeProject(
            scripts: [
                ProjectScript(id: "dev", name: "Dev", start: "npm run dev"),
                ProjectScript(id: "worker", name: "Worker", start: "python worker.py")
            ]
        )
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        XCTAssertEqual(viewModel.selectedWorkspaceRunConfiguration()?.source, .projectScript)
        XCTAssertEqual(viewModel.selectedWorkspaceRunConfiguration()?.sourceID, "dev")

        viewModel.selectWorkspaceRunConfiguration("project::\(project.path)::worker")
        try viewModel.runSelectedWorkspaceConfiguration()

        XCTAssertEqual(runManager.startedRequests.last?.configurationID, "project::\(project.path)::worker")
        XCTAssertEqual(runManager.startedRequests.last?.configurationName, "Worker")
        XCTAssertEqual(runManager.startedRequests.last?.command, "python worker.py")
        let state = try XCTUnwrap(viewModel.workspaceRunConsoleState(for: project.path))
        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.sessions.count, 1)
        XCTAssertEqual(state.selectedConfigurationID, "project::\(project.path)::worker")
        XCTAssertEqual(state.selectedSession?.configurationID, "project::\(project.path)::worker")
    }

    func testAvailableConfigurationsIgnoreSharedScriptsAndOnlyExposeProjectScripts() throws {
        let runManager = TestWorkspaceRunManager()
        let homeURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = LegacyCompatStore(homeDirectoryURL: homeURL)
        let sharedRoot = homeURL.appending(path: "shared-scripts", directoryHint: .isDirectory)
        try store.saveSharedScriptsManifest(
            [
                SharedScriptManifestScript(
                    id: "shared-log",
                    name: "通用日志查看",
                    path: "ops/shared-log.sh",
                    commandTemplate: "bash \"${scriptPath}\" --lines \"${lines}\"",
                    params: [
                        ScriptParamField(key: "lines", label: "输出行数", type: .number, required: true, defaultValue: "200", description: nil)
                    ]
                )
            ],
            rootOverride: sharedRoot.path
        )
        try store.writeSharedScriptFile(
            relativePath: "ops/shared-log.sh",
            content: "#!/usr/bin/env bash\necho shared\n",
            rootOverride: sharedRoot.path
        )

        let viewModel = makeViewModel(runManager: runManager, store: store)
        var settings = viewModel.snapshot.appState.settings
        settings.sharedScriptsRoot = sharedRoot.path
        viewModel.snapshot.appState.settings = settings

        let project = makeProject(scripts: [ProjectScript(id: "dev", name: "Dev", start: "npm run dev")])
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        let configurations = viewModel.availableWorkspaceRunConfigurations(in: project.path)
        XCTAssertEqual(configurations.count, 1)
        XCTAssertEqual(configurations.map(\.source), [.projectScript])
        XCTAssertEqual(configurations.first?.sourceID, "dev")
    }

    func testRunManagerEventsAppendOutputAndUpdateFinalState() throws {
        let runManager = TestWorkspaceRunManager()
        let viewModel = makeViewModel(runManager: runManager)
        let project = makeProject(scripts: [ProjectScript(id: "dev", name: "Dev", start: "npm run dev")])
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)
        try viewModel.runSelectedWorkspaceConfiguration()

        let sessionID = try XCTUnwrap(viewModel.workspaceRunConsoleState(for: project.path)?.selectedSession?.id)
        runManager.emit(.output(projectPath: project.path, sessionID: sessionID, chunk: "ready\n"))
        runManager.emit(.stateChanged(projectPath: project.path, sessionID: sessionID, state: .completed(exitCode: 0)))

        let state = try XCTUnwrap(viewModel.workspaceRunConsoleState(for: project.path))
        XCTAssertEqual(state.selectedSession?.displayBuffer, "ready\n")
        XCTAssertEqual(state.selectedSession?.state, .completed(exitCode: 0))
    }

    func testRerunningSameConfigurationReusesSingleTabAndRestartsInPlace() throws {
        let runManager = TestWorkspaceRunManager()
        let viewModel = makeViewModel(runManager: runManager)
        let project = makeProject(scripts: [ProjectScript(id: "dev", name: "Dev", start: "npm run dev")])
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        try viewModel.runSelectedWorkspaceConfiguration()
        let firstSessionID = try XCTUnwrap(viewModel.workspaceRunConsoleState(for: project.path)?.selectedSession?.id)
        try viewModel.runSelectedWorkspaceConfiguration()

        let state = try XCTUnwrap(viewModel.workspaceRunConsoleState(for: project.path))
        XCTAssertEqual(state.sessions.count, 1, "同一运行配置再次启动时应复用原 tab，而不是继续累积 execution history")
        XCTAssertEqual(runManager.startedRequests.count, 2)
        XCTAssertEqual(runManager.stoppedSessionIDs, [firstSessionID], "同一配置重跑前应先停止旧进程，形成 restart-in-place 语义")
        XCTAssertEqual(state.selectedConfigurationID, "project::\(project.path)::dev")
        XCTAssertNotEqual(state.selectedSession?.id, firstSessionID)
    }

    func testMultipleConfigurationsCanBeSelectedAndStopTargetsCurrentSelection() throws {
        let runManager = TestWorkspaceRunManager()
        let viewModel = makeViewModel(runManager: runManager)
        let project = makeProject(
            scripts: [
                ProjectScript(id: "dev", name: "Dev", start: "npm run dev"),
                ProjectScript(id: "worker", name: "Worker", start: "python worker.py")
            ]
        )
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        try viewModel.runSelectedWorkspaceConfiguration()
        let firstSessionID = try XCTUnwrap(viewModel.workspaceRunConsoleState(for: project.path)?.selectedSession?.id)
        viewModel.selectWorkspaceRunConfiguration("project::\(project.path)::worker")
        try viewModel.runSelectedWorkspaceConfiguration()
        let secondSessionID = try XCTUnwrap(viewModel.workspaceRunConsoleState(for: project.path)?.selectedSession?.id)

        XCTAssertNotEqual(firstSessionID, secondSessionID)
        viewModel.selectWorkspaceRunSession(firstSessionID)
        viewModel.stopSelectedWorkspaceRunSession()

        XCTAssertEqual(runManager.stoppedSessionIDs, [firstSessionID])
    }

    func testTogglingConsoleVisibilityAndClosingWorkspaceClearsRunState() throws {
        let runManager = TestWorkspaceRunManager()
        let viewModel = makeViewModel(runManager: runManager)
        let project = makeProject(scripts: [ProjectScript(id: "dev", name: "Dev", start: "npm run dev")])
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)
        try viewModel.runSelectedWorkspaceConfiguration()

        viewModel.toggleWorkspaceRunConsole()
        XCTAssertFalse(viewModel.workspaceRunConsoleState(for: project.path)?.isVisible ?? true)
        viewModel.toggleWorkspaceRunConsole()
        XCTAssertTrue(viewModel.workspaceRunConsoleState(for: project.path)?.isVisible ?? false)

        viewModel.closeWorkspaceProject(project.path)
        XCTAssertNil(viewModel.workspaceRunConsoleState(for: project.path))
        XCTAssertEqual(runManager.stoppedProjectPaths, [project.path])
    }

    private func makeViewModel(runManager: TestWorkspaceRunManager, store: LegacyCompatStore? = nil) -> NativeAppViewModel {
        NativeAppViewModel(
            store: store ?? LegacyCompatStore(
                homeDirectoryURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            ),
            projectDocumentLoader: { _ in ProjectDocumentSnapshot(notes: nil, todoItems: [], readmeFallback: nil) },
            gitDailyCollector: { _, _ in [] },
            gitDailyCollectorAsync: { _, _, _ in [] },
            terminalCommandRunner: { _, _ in },
            runManager: runManager
        )
    }

    private func makeProject(scripts: [ProjectScript]) -> Project {
        Project(
            id: "project-1",
            name: "DevHaven",
            path: "/tmp/devhaven",
            tags: [],
            scripts: scripts,
            worktrees: [],
            mtime: 1,
            size: 0,
            checksum: "checksum",
            gitCommits: 1,
            gitLastCommit: 1,
            gitLastCommitMessage: "feat: run",
            gitDaily: nil,
            created: 1,
            checked: 1
        )
    }
}

@MainActor
private final class TestWorkspaceRunManager: WorkspaceRunManaging {
    var onEvent: (@MainActor @Sendable (WorkspaceRunManagerEvent) -> Void)?
    var startedRequests = [WorkspaceRunStartRequest]()
    var stoppedSessionIDs = [String]()
    var stoppedProjectPaths = [String]()

    func start(_ request: WorkspaceRunStartRequest) throws -> WorkspaceRunSession {
        startedRequests.append(request)
        return WorkspaceRunSession(
            id: request.sessionID,
            configurationID: request.configurationID,
            configurationName: request.configurationName,
            configurationSource: request.configurationSource,
            projectPath: request.projectPath,
            rootProjectPath: request.rootProjectPath,
            command: request.command,
            workingDirectory: request.workingDirectory,
            state: .running,
            processID: 100,
            logFilePath: "/tmp/\(request.sessionID).log",
            startedAt: Date(),
            endedAt: nil,
            displayBuffer: ""
        )
    }

    func stop(sessionID: String) {
        stoppedSessionIDs.append(sessionID)
    }

    func stopAll(projectPath: String) {
        stoppedProjectPaths.append(projectPath)
    }

    func emit(_ event: WorkspaceRunManagerEvent) {
        onEvent?(event)
    }
}
