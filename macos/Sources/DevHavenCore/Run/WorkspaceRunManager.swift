import Foundation
import Darwin

@MainActor
public final class WorkspaceRunManager: WorkspaceRunManaging {
    public var onEvent: (@MainActor @Sendable (WorkspaceRunManagerEvent) -> Void)?

    private let logStore: WorkspaceRunLogStore
    private let outputEventFlushDelayNanoseconds: UInt64
    private var controllers = [String: ProcessController]()
    private lazy var outputEventBatcher = OutputEventBatcher(
        flushDelayNanoseconds: outputEventFlushDelayNanoseconds
    ) { [weak self] projectPath, sessionID, chunk in
        guard let self else {
            return
        }
        Task { @MainActor in
            self.emitOutputNow(projectPath: projectPath, sessionID: sessionID, chunk: chunk)
        }
    }

    public init(
        logStore: WorkspaceRunLogStore,
        outputEventFlushDelayNanoseconds: UInt64 = 50_000_000
    ) {
        self.logStore = logStore
        self.outputEventFlushDelayNanoseconds = outputEventFlushDelayNanoseconds
        self.onEvent = nil
    }

    public func start(_ request: WorkspaceRunStartRequest) throws -> WorkspaceRunSession {
        let logFileURL = try logStore.createLogFile(scriptName: request.configurationName, sessionID: request.sessionID)
        let outputEventBatcher = self.outputEventBatcher
        let process = Process()
        switch request.executable {
        case let .shell(command):
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
        case let .process(program, arguments):
            process.executableURL = URL(fileURLWithPath: program)
            process.arguments = arguments
        }
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
        controller.sessionID = request.sessionID
        let commandHeader = commandLogHeader(for: request)
        try? logStore.append(commandHeader, to: logFileURL)
        outputEventBatcher.append(
            chunk: commandHeader,
            projectPath: request.projectPath,
            sessionID: request.sessionID
        )
        installReadHandler(for: outputPipe.fileHandleForReading, controller: controller)
        installReadHandler(for: errorPipe.fileHandleForReading, controller: controller)
        let logStore = self.logStore
        process.terminationHandler = { [weak self, weak controller, outputEventBatcher] process in
            guard let self, let controller else { return }
            let pendingChunk = outputEventBatcher.drainPendingChunk(for: controller.sessionID)
            let remainingChunks = controller.drainRemainingOutput(using: logStore)
            let finalOutput = ([pendingChunk].compactMap { $0 } + remainingChunks).joined()
            logStore.closeLogFile(at: controller.logFileURL)
            let finalState: WorkspaceRunSessionState = controller.stopRequested
                ? .stopped
                : process.terminationStatus == 0 ? .completed(exitCode: process.terminationStatus) : .failed(exitCode: process.terminationStatus)
            Task { @MainActor in
                self.controllers.removeValue(forKey: controller.sessionID)
                if !finalOutput.isEmpty {
                    self.emitOutputNow(projectPath: controller.projectPath, sessionID: controller.sessionID, chunk: finalOutput)
                }
                self.onEvent?(.stateChanged(projectPath: controller.projectPath, sessionID: controller.sessionID, state: finalState))
            }
        }

        try process.run()
        controller.processID = process.processIdentifier
        controllers[request.sessionID] = controller

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
        let outputEventBatcher = self.outputEventBatcher
        handle.readabilityHandler = { [weak controller, outputEventBatcher] handle in
            guard let controller else { return }
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let chunk = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            guard !chunk.isEmpty else { return }
            try? logStore.append(chunk, to: controller.logFileURL)
            outputEventBatcher.append(
                chunk: chunk,
                projectPath: controller.projectPath,
                sessionID: controller.sessionID
            )
        }
    }

    private func emitOutputNow(projectPath: String, sessionID: String, chunk: String) {
        guard !chunk.isEmpty else {
            return
        }
        onEvent?(.output(projectPath: projectPath, sessionID: sessionID, chunk: chunk))
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

    private func commandLogHeader(for request: WorkspaceRunStartRequest) -> String {
        """
        [DevHaven] 执行目录：\(request.workingDirectory)
        [DevHaven] 执行命令：
        \(request.displayCommand)

        """
    }
}

private final class OutputEventBatcher: @unchecked Sendable {
    private let flushDelayNanoseconds: UInt64
    private let onFlush: @Sendable (String, String, String) -> Void
    private let queue = DispatchQueue(label: "DevHavenCore.WorkspaceRunManager.OutputEventBatcher")

    private var pendingChunksBySessionID = [String: String]()
    private var projectPathsBySessionID = [String: String]()
    private var scheduledSessionIDs = Set<String>()

    init(
        flushDelayNanoseconds: UInt64,
        onFlush: @escaping @Sendable (String, String, String) -> Void
    ) {
        self.flushDelayNanoseconds = flushDelayNanoseconds
        self.onFlush = onFlush
    }

    func append(chunk: String, projectPath: String, sessionID: String) {
        guard !chunk.isEmpty else {
            return
        }
        queue.async {
            self.pendingChunksBySessionID[sessionID, default: ""].append(chunk)
            self.projectPathsBySessionID[sessionID] = projectPath
            guard self.scheduledSessionIDs.insert(sessionID).inserted else {
                return
            }
            let delay = DispatchTimeInterval.nanoseconds(Int(clamping: self.flushDelayNanoseconds))
            self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.flushLocked(sessionID: sessionID)
            }
        }
    }

    func drainPendingChunk(for sessionID: String) -> String? {
        queue.sync {
            scheduledSessionIDs.remove(sessionID)
            projectPathsBySessionID.removeValue(forKey: sessionID)
            return pendingChunksBySessionID.removeValue(forKey: sessionID)
        }
    }

    private func flushLocked(sessionID: String) {
        scheduledSessionIDs.remove(sessionID)
        guard let projectPath = projectPathsBySessionID.removeValue(forKey: sessionID),
              let chunk = pendingChunksBySessionID.removeValue(forKey: sessionID),
              !chunk.isEmpty
        else {
            return
        }
        onFlush(projectPath, sessionID, chunk)
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
