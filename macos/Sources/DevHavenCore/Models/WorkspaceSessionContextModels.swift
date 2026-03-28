import Foundation

public struct WorkspaceRootSessionContext: Codable, Equatable, Sendable {
    public var workspaceID: String
    public var workspaceName: String

    public init(workspaceID: String, workspaceName: String) {
        self.workspaceID = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.workspaceName = workspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
