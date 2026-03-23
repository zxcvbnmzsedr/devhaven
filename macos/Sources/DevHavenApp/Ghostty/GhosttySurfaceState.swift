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
    var searchNeedle: String?
    var searchTotal: Int?
    var searchSelected: Int?
    var searchFocusCount = 0
}
