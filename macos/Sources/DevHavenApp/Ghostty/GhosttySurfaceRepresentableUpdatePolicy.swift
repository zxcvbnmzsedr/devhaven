enum GhosttySurfaceRepresentableUpdatePolicy {
    static let shouldApplyLatestModelStateOnUpdate = false

    @MainActor
    static func resolvedSurfaceView(
        for model: GhosttySurfaceHostModel,
        preferredFocus: Bool
    ) -> GhosttyTerminalSurfaceView {
        model.currentSurfaceView ?? model.acquireSurfaceView(preferredFocus: preferredFocus)
    }
}
