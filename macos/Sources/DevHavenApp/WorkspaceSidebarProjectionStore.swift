import Foundation
import DevHavenCore

@MainActor
final class WorkspaceSidebarProjectionStore: ObservableObject {
    @Published private(set) var projection = WorkspaceSidebarProjectionState()

    func sync(from viewModel: NativeAppViewModel) {
        let nextProjection = viewModel.workspaceSidebarProjectionState()
        guard projection != nextProjection else {
            return
        }
        projection = nextProjection
    }
}
