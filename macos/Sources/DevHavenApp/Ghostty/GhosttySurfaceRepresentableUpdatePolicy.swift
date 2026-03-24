enum GhosttySurfaceRepresentableUpdatePolicy {
    static let shouldApplyLatestModelStateOnUpdate = false

    @MainActor
    static func resolvedSurfaceView(
        for model: GhosttySurfaceHostModel,
        preferredFocus: Bool,
        prepareForAttachment: Bool
    ) -> GhosttyTerminalSurfaceView {
        if prepareForAttachment {
            return model.acquireSurfaceView(preferredFocus: preferredFocus)
        }
        return model.currentSurfaceView ?? model.acquireSurfaceView(preferredFocus: preferredFocus)
    }
}
