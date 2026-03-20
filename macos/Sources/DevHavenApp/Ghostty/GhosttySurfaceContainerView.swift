import AppKit

@MainActor
final class GhosttySurfaceContainerView: NSView {
    private let scrollView: NSScrollView
    private let documentView: NSView
    private(set) var surfaceView: NSView

    init(surfaceView: NSView) {
        self.surfaceView = surfaceView
        self.scrollView = NSScrollView()
        self.documentView = NSView(frame: .zero)
        super.init(frame: .zero)

        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.usesPredominantAxisScrolling = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.contentView.clipsToBounds = false
        scrollView.documentView = documentView

        documentView.addSubview(surfaceView)
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        documentView.frame = NSRect(origin: .zero, size: scrollView.bounds.size)
        surfaceView.frame = NSRect(origin: .zero, size: scrollView.bounds.size)
    }

    func setSurfaceView(_ newSurfaceView: NSView) {
        guard newSurfaceView !== surfaceView else { return }
        surfaceView.removeFromSuperview()
        surfaceView = newSurfaceView
        documentView.addSubview(newSurfaceView)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
}
