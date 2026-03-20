import SwiftUI

private struct GhosttySurfaceRepresentable: NSViewRepresentable {
    @ObservedObject var model: GhosttySurfaceHostModel
    let isFocused: Bool

    func makeNSView(context: Context) -> GhosttySurfaceScrollView {
        GhosttySurfaceScrollView(surfaceView: model.acquireSurfaceView(preferredFocus: isFocused))
    }

    func updateNSView(_ nsView: GhosttySurfaceScrollView, context: Context) {
        if let currentSurfaceView = model.currentSurfaceView,
           nsView.surfaceView !== currentSurfaceView {
            nsView.setSurfaceView(currentSurfaceView)
        }
        guard GhosttySurfaceRepresentableUpdatePolicy.shouldApplyLatestModelStateOnUpdate else {
            return
        }
        model.applyLatestModelState(preferredFocus: isFocused)
    }
}

struct GhosttyTerminalView: View {
    @ObservedObject var model: GhosttySurfaceHostModel
    let isFocused: Bool

    var body: some View {
        GhosttySurfaceRepresentable(model: model, isFocused: isFocused)
            .onChange(of: isFocused) { _, focused in
                model.syncPreferredFocusTransition(preferredFocus: focused)
            }
    }
}
