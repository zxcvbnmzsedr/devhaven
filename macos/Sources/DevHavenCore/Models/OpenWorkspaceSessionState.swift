import Foundation

public struct OpenWorkspaceSessionState: Identifiable, Equatable {
    public var projectPath: String
    public var controller: GhosttyWorkspaceController

    public init(projectPath: String, controller: GhosttyWorkspaceController) {
        self.projectPath = projectPath
        self.controller = controller
    }

    public nonisolated var id: String { projectPath }

    public nonisolated static func == (lhs: OpenWorkspaceSessionState, rhs: OpenWorkspaceSessionState) -> Bool {
        lhs.projectPath == rhs.projectPath
    }
}
