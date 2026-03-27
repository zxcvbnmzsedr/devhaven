import Foundation

public struct NativeGitCommandRunner: Sendable {
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

    public init(defaultTimeout: TimeInterval = 15) {
        self.defaultTimeout = defaultTimeout
    }

    public func run(
        arguments: [String],
        at repositoryPath: String,
        timeout: TimeInterval? = nil,
        environment: [String: String] = [:]
    ) throws -> Result {
        let result = try runAllowingFailure(arguments: arguments, at: repositoryPath, timeout: timeout, environment: environment)
        guard result.isSuccess else {
            throw WorkspaceGitCommandError.commandFailed(command: result.command.joined(separator: " "), message: result.errorMessage)
        }
        return result
    }

    public func runAllowingFailure(
        arguments: [String],
        at repositoryPath: String,
        timeout: TimeInterval? = nil,
        environment: [String: String] = [:]
    ) throws -> Result {
        let repositoryURL = URL(fileURLWithPath: repositoryPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: repositoryURL.path()) else {
            throw WorkspaceGitCommandError.invalidRepository("Git 仓库路径不存在：\(repositoryPath)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw WorkspaceGitCommandError.commandFailed(
                command: (["/usr/bin/git"] + arguments).joined(separator: " "),
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
            throw WorkspaceGitCommandError.timedOut(
                command: (["/usr/bin/git"] + arguments).joined(separator: " "),
                timeout: effectiveTimeout
            )
        }

        let stdout = String(data: stdoutBuffer.data(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrBuffer.data(), encoding: .utf8) ?? ""

        return Result(command: ["/usr/bin/git"] + arguments, stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}
