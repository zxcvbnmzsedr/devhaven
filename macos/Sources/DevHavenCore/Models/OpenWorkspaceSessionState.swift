import Foundation

public struct OpenWorkspaceSessionState: Identifiable, Equatable {
    public var projectPath: String
    public var rootProjectPath: String
    public var controller: GhosttyWorkspaceController
    public var isQuickTerminal: Bool

    public init(projectPath: String, rootProjectPath: String? = nil, controller: GhosttyWorkspaceController, isQuickTerminal: Bool = false) {
        self.projectPath = projectPath
        self.rootProjectPath = rootProjectPath ?? projectPath
        self.controller = controller
        self.isQuickTerminal = isQuickTerminal
    }

    public nonisolated var id: String { projectPath }

    public nonisolated static func == (lhs: OpenWorkspaceSessionState, rhs: OpenWorkspaceSessionState) -> Bool {
        lhs.projectPath == rhs.projectPath && lhs.rootProjectPath == rhs.rootProjectPath
    }
}
