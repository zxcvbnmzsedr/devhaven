import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelWorkspaceRunTests: XCTestCase {
    func testSelectionDefaultsToFirstRunConfigurationAndRunCreatesVisibleSession() throws {
        let runManager = TestWorkspaceRunManager()
        let viewModel = makeViewModel(runManager: runManager)
        let project = makeProject(
            runConfigurations: [
                ProjectRunConfiguration(
                    id: "dev",
                    name: "Dev",
                    kind: .customShell,
                    customShell: ProjectRunCustomShellConfiguration(command: "npm run dev")
                ),
                ProjectRunConfiguration(
                    id: "worker",
                    name: "Worker",
                    kind: .customShell,
                    customShell: ProjectRunCustomShellConfiguration(command: "python worker.py")
                )
            ]
        )
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        XCTAssertEqual(viewModel.selectedWorkspaceRunConfiguration()?.source, .projectRunConfiguration)
        XCTAssertEqual(viewModel.selectedWorkspaceRunConfiguration()?.sourceID, "dev")

        viewModel.selectWorkspaceRunConfiguration("project::\(project.path)::worker")
        try viewModel.runSelectedWorkspaceConfiguration()

        XCTAssertEqual(runManager.startedRequests.last?.configurationID, "project::\(project.path)::worker")
        XCTAssertEqual(runManager.startedRequests.last?.configurationName, "Worker")
        XCTAssertEqual(runManager.startedRequests.last?.displayCommand, "python worker.py")
        XCTAssertEqual(runManager.startedRequests.last?.executable, .shell(command: "python worker.py"))
        let state = try XCTUnwrap(viewModel.workspaceRunConsoleState(for: project.path))
        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.sessions.count, 1)
        XCTAssertEqual(state.selectedConfigurationID, "project::\(project.path)::worker")
        XCTAssertEqual(state.selectedSession?.configurationID, "project::\(project.path)::worker")
    }

    func testRemoteLogViewerConfigurationResolvesToSSHProcessExecutable() throws {
        let runManager = TestWorkspaceRunManager()
        let viewModel = makeViewModel(runManager: runManager)
        let project = makeProject(
            runConfigurations: [
                ProjectRunConfiguration(
                    id: "remote-log",
                    name: "远程日志",
                    kind: .remoteLogViewer,
                    remoteLogViewer: ProjectRunRemoteLogViewerConfiguration(
                        server: "192.168.0.131",
                        logPath: "/var/log/app.log",
                        user: "root",
                        port: 2222,
                        identityFile: "~/.ssh/id_rsa",
                        lines: 200,
                        follow: true,
                        strictHostKeyChecking: "accept-new",
                        allowPasswordPrompt: false
                    )
                )
            ]
        )
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)
        try viewModel.runSelectedWorkspaceConfiguration(in: project.path)

        let request = try XCTUnwrap(runManager.startedRequests.last)
        XCTAssertEqual(request.executable, .process(program: "/usr/bin/ssh", arguments: [
            "-l", "root",
            "-p", "2222",
            "-i", "~/.ssh/id_rsa",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "BatchMode=yes",
            "192.168.0.131",
            "tail -n 200 -F '/var/log/app.log'",
        ]))
        XCTAssertTrue(request.displayCommand.contains("/usr/bin/ssh"))
        XCTAssertTrue(request.displayCommand.contains("tail -n 200 -F"))
    }

    func testLegacyScriptsDecodeFlattensToCustomShellRunConfigurations() throws {
        let data = Data(
            """
            {
              "id": "project-legacy",
              "name": "Legacy",
              "path": "/tmp/legacy",
              "tags": [],
              "scripts": [
                {
                  "id": "remote-log",
                  "name": "Remote",
                  "start": "server=${server}\\nexec printf '%s\\\\n' \\"$server\\"",
                  "paramSchema": [
                    {"key":"server","label":"服务器","type":"text","required":true}
                  ],
                  "templateParams": {
                    "server": "root@192.168.0.131"
                  }
                }
              ],
              "worktrees": [],
              "mtime": 1,
              "size": 0,
              "checksum": "sum",
              "git_commits": 0,
              "git_last_commit": 0,
              "created": 1,
              "checked": 1
            }
            """.utf8
        )
        let project = try JSONDecoder().decode(Project.self, from: data)
        let configuration = try XCTUnwrap(project.runConfigurations.first)

        XCTAssertEqual(project.runConfigurations.count, 1)
        XCTAssertEqual(configuration.kind, .customShell)
        XCTAssertEqual(configuration.id, "remote-log")
        XCTAssertTrue(configuration.customShell?.command.contains("server='root@192.168.0.131'") ?? false)
        XCTAssertTrue(configuration.customShell?.command.contains("exec printf '%s\\n' \"$server\"") ?? false)
    }

    func testRunManagerEventsAppendOutputAndUpdateFinalState() throws {
        let runManager = TestWorkspaceRunManager()
        let viewModel = makeViewModel(runManager: runManager)
        let project = makeProject(
            runConfigurations: [
                ProjectRunConfiguration(
                    id: "dev",
                    name: "Dev",
                    kind: .customShell,
                    customShell: ProjectRunCustomShellConfiguration(command: "npm run dev")
                )
            ]
        )
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
        let project = makeProject(
            runConfigurations: [
                ProjectRunConfiguration(
                    id: "dev",
                    name: "Dev",
                    kind: .customShell,
                    customShell: ProjectRunCustomShellConfiguration(command: "npm run dev")
                )
            ]
        )
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
            runConfigurations: [
                ProjectRunConfiguration(
                    id: "dev",
                    name: "Dev",
                    kind: .customShell,
                    customShell: ProjectRunCustomShellConfiguration(command: "npm run dev")
                ),
                ProjectRunConfiguration(
                    id: "worker",
                    name: "Worker",
                    kind: .customShell,
                    customShell: ProjectRunCustomShellConfiguration(command: "python worker.py")
                )
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
        let project = makeProject(
            runConfigurations: [
                ProjectRunConfiguration(
                    id: "dev",
                    name: "Dev",
                    kind: .customShell,
                    customShell: ProjectRunCustomShellConfiguration(command: "npm run dev")
                )
            ]
        )
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

    private func makeProject(runConfigurations: [ProjectRunConfiguration]) -> Project {
        Project(
            id: "project-1",
            name: "DevHaven",
            path: "/tmp/devhaven",
            tags: [],
            runConfigurations: runConfigurations,
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
            command: request.displayCommand,
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
