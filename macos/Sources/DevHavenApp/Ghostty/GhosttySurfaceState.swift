import Observation

@Observable
final class GhosttySurfaceState {
    var title: String?
    var pwd: String?
    var rendererHealthy = true
    var appearance: GhosttySurfaceAppearance = .fallback
}
