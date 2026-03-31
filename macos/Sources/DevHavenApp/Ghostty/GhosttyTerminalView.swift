import SwiftUI

private struct GhosttySurfaceRepresentable: NSViewRepresentable {
    let model: GhosttySurfaceHostModel
    let isFocused: Bool

    func makeNSView(context: Context) -> GhosttySurfaceScrollView {
        GhosttySurfaceLifecycleDiagnostics.shared.recordRepresentableMake(
            request: model.request,
            preferredFocus: isFocused,
            prepareForAttachment: true
        )
        return GhosttySurfaceScrollView(
            surfaceView: GhosttySurfaceRepresentableUpdatePolicy.resolvedSurfaceView(
                for: model,
                preferredFocus: isFocused,
                prepareForAttachment: true
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
            preferredFocus: isFocused,
            prepareForAttachment: false
        )
        GhosttySurfaceLifecycleDiagnostics.shared.recordRepresentableUpdate(
            request: model.request,
            preferredFocus: isFocused,
            prepareForAttachment: false,
            surfaceSwap: nsView.surfaceView !== resolvedSurfaceView
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
    let model: GhosttySurfaceHostModel
    let isFocused: Bool

    var body: some View {
        GhosttySurfaceRepresentable(model: model, isFocused: isFocused)
            // 终端内容会高频刷新（例如 agent spinner / elapsed time），
            // 若继续参与 SwiftUI accessibility graph，主线程会放大
            // AccessibilityViewGraph / PropertiesTransform 的更新成本。
            .accessibilityHidden(true)
            .onChange(of: isFocused) { _, focused in
                model.syncPreferredFocusTransition(preferredFocus: focused)
            }
    }
}
