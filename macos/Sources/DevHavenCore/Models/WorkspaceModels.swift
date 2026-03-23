import Foundation

public struct WorkspaceTerminalRestoreContext: Equatable, Sendable {
    public var workingDirectory: String?
    public var title: String?
    public var snapshotText: String?
    public var agentSummary: String?

    public init(
        workingDirectory: String?,
        title: String?,
        snapshotText: String?,
        agentSummary: String?
    ) {
        self.workingDirectory = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.snapshotText = snapshotText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.agentSummary = agentSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var isEmpty: Bool {
        workingDirectory == nil && title == nil && snapshotText == nil && agentSummary == nil
    }
}

public struct WorkspaceTerminalLaunchRequest: Equatable, Sendable {
    public var projectPath: String
    public var workspaceId: String
    public var tabId: String
    public var paneId: String
    public var surfaceId: String
    public var terminalSessionId: String
    public var terminalRuntime: String
    public var workingDirectoryOverride: String?
    public var restoreContext: WorkspaceTerminalRestoreContext?

    public init(
        projectPath: String,
        workspaceId: String,
        tabId: String,
        paneId: String,
        surfaceId: String,
        terminalSessionId: String,
        terminalRuntime: String = "ghostty",
        workingDirectoryOverride: String? = nil,
        restoreContext: WorkspaceTerminalRestoreContext? = nil
    ) {
        self.projectPath = projectPath
        self.workspaceId = workspaceId
        self.tabId = tabId
        self.paneId = paneId
        self.surfaceId = surfaceId
        self.terminalSessionId = terminalSessionId
        self.terminalRuntime = terminalRuntime
        self.workingDirectoryOverride = workingDirectoryOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.restoreContext = restoreContext
    }

    public var workingDirectory: String {
        workingDirectoryOverride
            ?? restoreContext?.workingDirectory
            ?? projectPath
    }

    public var environment: [String: String] {
        [
            "DEVHAVEN_PROJECT_PATH": projectPath,
            "DEVHAVEN_WORKSPACE_ID": workspaceId,
            "DEVHAVEN_TAB_ID": tabId,
            "DEVHAVEN_PANE_ID": paneId,
            "DEVHAVEN_SURFACE_ID": surfaceId,
            "DEVHAVEN_TERMINAL_SESSION_ID": terminalSessionId,
            "DEVHAVEN_TERMINAL_RUNTIME": terminalRuntime,
        ]
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
