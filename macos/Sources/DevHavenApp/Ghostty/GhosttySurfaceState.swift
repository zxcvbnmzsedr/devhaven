import Observation

enum GhosttySurfaceTaskStatus: Equatable {
    case idle
    case running
}

@Observable
final class GhosttySurfaceState {
    var title: String?
    var pwd: String?
    var rendererHealthy = true
    var appearance: GhosttySurfaceAppearance = .fallback
    var taskStatus: GhosttySurfaceTaskStatus = .idle
    var bellCount = 0
}
