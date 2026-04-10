import Foundation

public enum WorkspaceCLICommandKind: String, Codable, Equatable, Sendable, CaseIterable {
    case capabilities = "capabilities"
    case status = "status"
    case workspaceList = "workspace.list"
    case workspaceEnter = "workspace.enter"
    case workspaceActivate = "workspace.activate"
    case workspaceExit = "workspace.exit"
    case workspaceClose = "workspace.close"
    case toolWindowShow = "tool-window.show"
    case toolWindowHide = "tool-window.hide"
    case toolWindowToggle = "tool-window.toggle"
}

public enum WorkspaceCLICloseScope: String, Codable, Equatable, Sendable {
    case session
    case project
}

public struct WorkspaceCLICommandTarget: Codable, Equatable, Sendable {
    public var projectPath: String?
    public var workspaceID: String?
    public var paneID: String?
    public var terminalSessionID: String?
    public var useCurrentContext: Bool

    public init(
        projectPath: String? = nil,
        workspaceID: String? = nil,
        paneID: String? = nil,
        terminalSessionID: String? = nil,
        useCurrentContext: Bool = false
    ) {
        self.projectPath = projectPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.workspaceID = workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.paneID = paneID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.terminalSessionID = terminalSessionID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.useCurrentContext = useCurrentContext
    }
}

public struct WorkspaceCLICommandPayload: Codable, Equatable, Sendable {
    public var kind: WorkspaceCLICommandKind
    public var target: WorkspaceCLICommandTarget?
    public var closeScope: WorkspaceCLICloseScope?
    public var toolWindowKind: String?

    public init(
        kind: WorkspaceCLICommandKind,
        target: WorkspaceCLICommandTarget? = nil,
        closeScope: WorkspaceCLICloseScope? = nil,
        toolWindowKind: String? = nil
    ) {
        self.kind = kind
        self.target = target
        self.closeScope = closeScope
        self.toolWindowKind = toolWindowKind?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

public struct WorkspaceCLIRequestSource: Codable, Equatable, Sendable {
    public var pid: Int32
    public var currentWorkingDirectory: String
    public var arguments: [String]

    public init(pid: Int32, currentWorkingDirectory: String, arguments: [String]) {
        self.pid = pid
        self.currentWorkingDirectory = currentWorkingDirectory
        self.arguments = arguments
    }
}

public struct WorkspaceCLIRequestEnvelope: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var requestID: String
    public var createdAt: Date
    public var source: WorkspaceCLIRequestSource
    public var command: WorkspaceCLICommandPayload

    public init(
        requestID: String,
        createdAt: Date = Date(),
        source: WorkspaceCLIRequestSource,
        command: WorkspaceCLICommandPayload
    ) {
        self.schemaVersion = Self.schemaVersion
        self.requestID = requestID
        self.createdAt = createdAt
        self.source = source
        self.command = command
    }
}

public enum WorkspaceCLIResponseStatus: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
}

public struct WorkspaceCLIToolWindowSnapshot: Codable, Equatable, Sendable {
    public var placement: String
    public var activeKind: String?
    public var isVisible: Bool
    public var dimension: Double

    public init(placement: String, activeKind: String?, isVisible: Bool, dimension: Double) {
        self.placement = placement
        self.activeKind = activeKind
        self.isVisible = isVisible
        self.dimension = dimension
    }
}

public struct WorkspaceCLIWorkspaceSummary: Codable, Equatable, Sendable {
    public var projectPath: String
    public var rootProjectPath: String
    public var kind: String
    public var isActive: Bool
    public var workspaceID: String?
    public var workspaceName: String?

    public init(
        projectPath: String,
        rootProjectPath: String,
        kind: String,
        isActive: Bool,
        workspaceID: String? = nil,
        workspaceName: String? = nil
    ) {
        self.projectPath = projectPath
        self.rootProjectPath = rootProjectPath
        self.kind = kind
        self.isActive = isActive
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
    }
}

public struct WorkspaceCLICapabilities: Codable, Equatable, Sendable {
    public static let protocolVersion = 1
    public static let supportedNamespaces: [String] = [
        "workspace",
        "tool-window"
    ]
    public static let supportedCommands: [String] = WorkspaceCLICommandKind.allCases.map(\.rawValue)

    public var protocolVersion: Int
    public var appVersion: String?
    public var buildVersion: String?
    public var commands: [String]
    public var namespaces: [String]

    public init(
        protocolVersion: Int = Self.protocolVersion,
        appVersion: String? = nil,
        buildVersion: String? = nil,
        commands: [String] = Self.supportedCommands,
        namespaces: [String] = Self.supportedNamespaces
    ) {
        self.protocolVersion = protocolVersion
        self.appVersion = appVersion
        self.buildVersion = buildVersion
        self.commands = commands
        self.namespaces = namespaces
    }
}

public struct WorkspaceCLIStatusSummary: Codable, Equatable, Sendable {
    public var isRunning: Bool
    public var isReady: Bool
    public var pid: Int32?
    public var appVersion: String?
    public var buildVersion: String?
    public var activeWorkspaceProjectPath: String?
    public var openWorkspaceCount: Int
    public var sideToolWindow: WorkspaceCLIToolWindowSnapshot
    public var bottomToolWindow: WorkspaceCLIToolWindowSnapshot

    public init(
        isRunning: Bool,
        isReady: Bool,
        pid: Int32? = nil,
        appVersion: String? = nil,
        buildVersion: String? = nil,
        activeWorkspaceProjectPath: String? = nil,
        openWorkspaceCount: Int,
        sideToolWindow: WorkspaceCLIToolWindowSnapshot,
        bottomToolWindow: WorkspaceCLIToolWindowSnapshot
    ) {
        self.isRunning = isRunning
        self.isReady = isReady
        self.pid = pid
        self.appVersion = appVersion
        self.buildVersion = buildVersion
        self.activeWorkspaceProjectPath = activeWorkspaceProjectPath
        self.openWorkspaceCount = openWorkspaceCount
        self.sideToolWindow = sideToolWindow
        self.bottomToolWindow = bottomToolWindow
    }

    public static func offline() -> WorkspaceCLIStatusSummary {
        WorkspaceCLIStatusSummary(
            isRunning: false,
            isReady: false,
            pid: nil,
            appVersion: nil,
            buildVersion: nil,
            activeWorkspaceProjectPath: nil,
            openWorkspaceCount: 0,
            sideToolWindow: WorkspaceCLIToolWindowSnapshot(
                placement: "side",
                activeKind: nil,
                isVisible: false,
                dimension: 0
            ),
            bottomToolWindow: WorkspaceCLIToolWindowSnapshot(
                placement: "bottom",
                activeKind: nil,
                isVisible: false,
                dimension: 0
            )
        )
    }
}

public struct WorkspaceCLIResponsePayload: Codable, Equatable, Sendable {
    public var capabilities: WorkspaceCLICapabilities?
    public var status: WorkspaceCLIStatusSummary?
    public var workspaces: [WorkspaceCLIWorkspaceSummary]?

    public init(
        capabilities: WorkspaceCLICapabilities? = nil,
        status: WorkspaceCLIStatusSummary? = nil,
        workspaces: [WorkspaceCLIWorkspaceSummary]? = nil
    ) {
        self.capabilities = capabilities
        self.status = status
        self.workspaces = workspaces
    }
}

public struct WorkspaceCLIResponseEnvelope: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var requestID: String
    public var finishedAt: Date
    public var status: WorkspaceCLIResponseStatus
    public var code: String?
    public var message: String?
    public var payload: WorkspaceCLIResponsePayload?

    public init(
        requestID: String,
        finishedAt: Date = Date(),
        status: WorkspaceCLIResponseStatus,
        code: String? = nil,
        message: String? = nil,
        payload: WorkspaceCLIResponsePayload? = nil
    ) {
        self.schemaVersion = Self.schemaVersion
        self.requestID = requestID
        self.finishedAt = finishedAt
        self.status = status
        self.code = code?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.message = message?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.payload = payload
    }
}

public struct WorkspaceCLIServerState: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var protocolVersion: Int
    public var pid: Int32
    public var startedAt: Date
    public var isReady: Bool
    public var appVersion: String?
    public var buildVersion: String?
    public var commands: [String]
    public var namespaces: [String]

    public init(
        pid: Int32,
        startedAt: Date = Date(),
        isReady: Bool,
        appVersion: String? = nil,
        buildVersion: String? = nil,
        commands: [String] = WorkspaceCLICapabilities.supportedCommands,
        namespaces: [String] = WorkspaceCLICapabilities.supportedNamespaces
    ) {
        self.schemaVersion = Self.schemaVersion
        self.protocolVersion = WorkspaceCLICapabilities.protocolVersion
        self.pid = pid
        self.startedAt = startedAt
        self.isReady = isReady
        self.appVersion = appVersion
        self.buildVersion = buildVersion
        self.commands = commands
        self.namespaces = namespaces
    }
}

public struct WorkspaceCLIQueuedRequest: Equatable, Sendable {
    public var fileURL: URL
    public var envelope: WorkspaceCLIRequestEnvelope

    public init(fileURL: URL, envelope: WorkspaceCLIRequestEnvelope) {
        self.fileURL = fileURL
        self.envelope = envelope
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
