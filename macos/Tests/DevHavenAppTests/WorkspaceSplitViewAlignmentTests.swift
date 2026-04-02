import XCTest
import SwiftUI
import AppKit
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class WorkspaceSplitViewAlignmentTests: XCTestCase {
    func testVerticalSplitKeepsLeadingContentPinnedToTop() {
        let probe = SplitViewFrameProbe()
        let window = makeWindow()
        defer {
            window.orderOut(nil)
        }

        let hostingView = NSHostingView(
            rootView: verticalSplitTestView(probe: probe)
        )
        window.contentView = hostingView
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        pumpMainRunLoop(ticks: 20)

        XCTAssertEqual(
            probe.leadingFrame?.minY ?? -1,
            0,
            accuracy: 1,
            "vertical split 的 leading 内容应贴住顶部，避免在大容器里被垂直居中后留下整块空白。"
        )
    }

    func testHorizontalSplitKeepsLeadingContentPinnedToLeadingEdge() {
        let probe = SplitViewFrameProbe()
        let window = makeWindow()
        defer {
            window.orderOut(nil)
        }

        let hostingView = NSHostingView(
            rootView: horizontalSplitTestView(probe: probe)
        )
        window.contentView = hostingView
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        pumpMainRunLoop(ticks: 20)

        XCTAssertEqual(
            probe.leadingFrame?.minX ?? -1,
            0,
            accuracy: 1,
            "horizontal split 的 leading 内容应贴住左侧，避免窄内容在 pane 槽位里被水平居中。"
        )
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
    }

    private func verticalSplitTestView(probe: SplitViewFrameProbe) -> some View {
        WorkspaceSplitView(
            direction: .vertical,
            ratio: 0.55,
            onRatioChange: { _ in }
        ) {
            SplitAlignmentProbeView(
                axis: .vertical,
                probe: probe
            )
        } trailing: {
            Color.black
        }
        .frame(width: 420, height: 260)
        .coordinateSpace(name: SplitAlignmentProbeView.coordinateSpaceName)
    }

    private func horizontalSplitTestView(probe: SplitViewFrameProbe) -> some View {
        WorkspaceSplitView(
            direction: .horizontal,
            ratio: 0.45,
            onRatioChange: { _ in }
        ) {
            SplitAlignmentProbeView(
                axis: .horizontal,
                probe: probe
            )
        } trailing: {
            Color.black
        }
        .frame(width: 420, height: 260)
        .coordinateSpace(name: SplitAlignmentProbeView.coordinateSpaceName)
    }

    private func pumpMainRunLoop(ticks: Int) {
        for _ in 0..<ticks {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }
}

@MainActor
private final class SplitViewFrameProbe: ObservableObject {
    @Published var leadingFrame: CGRect?
}

private struct SplitAlignmentProbeView: View {
    static let coordinateSpaceName = "workspace-split-view-alignment-test-space"

    let axis: WorkspaceSplitAxis
    @ObservedObject var probe: SplitViewFrameProbe

    var body: some View {
        Color.orange
            .frame(
                width: axis == .horizontal ? 90 : 160,
                height: axis == .vertical ? 44 : 120
            )
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: SplitAlignmentFramePreferenceKey.self,
                            value: geometry.frame(in: .named(Self.coordinateSpaceName))
                        )
                }
            }
            .onPreferenceChange(SplitAlignmentFramePreferenceKey.self) { frame in
                probe.leadingFrame = frame
            }
    }
}

private struct SplitAlignmentFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
