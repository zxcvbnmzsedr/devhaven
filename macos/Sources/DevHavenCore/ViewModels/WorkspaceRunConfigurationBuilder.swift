import Foundation

@MainActor
final class WorkspaceRunConfigurationBuilder {
    private let normalizePath: @MainActor (String) -> String
    private let projects: @MainActor () -> [Project]
    private let resolveDisplayProject: @MainActor (String) -> Project?

    init(
        normalizePath: @escaping @MainActor (String) -> String,
        projects: @escaping @MainActor () -> [Project],
        resolveDisplayProject: @escaping @MainActor (String) -> Project?
    ) {
        self.normalizePath = normalizePath
        self.projects = projects
        self.resolveDisplayProject = resolveDisplayProject
    }

    func configurations(
        for projectPath: String,
        sessions: [OpenWorkspaceSessionState]
    ) -> [WorkspaceRunConfiguration] {
        guard let session = sessions.first(where: { $0.projectPath == projectPath }),
              let project = resolveDisplayProject(projectPath)
        else {
            return []
        }

        return project.runConfigurations.map {
            configuration(
                from: $0,
                projectPath: projectPath,
                rootProjectPath: session.rootProjectPath
            )
        }
    }

    func ownerProjectPath(for projectPath: String) -> String? {
        let normalizedProjectPath = normalizePath(projectPath)
        if projects().contains(where: { normalizePath($0.path) == normalizedProjectPath }) {
            return projectPath
        }
        return projects().first(where: { project in
            project.worktrees.contains(where: { normalizePath($0.path) == normalizedProjectPath })
        })?.path
    }

    func configuration(
        from configuration: ProjectRunConfiguration,
        projectPath: String,
        rootProjectPath: String
    ) -> WorkspaceRunConfiguration {
        switch configuration.kind {
        case .customShell:
            let command = configuration.customShell?.command.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return WorkspaceRunConfiguration(
                id: workspaceProjectRunConfigurationID(projectPath: projectPath, configurationID: configuration.id),
                projectPath: projectPath,
                rootProjectPath: rootProjectPath,
                source: .projectRunConfiguration,
                sourceID: configuration.id,
                name: configuration.name,
                executable: .shell(command: command),
                displayCommand: command,
                workingDirectory: projectPath,
                isShared: false,
                canRun: !command.isEmpty,
                disabledReason: command.isEmpty ? "命令为空，请先完善自定义 Shell 配置。" : nil
            )
        case .remoteLogViewer:
            let resolution = resolveRemoteLogViewerExecutable(configuration.remoteLogViewer)
            return WorkspaceRunConfiguration(
                id: workspaceProjectRunConfigurationID(projectPath: projectPath, configurationID: configuration.id),
                projectPath: projectPath,
                rootProjectPath: rootProjectPath,
                source: .projectRunConfiguration,
                sourceID: configuration.id,
                name: configuration.name,
                executable: resolution.executable,
                displayCommand: resolution.displayCommand,
                workingDirectory: projectPath,
                isShared: false,
                canRun: resolution.canRun,
                disabledReason: resolution.disabledReason
            )
        }
    }

    private func workspaceProjectRunConfigurationID(projectPath: String, configurationID: String) -> String {
        "project::\(projectPath)::\(configurationID)"
    }

    private func resolveRemoteLogViewerExecutable(
        _ configuration: ProjectRunRemoteLogViewerConfiguration?
    ) -> RemoteLogViewerExecutableResolution {
        guard let configuration else {
            return RemoteLogViewerExecutableResolution(
                executable: .process(program: "/usr/bin/ssh", arguments: []),
                displayCommand: "/usr/bin/ssh",
                canRun: false,
                disabledReason: "远程日志配置缺失，请重新创建该运行配置。"
            )
        }

        let server = configuration.server.trimmingCharacters(in: .whitespacesAndNewlines)
        let logPath = configuration.logPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty, !logPath.isEmpty else {
            return RemoteLogViewerExecutableResolution(
                executable: .process(program: "/usr/bin/ssh", arguments: []),
                displayCommand: "/usr/bin/ssh",
                canRun: false,
                disabledReason: "远程日志配置缺少服务器或日志路径。"
            )
        }

        var args = [String]()
        let user = configuration.user?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !user.isEmpty {
            args.append(contentsOf: ["-l", user])
        }
        if let port = configuration.port, port > 0 {
            args.append(contentsOf: ["-p", String(port)])
        }
        let identityFile = configuration.identityFile?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !identityFile.isEmpty {
            args.append(contentsOf: ["-i", identityFile])
        }
        let strictHostKeyChecking = configuration.strictHostKeyChecking?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !strictHostKeyChecking.isEmpty {
            args.append(contentsOf: ["-o", "StrictHostKeyChecking=\(strictHostKeyChecking)"])
        }
        if !configuration.allowPasswordPrompt {
            args.append(contentsOf: ["-o", "BatchMode=yes"])
        }

        let lines = max(1, configuration.lines ?? 200)
        let remoteCommand = remoteTailCommand(logPath: logPath, lines: lines, follow: configuration.follow)
        args.append(server)
        args.append(remoteCommand)

        return RemoteLogViewerExecutableResolution(
            executable: .process(program: "/usr/bin/ssh", arguments: args),
            displayCommand: processDisplayCommand(program: "/usr/bin/ssh", arguments: args),
            canRun: true,
            disabledReason: nil
        )
    }

    private func remoteTailCommand(logPath: String, lines: Int, follow: Bool) -> String {
        var components = ["tail", "-n", String(lines)]
        if follow {
            components.append("-F")
        }
        components.append(shellQuote(logPath))
        return components.joined(separator: " ")
    }

    private func processDisplayCommand(program: String, arguments: [String]) -> String {
        ([program] + arguments.map(shellQuote)).joined(separator: " ")
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

private struct RemoteLogViewerExecutableResolution {
    var executable: WorkspaceRunExecutable
    var displayCommand: String
    var canRun: Bool
    var disabledReason: String?
}
