import Foundation

public struct NativeWorktreeEnvironmentService: NativeWorktreeEnvironmentServicing {
    public init() {}

    public func prepareEnvironment(
        mainRepositoryPath: String,
        worktreePath: String,
        workspaceName: String
    ) -> NativeWorktreeEnvironmentResult {
        var warnings = [String]()
        if let error = copySetupDirectory(mainRepositoryPath: mainRepositoryPath, worktreePath: worktreePath) {
            warnings.append(error)
        }

        let commandResult = runSetupCommandsIfNeeded(
            mainRepositoryPath: mainRepositoryPath,
            worktreePath: worktreePath,
            workspaceName: workspaceName
        )
        if let error = commandResult.warning {
            warnings.append(error)
        }

        let warning = warnings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return NativeWorktreeEnvironmentResult(
            warning: warning.isEmpty ? nil : warning,
            executedCommands: commandResult.executedCommands,
            failedCommand: commandResult.failedCommand,
            latestOutputLines: commandResult.latestOutputLines
        )
    }

    private func copySetupDirectory(mainRepositoryPath: String, worktreePath: String) -> String? {
        let sourceURL = URL(fileURLWithPath: mainRepositoryPath).appending(path: ".devhaven", directoryHint: .isDirectory)
        let targetURL = URL(fileURLWithPath: worktreePath).appending(path: ".devhaven", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return nil
        }
        guard !FileManager.default.fileExists(atPath: targetURL.path) else {
            return nil
        }

        do {
            try copyDirectoryRecursively(from: sourceURL, to: targetURL)
            return nil
        } catch {
            return "复制 .devhaven 目录失败：\(error.localizedDescription)"
        }
    }

    private func copyDirectoryRecursively(from sourceURL: URL, to targetURL: URL) throws {
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        for entry in try FileManager.default.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let destinationURL = targetURL.appending(path: entry.lastPathComponent)
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isDirectory == true {
                try copyDirectoryRecursively(from: entry, to: destinationURL)
                continue
            }
            if values.isSymbolicLink == true {
                let metadata = try FileManager.default.attributesOfItem(atPath: entry.path)
                if metadata[.type] as? FileAttributeType == .typeDirectory {
                    continue
                }
            }
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: entry, to: destinationURL)
        }
    }

    private func runSetupCommandsIfNeeded(
        mainRepositoryPath: String,
        worktreePath: String,
        workspaceName: String
    ) -> NativeWorktreeEnvironmentResult {
        let configURL = URL(fileURLWithPath: mainRepositoryPath)
            .appending(path: ".devhaven", directoryHint: .isDirectory)
            .appending(path: "config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return NativeWorktreeEnvironmentResult()
        }

        let commands: [String]
        do {
            commands = try loadSetupCommands(configURL: configURL)
        } catch {
            return NativeWorktreeEnvironmentResult(warning: error.localizedDescription)
        }
        guard !commands.isEmpty else {
            return NativeWorktreeEnvironmentResult()
        }

        var executedCommands = [String]()
        var latestOutputLines = [String]()
        for command in commands {
            executedCommands.append(command)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = URL(fileURLWithPath: worktreePath, isDirectory: true)
            process.environment = ProcessInfo.processInfo.environment.merging([
                "DEVHAVEN_WORKSPACE_NAME": workspaceName,
                "DEVHAVEN_ROOT_PATH": mainRepositoryPath,
            ]) { _, new in new }

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
            } catch {
                return NativeWorktreeEnvironmentResult(
                    warning: "执行 setup 命令失败（\(command)）：\(error.localizedDescription)",
                    executedCommands: executedCommands,
                    failedCommand: command,
                    latestOutputLines: latestOutputLines
                )
            }
            process.waitUntilExit()

            let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            latestOutputLines = summarizeOutputLines(stdout: stdoutText, stderr: stderrText)

            guard process.terminationStatus == 0 else {
                return NativeWorktreeEnvironmentResult(
                    warning: "环境初始化命令执行失败：\n$ \(command)\n退出码：\(process.terminationStatus)",
                    executedCommands: executedCommands,
                    failedCommand: command,
                    latestOutputLines: latestOutputLines.isEmpty ? ["命令无输出"] : latestOutputLines
                )
            }
        }

        return NativeWorktreeEnvironmentResult(
            executedCommands: executedCommands,
            latestOutputLines: latestOutputLines
        )
    }

    private func summarizeOutputLines(stdout: String, stderr: String, limit: Int = 5) -> [String] {
        let stdoutLines = stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "stdout | \($0)" }
        let stderrLines = stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "stderr | \($0)" }
        return Array((stdoutLines + stderrLines).suffix(limit))
    }

    private func loadSetupCommands(configURL: URL) throws -> [String] {
        struct SetupConfig: Decodable {
            var setup: [String] = []
        }

        let data = try Data(contentsOf: configURL)
        let parsed = try JSONDecoder().decode(SetupConfig.self, from: data)
        return parsed.setup
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
