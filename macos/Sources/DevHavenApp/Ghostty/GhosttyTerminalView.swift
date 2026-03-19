import SwiftUI

private struct GhosttySurfaceRepresentable: NSViewRepresentable {
    @ObservedObject var model: GhosttySurfaceHostModel

    func makeNSView(context: Context) -> GhosttyTerminalSurfaceView {
        model.acquireSurfaceView()
    }

    func updateNSView(_ nsView: GhosttyTerminalSurfaceView, context: Context) {
        model.applyLatestModelState()
    }
}

struct GhosttyTerminalView: View {
    @ObservedObject var model: GhosttySurfaceHostModel

    var body: some View {
        GhosttySurfaceRepresentable(model: model)
    }
}
