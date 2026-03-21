import SwiftUI

private struct GhosttySurfaceRepresentable: NSViewRepresentable {
    @ObservedObject var model: GhosttySurfaceHostModel
    let isFocused: Bool

    func makeNSView(context: Context) -> GhosttySurfaceScrollView {
        GhosttySurfaceScrollView(
            surfaceView: GhosttySurfaceRepresentableUpdatePolicy.resolvedSurfaceView(
                for: model,
                preferredFocus: isFocused
            ),
            onSurfaceAttached: {
                model.surfaceViewDidAttach(preferredFocus: isFocused)
            }
        )
    }

    func updateNSView(_ nsView: GhosttySurfaceScrollView, context: Context) {
        nsView.setSurfaceAttachmentHandler {
            model.surfaceViewDidAttach(preferredFocus: isFocused)
        }
        let resolvedSurfaceView = GhosttySurfaceRepresentableUpdatePolicy.resolvedSurfaceView(
            for: model,
            preferredFocus: isFocused
        )
        if nsView.surfaceView !== resolvedSurfaceView {
            nsView.setSurfaceView(resolvedSurfaceView)
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
