import Foundation

public struct OpenWorkspaceSessionState: Identifiable, Equatable {
    public var projectPath: String
    public var rootProjectPath: String
    public var controller: GhosttyWorkspaceController
    public var isQuickTerminal: Bool
    public var workspaceRootContext: WorkspaceRootSessionContext?

    public init(
        projectPath: String,
        rootProjectPath: String? = nil,
        controller: GhosttyWorkspaceController,
        isQuickTerminal: Bool = false,
        workspaceRootContext: WorkspaceRootSessionContext? = nil
    ) {
        self.projectPath = projectPath
        self.rootProjectPath = rootProjectPath ?? projectPath
        self.controller = controller
        self.isQuickTerminal = isQuickTerminal
        self.workspaceRootContext = workspaceRootContext
    }

    public nonisolated var id: String { projectPath }

    public nonisolated static func == (lhs: OpenWorkspaceSessionState, rhs: OpenWorkspaceSessionState) -> Bool {
        lhs.projectPath == rhs.projectPath &&
            lhs.rootProjectPath == rhs.rootProjectPath &&
            lhs.isQuickTerminal == rhs.isQuickTerminal &&
            lhs.workspaceRootContext == rhs.workspaceRootContext
    }
}
