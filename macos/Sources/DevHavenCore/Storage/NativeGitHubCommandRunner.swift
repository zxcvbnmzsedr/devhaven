import Foundation

public struct NativeGitHubCommandRunner: Sendable {
    typealias Execution = @Sendable (_ arguments: [String], _ repositoryPath: String, _ timeout: TimeInterval?, _ environment: [String: String]) throws -> Result
    private static let defaultSearchPaths = [
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]
    private static let fallbackSearchPaths = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/opt/homebrew/opt/gh/bin",
        "/usr/local/bin",
        "/usr/local/sbin",
        "/usr/local/opt/gh/bin",
    ]

    private final class PipeBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()

        func append(_ chunk: Data) {
            lock.lock()
            storage.append(chunk)
            lock.unlock()
        }

        func data() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    public struct Result: Equatable, Sendable {
        public var command: [String]
        public var stdout: String
        public var stderr: String
        public var exitCode: Int32

        public init(command: [String], stdout: String, stderr: String, exitCode: Int32) {
            self.command = command
            self.stdout = stdout
            self.stderr = stderr
            self.exitCode = exitCode
        }

        public var isSuccess: Bool {
            exitCode == 0
        }

        public var errorMessage: String {
            let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedStderr.isEmpty {
                return trimmedStderr
            }
            let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedStdout.isEmpty ? "未知错误" : trimmedStdout
        }
    }

    public var defaultTimeout: TimeInterval
    private let executeOverride: Execution?

    public init(defaultTimeout: TimeInterval = 30) {
        self.defaultTimeout = defaultTimeout
        self.executeOverride = nil
    }

    init(
        defaultTimeout: TimeInterval = 30,
        executeOverride: Execution?
    ) {
        self.defaultTimeout = defaultTimeout
        self.executeOverride = executeOverride
    }

    public func run(
        arguments: [String],
        at repositoryPath: String,
        timeout: TimeInterval? = nil,
        environment: [String: String] = [:]
    ) throws -> Result {
        let result = try runAllowingFailure(
            arguments: arguments,
            at: repositoryPath,
            timeout: timeout,
            environment: environment
        )
        guard result.isSuccess else {
            throw mapFailure(result, timeout: timeout ?? defaultTimeout)
        }
        return result
    }

    public func runAllowingFailure(
        arguments: [String],
        at repositoryPath: String,
        timeout: TimeInterval? = nil,
        environment: [String: String] = [:]
    ) throws -> Result {
        if let executeOverride {
            return try executeOverride(arguments, repositoryPath, timeout, environment)
        }

        let repositoryURL = URL(fileURLWithPath: repositoryPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: repositoryURL.path) else {
            throw WorkspaceGitHubCommandError.invalidRepository("仓库路径不存在：\(repositoryPath)")
        }

        let process = Process()

        var mergedEnvironment = ProcessInfo.processInfo.environment
        mergedEnvironment["GH_PAGER"] = "cat"
        mergedEnvironment["PAGER"] = "cat"
        mergedEnvironment["NO_COLOR"] = "1"
        mergedEnvironment["CLICOLOR"] = "0"
        mergedEnvironment["GH_NO_UPDATE_NOTIFIER"] = "1"
        mergedEnvironment["GH_PROMPT_DISABLED"] = "1"
        for (key, value) in environment {
            mergedEnvironment[key] = value
        }
        mergedEnvironment["PATH"] = Self.normalizedSearchPath(environment: mergedEnvironment)

        let executablePath = Self.resolveExecutablePath(searchPath: mergedEnvironment["PATH"] ?? "")
        let commandPrefix: [String]
        if let executablePath {
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            commandPrefix = [executablePath]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["gh"] + arguments
            commandPrefix = ["/usr/bin/env", "gh"]
        }
        process.currentDirectoryURL = repositoryURL
        process.environment = mergedEnvironment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw WorkspaceGitHubCommandError.commandFailed(
                command: (commandPrefix + arguments).joined(separator: " "),
                message: error.localizedDescription
            )
        }

        let stdoutBuffer = PipeBuffer()
        let stderrBuffer = PipeBuffer()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            stdoutBuffer.append(chunk)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            stderrBuffer.append(chunk)
        }

        let effectiveTimeout = timeout ?? defaultTimeout
        var didTimeout = false
        if effectiveTimeout > 0 {
            let deadline = Date().addingTimeInterval(effectiveTimeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                didTimeout = true
                process.terminate()
            }
        }
        process.waitUntilExit()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

        if didTimeout {
            throw WorkspaceGitHubCommandError.timedOut(
                command: (commandPrefix + arguments).joined(separator: " "),
                timeout: effectiveTimeout
            )
        }

        let stdout = String(data: stdoutBuffer.data(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrBuffer.data(), encoding: .utf8) ?? ""
        return Result(
            command: commandPrefix + arguments,
            stdout: stdout,
            stderr: stderr,
            exitCode: process.terminationStatus
        )
    }

    static func normalizedSearchPath(environment: [String: String]) -> String {
        let rawEntries = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let candidateEntries = rawEntries + defaultSearchPaths + fallbackSearchPaths
        var seen = Set<String>()
        var ordered = [String]()
        for entry in candidateEntries {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }
            seen.insert(trimmed)
            ordered.append(trimmed)
        }
        return ordered.joined(separator: ":")
    }

    static func resolveExecutablePath(
        searchPath: String,
        isExecutableFile: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        for directory in searchPath.split(separator: ":") {
            let path = String(directory)
            guard !path.isEmpty else {
                continue
            }
            let candidate = URL(fileURLWithPath: path, isDirectory: true)
                .appending(path: "gh", directoryHint: .notDirectory)
                .path
            if isExecutableFile(candidate) {
                return candidate
            }
        }
        return nil
    }

    private func mapFailure(_ result: Result, timeout: TimeInterval) -> WorkspaceGitHubCommandError {
        let command = result.command.joined(separator: " ")
        let message = result.errorMessage
        let normalized = message.lowercased()
        if normalized.contains("authenticate") || normalized.contains("not logged into") {
            return .authRequired("GitHub CLI 未登录，请先执行 gh auth login")
        }
        return .commandFailed(command: command, message: message)
    }
}
