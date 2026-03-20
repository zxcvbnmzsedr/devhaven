import Foundation

public struct OpenWorkspaceSessionState: Identifiable, Equatable, Sendable {
    public var id: String { projectPath }
    public var projectPath: String
    public var workspaceState: WorkspaceSessionState

    public init(projectPath: String, workspaceState: WorkspaceSessionState) {
        self.projectPath = projectPath
        self.workspaceState = workspaceState
    }
}
