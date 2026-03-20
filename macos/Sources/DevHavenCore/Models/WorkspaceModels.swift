import Foundation

public struct WorkspaceTerminalLaunchRequest: Equatable, Sendable {
    public var projectPath: String
    public var workspaceId: String
    public var tabId: String
    public var paneId: String
    public var surfaceId: String
    public var terminalSessionId: String
    public var terminalRuntime: String

    public init(
        projectPath: String,
        workspaceId: String,
        tabId: String,
        paneId: String,
        surfaceId: String,
        terminalSessionId: String,
        terminalRuntime: String = "ghostty"
    ) {
        self.projectPath = projectPath
        self.workspaceId = workspaceId
        self.tabId = tabId
        self.paneId = paneId
        self.surfaceId = surfaceId
        self.terminalSessionId = terminalSessionId
        self.terminalRuntime = terminalRuntime
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
