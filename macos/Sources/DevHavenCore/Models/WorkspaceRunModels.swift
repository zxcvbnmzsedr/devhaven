import Foundation

public enum WorkspaceRunConfigurationSource: String, Equatable, Sendable {
    case projectScript
    case sharedScript

    public var displayTitle: String {
        switch self {
        case .projectScript:
            return "项目脚本"
        case .sharedScript:
            return "通用脚本"
        }
    }
}

public struct WorkspaceRunConfiguration: Identifiable, Equatable, Sendable {
    public var id: String
    public var projectPath: String
    public var rootProjectPath: String
    public var source: WorkspaceRunConfigurationSource
    public var sourceID: String
    public var name: String
    public var command: String
    public var workingDirectory: String
    public var isShared: Bool
    public var canRun: Bool
    public var disabledReason: String?

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
        self.id = id
        self.projectPath = projectPath
        self.rootProjectPath = rootProjectPath
        self.source = source
        self.sourceID = sourceID
        self.name = name
        self.command = command
        self.workingDirectory = workingDirectory
        self.isShared = isShared
        self.canRun = canRun
        self.disabledReason = disabledReason
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
}

public struct WorkspaceRunConsoleState: Equatable, Sendable {
    public var sessions: [WorkspaceRunSession]
    public var selectedSessionID: String?
    public var selectedConfigurationID: String?
    public var isVisible: Bool

    public init(
        sessions: [WorkspaceRunSession] = [],
        selectedSessionID: String? = nil,
        selectedConfigurationID: String? = nil,
        isVisible: Bool = false
    ) {
        self.sessions = sessions
        self.selectedSessionID = selectedSessionID
        self.selectedConfigurationID = selectedConfigurationID
        self.isVisible = isVisible
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

public struct WorkspaceRunStartRequest: Equatable, Sendable {
    public var sessionID: String
    public var configurationID: String
    public var configurationName: String
    public var configurationSource: WorkspaceRunConfigurationSource
    public var projectPath: String
    public var rootProjectPath: String
    public var command: String
    public var workingDirectory: String

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
        self.sessionID = sessionID
        self.configurationID = configurationID
        self.configurationName = configurationName
        self.configurationSource = configurationSource
        self.projectPath = projectPath
        self.rootProjectPath = rootProjectPath
        self.command = command
        self.workingDirectory = workingDirectory
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
