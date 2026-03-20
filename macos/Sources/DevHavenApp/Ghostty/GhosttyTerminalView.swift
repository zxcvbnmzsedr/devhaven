import SwiftUI

private struct GhosttySurfaceRepresentable: NSViewRepresentable {
    @ObservedObject var model: GhosttySurfaceHostModel
    let isFocused: Bool

    func makeNSView(context: Context) -> GhosttyTerminalSurfaceView {
        model.acquireSurfaceView(preferredFocus: isFocused)
    }

    func updateNSView(_ nsView: GhosttyTerminalSurfaceView, context: Context) {
        model.applyLatestModelState(preferredFocus: isFocused)
    }
}

struct GhosttyTerminalView: View {
    @ObservedObject var model: GhosttySurfaceHostModel
    let isFocused: Bool

    var body: some View {
        GhosttySurfaceRepresentable(model: model, isFocused: isFocused)
    }
}
