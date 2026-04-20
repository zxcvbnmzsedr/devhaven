import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceProjectTreeStateStore {
    var statesByProjectPath: [String: WorkspaceProjectTreeState]
    var refreshingProjectPaths: Set<String>
    @ObservationIgnored var refreshTasksByProjectPath: [String: Task<Void, Never>]
    @ObservationIgnored var refreshGenerationByProjectPath: [String: Int]
    @ObservationIgnored var projectionCacheByProjectPath: [String: (revision: Int, projection: WorkspaceProjectTreeDisplayProjection)]

    init(
        statesByProjectPath: [String: WorkspaceProjectTreeState] = [:],
        refreshingProjectPaths: Set<String> = [],
        refreshTasksByProjectPath: [String: Task<Void, Never>] = [:],
        refreshGenerationByProjectPath: [String: Int] = [:],
        projectionCacheByProjectPath: [String: (revision: Int, projection: WorkspaceProjectTreeDisplayProjection)] = [:]
    ) {
        self.statesByProjectPath = statesByProjectPath
        self.refreshingProjectPaths = refreshingProjectPaths
        self.refreshTasksByProjectPath = refreshTasksByProjectPath
        self.refreshGenerationByProjectPath = refreshGenerationByProjectPath
        self.projectionCacheByProjectPath = projectionCacheByProjectPath
    }
}
