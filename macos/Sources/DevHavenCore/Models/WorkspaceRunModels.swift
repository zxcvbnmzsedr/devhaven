import Foundation

public enum WorkspaceRunConfigurationSource: String, Equatable, Sendable {
    case projectRunConfiguration

    public var displayTitle: String {
        switch self {
        case .projectRunConfiguration:
            return "项目运行配置"
        }
    }
}

public enum WorkspaceRunExecutable: Equatable, Sendable {
    case shell(command: String)
    case process(program: String, arguments: [String])
}

public struct WorkspaceRunConfiguration: Identifiable, Equatable, Sendable {
    public var id: String
    public var projectPath: String
    public var rootProjectPath: String
    public var source: WorkspaceRunConfigurationSource
    public var sourceID: String
    public var name: String
    public var executable: WorkspaceRunExecutable
    public var displayCommand: String
    public var workingDirectory: String
    public var isShared: Bool
    public var canRun: Bool
    public var disabledReason: String?

    public var command: String {
        displayCommand
    }

    public init(
        id: String,
        projectPath: String,
        rootProjectPath: String,
        source: WorkspaceRunConfigurationSource,
        sourceID: String,
        name: String,
        executable: WorkspaceRunExecutable,
        displayCommand: String,
        workingDirectory: String,
        isShared: Bool,
        canRun: Bool = true,
        disabledReason: String? = nil
    ) {
        self.id = id
        self.projectPath = projectPath
        self.rootProjectPath = rootProjectPath
        self.source = source
        self.sourceID = sourceID
        self.name = name
        self.executable = executable
        self.displayCommand = displayCommand
        self.workingDirectory = workingDirectory
        self.isShared = isShared
        self.canRun = canRun
        self.disabledReason = disabledReason
    }

    public init(
        id: String,
        projectPath: String,
        rootProjectPath: String,
        source: WorkspaceRunConfigurationSource,
        sourceID: String,
        name: String,
        command: String,
        workingDirectory: String,
        isShared: Bool,
        canRun: Bool = true,
        disabledReason: String? = nil
    ) {
        self.init(
            id: id,
            projectPath: projectPath,
            rootProjectPath: rootProjectPath,
            source: source,
            sourceID: sourceID,
            name: name,
            executable: .shell(command: command),
            displayCommand: command,
            workingDirectory: workingDirectory,
            isShared: isShared,
            canRun: canRun,
            disabledReason: disabledReason
        )
    }
}

public enum WorkspaceRunSessionState: Equatable, Sendable {
    case starting
    case running
    case stopping
    case stopped
    case completed(exitCode: Int32)
    case failed(exitCode: Int32)

    public var isActive: Bool {
        switch self {
        case .starting, .running, .stopping:
            return true
        case .stopped, .completed, .failed:
            return false
        }
    }
}

public struct WorkspaceRunSession: Identifiable, Equatable, Sendable {
    static let maxDisplayBufferUTF8Bytes = 128 * 1024
    static let trimmedDisplayBufferUTF8Bytes = 96 * 1024
    static let displayBufferTruncationNotice = "[DevHaven] 控制台输出过长，已仅保留最近内容。完整日志请点“打开日志”。\n\n"

    public var id: String
    public var configurationID: String
    public var configurationName: String
    public var configurationSource: WorkspaceRunConfigurationSource
    public var projectPath: String
    public var rootProjectPath: String
    public var command: String
    public var workingDirectory: String
    public var state: WorkspaceRunSessionState
    public var processID: Int32?
    public var logFilePath: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var displayBuffer: String

    public init(
        id: String,
        configurationID: String,
        configurationName: String,
        configurationSource: WorkspaceRunConfigurationSource,
        projectPath: String,
        rootProjectPath: String,
        command: String,
        workingDirectory: String,
        state: WorkspaceRunSessionState,
        processID: Int32? = nil,
        logFilePath: String? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        displayBuffer: String = ""
    ) {
        self.id = id
        self.configurationID = configurationID
        self.configurationName = configurationName
        self.configurationSource = configurationSource
        self.projectPath = projectPath
        self.rootProjectPath = rootProjectPath
        self.command = command
        self.workingDirectory = workingDirectory
        self.state = state
        self.processID = processID
        self.logFilePath = logFilePath
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.displayBuffer = displayBuffer
    }

    mutating func appendDisplayChunk(_ chunk: String) {
        guard !chunk.isEmpty else {
            return
        }
        displayBuffer = Self.appendingDisplayChunk(chunk, to: displayBuffer)
    }

    static func appendingDisplayChunk(_ chunk: String, to existing: String) -> String {
        guard !chunk.isEmpty else {
            return existing
        }
        let combined = existing + chunk
        guard combined.utf8.count > maxDisplayBufferUTF8Bytes else {
            return combined
        }

        let contentWithoutNotice: String
        if combined.hasPrefix(displayBufferTruncationNotice) {
            contentWithoutNotice = String(combined.dropFirst(displayBufferTruncationNotice.count))
        } else {
            contentWithoutNotice = combined
        }

        var trimmed = utf8Suffix(
            of: contentWithoutNotice,
            byteLimit: trimmedDisplayBufferUTF8Bytes
        )
        if let firstNewline = trimmed.firstIndex(of: "\n"),
           firstNewline < trimmed.index(before: trimmed.endIndex)
        {
            trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
        }
        return displayBufferTruncationNotice + trimmed
    }

    private static func utf8Suffix(of text: String, byteLimit: Int) -> String {
        guard byteLimit > 0, text.utf8.count > byteLimit else {
            return text
        }
        var collectedBytes = 0
        var startIndex = text.endIndex
        while startIndex > text.startIndex {
            let previousIndex = text.index(before: startIndex)
            let scalarBytes = String(text[previousIndex]).utf8.count
            if collectedBytes + scalarBytes > byteLimit {
                break
            }
            collectedBytes += scalarBytes
            startIndex = previousIndex
        }
        return String(text[startIndex...])
    }
}

public struct WorkspaceRunConsoleState: Equatable, Sendable {
    public static let defaultPanelHeight: Double = 220

    public var sessions: [WorkspaceRunSession]
    public var selectedSessionID: String?
    public var selectedConfigurationID: String?
    public var isVisible: Bool
    public var panelHeight: Double

    public init(
        sessions: [WorkspaceRunSession] = [],
        selectedSessionID: String? = nil,
        selectedConfigurationID: String? = nil,
        isVisible: Bool = false,
        panelHeight: Double = WorkspaceRunConsoleState.defaultPanelHeight
    ) {
        self.sessions = sessions
        self.selectedSessionID = selectedSessionID
        self.selectedConfigurationID = selectedConfigurationID
        self.isVisible = isVisible
        self.panelHeight = panelHeight
    }

    public var selectedSession: WorkspaceRunSession? {
        if let selectedSessionID,
           let session = sessions.first(where: { $0.id == selectedSessionID }) {
            return session
        }
        return sessions.max(by: { $0.startedAt < $1.startedAt })
    }

    public var runningSessionCount: Int {
        sessions.reduce(into: 0) { count, session in
            if session.state.isActive {
                count += 1
            }
        }
    }
}

public struct WorkspaceRunToolbarState: Equatable, Sendable {
    public var configurations: [WorkspaceRunConfiguration]
    public var selectedConfigurationID: String?
    public var canRun: Bool
    public var canStop: Bool
    public var hasSessions: Bool
    public var isLogsVisible: Bool

    public init(
        configurations: [WorkspaceRunConfiguration] = [],
        selectedConfigurationID: String? = nil,
        canRun: Bool = false,
        canStop: Bool = false,
        hasSessions: Bool = false,
        isLogsVisible: Bool = false
    ) {
        self.configurations = configurations
        self.selectedConfigurationID = selectedConfigurationID
        self.canRun = canRun
        self.canStop = canStop
        self.hasSessions = hasSessions
        self.isLogsVisible = isLogsVisible
    }
}

public struct WorkspaceRunStartRequest: Equatable, Sendable {
    public var sessionID: String
    public var configurationID: String
    public var configurationName: String
    public var configurationSource: WorkspaceRunConfigurationSource
    public var projectPath: String
    public var rootProjectPath: String
    public var executable: WorkspaceRunExecutable
    public var displayCommand: String
    public var workingDirectory: String

    public var command: String {
        displayCommand
    }

    public init(
        sessionID: String,
        configurationID: String,
        configurationName: String,
        configurationSource: WorkspaceRunConfigurationSource,
        projectPath: String,
        rootProjectPath: String,
        executable: WorkspaceRunExecutable,
        displayCommand: String,
        workingDirectory: String
    ) {
        self.sessionID = sessionID
        self.configurationID = configurationID
        self.configurationName = configurationName
        self.configurationSource = configurationSource
        self.projectPath = projectPath
        self.rootProjectPath = rootProjectPath
        self.executable = executable
        self.displayCommand = displayCommand
        self.workingDirectory = workingDirectory
    }

    public init(
        sessionID: String,
        configurationID: String,
        configurationName: String,
        configurationSource: WorkspaceRunConfigurationSource,
        projectPath: String,
        rootProjectPath: String,
        command: String,
        workingDirectory: String
    ) {
        self.init(
            sessionID: sessionID,
            configurationID: configurationID,
            configurationName: configurationName,
            configurationSource: configurationSource,
            projectPath: projectPath,
            rootProjectPath: rootProjectPath,
            executable: .shell(command: command),
            displayCommand: command,
            workingDirectory: workingDirectory
        )
    }
}

public enum WorkspaceRunManagerEvent: Equatable, Sendable {
    case output(projectPath: String, sessionID: String, chunk: String)
    case stateChanged(projectPath: String, sessionID: String, state: WorkspaceRunSessionState)
}

@MainActor
public protocol WorkspaceRunManaging: AnyObject {
    var onEvent: (@MainActor @Sendable (WorkspaceRunManagerEvent) -> Void)? { get set }

    func start(_ request: WorkspaceRunStartRequest) throws -> WorkspaceRunSession
    func stop(sessionID: String)
    func stopAll(projectPath: String)
}
