import XCTest
import AppKit
@testable import DevHavenApp

@MainActor
final class GhosttySurfaceScrollViewTests: XCTestCase {
    func testSurfaceAttachmentWaitsForWindowAndNonZeroBounds() {
        let surfaceView = NSView(frame: .zero)
        var attachmentCount = 0
        let scrollView = GhosttySurfaceScrollView(
            surfaceView: surfaceView,
            onSurfaceAttached: { _ in
                attachmentCount += 1
            }
        )

        scrollView.frame = .zero
        scrollView.layoutSubtreeIfNeeded()
        XCTAssertEqual(attachmentCount, 0, "未挂到窗口且没有有效尺寸时，不应过早触发 surface attach。")

        let window = makeWindow()
        defer {
            window.orderOut(nil)
        }

        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        container.autoresizingMask = [.width, .height]
        window.contentView = container
        container.addSubview(scrollView)
        scrollView.frame = .zero
        window.makeKeyAndOrderFront(nil)
        pumpMainRunLoop(ticks: 10)

        XCTAssertEqual(attachmentCount, 0, "挂到窗口但布局仍为零尺寸时，仍应继续等待真实 attach/layout。")

        scrollView.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
        scrollView.layoutSubtreeIfNeeded()
        pumpMainRunLoop(ticks: 10)

        XCTAssertEqual(attachmentCount, 1, "拿到有效窗口与非零尺寸后，应触发一次 surface attach。")
    }

    func testSurfaceAttachmentRearmsAfterReparentingWithinSameWindow() {
        let surfaceView = NSView(frame: .zero)
        var attachmentCount = 0
        let scrollView = GhosttySurfaceScrollView(
            surfaceView: surfaceView,
            onSurfaceAttached: { _ in
                attachmentCount += 1
            }
        )

        let window = makeWindow()
        defer {
            window.orderOut(nil)
        }

        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        root.autoresizingMask = [.width, .height]
        let leftContainer = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 320))
        let rightContainer = NSView(frame: NSRect(x: 300, y: 0, width: 300, height: 320))
        root.addSubview(leftContainer)
        root.addSubview(rightContainer)
        window.contentView = root

        leftContainer.addSubview(scrollView)
        scrollView.frame = leftContainer.bounds
        window.makeKeyAndOrderFront(nil)
        pumpMainRunLoop(ticks: 10)

        XCTAssertEqual(attachmentCount, 1, "首次挂载应触发一次 surface attach。")

        scrollView.removeFromSuperview()
        rightContainer.addSubview(scrollView)
        scrollView.frame = rightContainer.bounds
        scrollView.layoutSubtreeIfNeeded()
        pumpMainRunLoop(ticks: 10)

        XCTAssertEqual(attachmentCount, 2, "同一窗口内重挂到新容器后，应重新触发 attach，避免 pane 重排后内容卡空白。")
    }

    func testStaleScrollViewDoesNotFireAttachmentForSurfaceItNoLongerOwns() {
        let surfaceView = NSView(frame: .zero)
        var staleAttachmentCount = 0
        var activeAttachmentCount = 0
        let staleScrollView = GhosttySurfaceScrollView(
            surfaceView: surfaceView,
            onSurfaceAttached: { _ in
                staleAttachmentCount += 1
            }
        )

        let window = makeWindow()
        defer {
            window.orderOut(nil)
        }

        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        root.autoresizingMask = [.width, .height]
        let leftContainer = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 320))
        let rightContainer = NSView(frame: NSRect(x: 300, y: 0, width: 300, height: 320))
        root.addSubview(leftContainer)
        root.addSubview(rightContainer)
        window.contentView = root

        leftContainer.addSubview(staleScrollView)
        staleScrollView.frame = leftContainer.bounds
        window.makeKeyAndOrderFront(nil)
        pumpMainRunLoop(ticks: 10)

        XCTAssertEqual(staleAttachmentCount, 1, "旧 scroll view 初次挂载时，应正常触发一次 attach。")

        let activeScrollView = GhosttySurfaceScrollView(
            surfaceView: surfaceView,
            onSurfaceAttached: { _ in
                activeAttachmentCount += 1
            }
        )
        rightContainer.addSubview(activeScrollView)
        activeScrollView.frame = rightContainer.bounds
        activeScrollView.layoutSubtreeIfNeeded()
        pumpMainRunLoop(ticks: 10)

        XCTAssertEqual(activeAttachmentCount, 1, "surface 被新的 scroll view 接管后，新的宿主应成为唯一有效 attach 来源。")

        staleScrollView.replaySurfaceAttachmentAfterWindowActivity()
        staleScrollView.layoutSubtreeIfNeeded()
        pumpMainRunLoop(ticks: 10)

        XCTAssertEqual(
            staleAttachmentCount,
            1,
            "旧 scroll view 如果已经不再持有当前 surface，不应继续发 attach 回调污染当前 host。"
        )
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
    }

    private func pumpMainRunLoop(ticks: Int) {
        for _ in 0..<ticks {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }
}
