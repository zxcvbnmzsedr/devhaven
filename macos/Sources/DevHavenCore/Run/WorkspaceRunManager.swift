import Foundation
import Darwin

@MainActor
public final class WorkspaceRunManager: WorkspaceRunManaging {
    public var onEvent: (@MainActor @Sendable (WorkspaceRunManagerEvent) -> Void)?

    private let logStore: WorkspaceRunLogStore
    private var controllers = [String: ProcessController]()

    public init(logStore: WorkspaceRunLogStore) {
        self.logStore = logStore
        self.onEvent = nil
    }

    public func start(_ request: WorkspaceRunStartRequest) throws -> WorkspaceRunSession {
        let logFileURL = try logStore.createLogFile(scriptName: request.configurationName, sessionID: request.sessionID)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "exec \(request.command)"]
        process.currentDirectoryURL = URL(fileURLWithPath: request.workingDirectory, isDirectory: true)

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let controller = ProcessController(
            process: process,
            projectPath: request.projectPath,
            logFileURL: logFileURL,
            outputHandle: outputPipe.fileHandleForReading,
            errorHandle: errorPipe.fileHandleForReading
        )
        installReadHandler(for: outputPipe.fileHandleForReading, controller: controller)
        installReadHandler(for: errorPipe.fileHandleForReading, controller: controller)
        let logStore = self.logStore
        process.terminationHandler = { [weak self, weak controller] process in
            guard let self, let controller else { return }
            let remainingChunks = controller.drainRemainingOutput(using: logStore)
            let finalState: WorkspaceRunSessionState = controller.stopRequested
                ? .stopped
                : process.terminationStatus == 0 ? .completed(exitCode: process.terminationStatus) : .failed(exitCode: process.terminationStatus)
            Task { @MainActor in
                self.controllers.removeValue(forKey: controller.sessionID)
                for chunk in remainingChunks {
                    self.onEvent?(.output(projectPath: controller.projectPath, sessionID: controller.sessionID, chunk: chunk))
                }
                self.onEvent?(.stateChanged(projectPath: controller.projectPath, sessionID: controller.sessionID, state: finalState))
            }
        }

        try process.run()
        controller.sessionID = request.sessionID
        controller.processID = process.processIdentifier
        controllers[request.sessionID] = controller

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
            processID: process.processIdentifier,
            logFilePath: logFileURL.path,
            startedAt: Date(),
            endedAt: nil,
            displayBuffer: ""
        )
    }

    public func stop(sessionID: String) {
        guard let controller = controllers[sessionID], !controller.stopRequested else {
            return
        }
        controller.stopRequested = true
        onEvent?(.stateChanged(projectPath: controller.projectPath, sessionID: sessionID, state: .stopping))
        send(signal: SIGINT, to: controller)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard controller.process.isRunning else { return }
            send(signal: SIGTERM, to: controller)
            controller.process.terminate()

            try? await Task.sleep(for: .milliseconds(800))
            guard controller.process.isRunning else { return }
            send(signal: SIGKILL, to: controller)
            _ = Darwin.kill(controller.process.processIdentifier, SIGKILL)
        }
    }

    public func stopAll(projectPath: String) {
        controllers.values
            .filter { $0.projectPath == projectPath }
            .forEach { stop(sessionID: $0.sessionID) }
    }

    private func installReadHandler(for handle: FileHandle, controller: ProcessController) {
        let logStore = self.logStore
        handle.readabilityHandler = { [weak self, weak controller] handle in
            guard let self, let controller else { return }
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let chunk = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            guard !chunk.isEmpty else { return }
            try? logStore.append(chunk, to: controller.logFileURL)
            Task { @MainActor in
                self.onEvent?(.output(projectPath: controller.projectPath, sessionID: controller.sessionID, chunk: chunk))
            }
        }
    }

    private func send(signal: Int32, to controller: ProcessController) {
        let pid = controller.process.processIdentifier
        killDescendants(of: pid, signal: signal)
        _ = Darwin.kill(pid, signal)
    }

    private func killDescendants(of pid: Int32, signal: Int32) {
        for child in childProcessIDs(of: pid) {
            killDescendants(of: child, signal: signal)
            _ = Darwin.kill(child, signal)
        }
    }

    private func childProcessIDs(of pid: Int32) -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", String(pid)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return []
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output
                .split(whereSeparator: \.isNewline)
                .compactMap { Int32($0) }
        } catch {
            return []
        }
    }
}

private final class ProcessController: @unchecked Sendable {
    let process: Process
    let projectPath: String
    let logFileURL: URL
    let outputHandle: FileHandle
    let errorHandle: FileHandle
    var sessionID: String
    var processID: Int32?
    var stopRequested: Bool

    init(process: Process, projectPath: String, logFileURL: URL, outputHandle: FileHandle, errorHandle: FileHandle) {
        self.process = process
        self.projectPath = projectPath
        self.logFileURL = logFileURL
        self.outputHandle = outputHandle
        self.errorHandle = errorHandle
        self.sessionID = ""
        self.processID = nil
        self.stopRequested = false
    }

    func drainRemainingOutput(using logStore: WorkspaceRunLogStore) -> [String] {
        let handles = [outputHandle, errorHandle]
        var chunks = [String]()
        for handle in handles {
            handle.readabilityHandler = nil
            let data = handle.readDataToEndOfFile()
            guard !data.isEmpty else { continue }
            let chunk = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            guard !chunk.isEmpty else { continue }
            try? logStore.append(chunk, to: logFileURL)
            chunks.append(chunk)
        }
        return chunks
    }
}
