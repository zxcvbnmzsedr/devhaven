import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceRunConfigurationBuilderTests: XCTestCase {
    func testCustomShellConfigurationTrimsCommandAndBuildsStableID() {
        let builder = makeBuilder()

        let configuration = builder.configuration(
            from: ProjectRunConfiguration(
                id: "dev",
                name: "Dev",
                kind: .customShell,
                customShell: ProjectRunCustomShellConfiguration(command: " npm run dev \n")
            ),
            projectPath: "/repo/app",
            rootProjectPath: "/repo"
        )

        XCTAssertEqual(configuration.id, "project::/repo/app::dev")
        XCTAssertEqual(configuration.projectPath, "/repo/app")
        XCTAssertEqual(configuration.rootProjectPath, "/repo")
        XCTAssertEqual(configuration.executable, .shell(command: "npm run dev"))
        XCTAssertEqual(configuration.displayCommand, "npm run dev")
        XCTAssertEqual(configuration.workingDirectory, "/repo/app")
        XCTAssertTrue(configuration.canRun)
        XCTAssertNil(configuration.disabledReason)
    }

    func testCustomShellConfigurationDisablesEmptyCommand() {
        let builder = makeBuilder()

        let configuration = builder.configuration(
            from: ProjectRunConfiguration(
                id: "empty",
                name: "Empty",
                kind: .customShell,
                customShell: ProjectRunCustomShellConfiguration(command: " \n ")
            ),
            projectPath: "/repo",
            rootProjectPath: "/repo"
        )

        XCTAssertEqual(configuration.executable, .shell(command: ""))
        XCTAssertFalse(configuration.canRun)
        XCTAssertEqual(configuration.disabledReason, "命令为空，请先完善自定义 Shell 配置。")
    }

    func testRemoteLogViewerBuildsSSHExecutableAndDisplayCommand() {
        let builder = makeBuilder()

        let configuration = builder.configuration(
            from: ProjectRunConfiguration(
                id: "prod-log",
                name: "Prod Log",
                kind: .remoteLogViewer,
                remoteLogViewer: ProjectRunRemoteLogViewerConfiguration(
                    server: " prod.example.com ",
                    logPath: " /var/log/app's.log ",
                    user: " deploy ",
                    port: 2202,
                    identityFile: " ~/.ssh/prod ",
                    lines: 50,
                    follow: true,
                    strictHostKeyChecking: "accept-new",
                    allowPasswordPrompt: false
                )
            ),
            projectPath: "/repo",
            rootProjectPath: "/repo"
        )

        XCTAssertEqual(
            configuration.executable,
            .process(
                program: "/usr/bin/ssh",
                arguments: [
                    "-l", "deploy",
                    "-p", "2202",
                    "-i", "~/.ssh/prod",
                    "-o", "StrictHostKeyChecking=accept-new",
                    "-o", "BatchMode=yes",
                    "prod.example.com",
                    "tail -n 50 -F '/var/log/app'\\''s.log'"
                ]
            )
        )
        XCTAssertEqual(
            configuration.displayCommand,
            "/usr/bin/ssh '-l' 'deploy' '-p' '2202' '-i' '~/.ssh/prod' '-o' 'StrictHostKeyChecking=accept-new' '-o' 'BatchMode=yes' 'prod.example.com' 'tail -n 50 -F '\\''/var/log/app'\\''\\'\\'''\\''s.log'\\'''"
        )
        XCTAssertTrue(configuration.canRun)
        XCTAssertNil(configuration.disabledReason)
    }

    func testRemoteLogViewerDisablesMissingServerOrLogPath() {
        let builder = makeBuilder()

        let configuration = builder.configuration(
            from: ProjectRunConfiguration(
                id: "bad-log",
                name: "Bad Log",
                kind: .remoteLogViewer,
                remoteLogViewer: ProjectRunRemoteLogViewerConfiguration(
                    server: " ",
                    logPath: "/var/log/app.log"
                )
            ),
            projectPath: "/repo",
            rootProjectPath: "/repo"
        )

        XCTAssertEqual(configuration.executable, .process(program: "/usr/bin/ssh", arguments: []))
        XCTAssertFalse(configuration.canRun)
        XCTAssertEqual(configuration.disabledReason, "远程日志配置缺少服务器或日志路径。")
    }

    func testConfigurationsUseResolvedDisplayProjectRunConfigurationsAndSessionRoot() {
        let project = makeProject(
            path: "/repo/app",
            runConfigurations: [ProjectRunConfiguration(id: "dev", name: "Dev", command: "npm run dev")]
        )
        let session = OpenWorkspaceSessionState(
            projectPath: "/repo/app",
            rootProjectPath: "/repo",
            controller: GhosttyWorkspaceController(projectPath: "/repo/app")
        )
        let builder = makeBuilder(projects: [project], resolvedProjects: ["/repo/app": project])

        let configurations = builder.configurations(for: "/repo/app", sessions: [session])

        XCTAssertEqual(configurations.map(\.id), ["project::/repo/app::dev"])
        XCTAssertEqual(configurations.first?.rootProjectPath, "/repo")
    }

    func testOwnerProjectPathResolvesDirectProjectAndChildWorktree() {
        let project = makeProject(
            path: "/repo",
            worktrees: [
                ProjectWorktree(
                    id: "worktree",
                    name: "Feature",
                    path: "/repo-feature",
                    branch: "feature/test",
                    inheritConfig: true,
                    created: 1
                )
            ]
        )
        let builder = makeBuilder(projects: [project])

        XCTAssertEqual(builder.ownerProjectPath(for: "/repo/"), "/repo/")
        XCTAssertEqual(builder.ownerProjectPath(for: "/repo-feature/"), "/repo")
        XCTAssertNil(builder.ownerProjectPath(for: "/missing"))
    }

    private func makeBuilder(
        projects: [Project] = [],
        resolvedProjects: [String: Project] = [:]
    ) -> WorkspaceRunConfigurationBuilder {
        WorkspaceRunConfigurationBuilder(
            normalizePath: normalizeRunConfigurationBuilderTestPath,
            projects: { projects },
            resolveDisplayProject: { resolvedProjects[$0] }
        )
    }

    private func makeProject(
        path: String,
        worktrees: [ProjectWorktree] = [],
        runConfigurations: [ProjectRunConfiguration] = []
    ) -> Project {
        Project(
            id: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            path: path,
            tags: [],
            runConfigurations: runConfigurations,
            worktrees: worktrees,
            mtime: 1,
            size: 0,
            checksum: path,
            isGitRepository: true,
            gitCommits: 1,
            gitLastCommit: 1,
            created: 1,
            checked: 1
        )
    }
}

private func normalizeRunConfigurationBuilderTestPath(_ path: String) -> String {
    var normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\", with: "/")
    while normalized.count > 1 && normalized.hasSuffix("/") {
        normalized.removeLast()
    }
    return normalized
}
