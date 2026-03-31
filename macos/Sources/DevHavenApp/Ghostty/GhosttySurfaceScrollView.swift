import AppKit

@MainActor
final class GhosttySurfaceScrollView: NSView {
    private struct ScrollbarState: Equatable {
        let total: UInt64
        let offset: UInt64
        let length: UInt64
    }

    private let scrollView: NSScrollView
    private let documentView: NSView
    private(set) var surfaceView: NSView
    private var observers: [NSObjectProtocol] = []
    private var isLiveScrolling = false
    private var lastSentRow: Int?
    private var scrollbar: ScrollbarState?
    private var onSurfaceAttached: (() -> Void)?
    private var needsSurfaceAttachmentCallback = true

    init(surfaceView: NSView, onSurfaceAttached: (() -> Void)? = nil) {
        self.surfaceView = surfaceView
        self.onSurfaceAttached = onSurfaceAttached
        scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.usesPredominantAxisScrolling = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.contentView.clipsToBounds = false
        documentView = NSView(frame: .zero)
        scrollView.documentView = documentView
        super.init(frame: .zero)
        configureAccessibilityTreeExclusion(for: self)
        configureAccessibilityTreeExclusion(for: scrollView)
        configureAccessibilityTreeExclusion(for: documentView)
        configureAccessibilityTreeExclusion(for: surfaceView)

        addSubview(scrollView)
        documentView.addSubview(surfaceView)
        bindScrollWrapperIfNeeded(to: surfaceView)

        scrollView.contentView.postsBoundsChangedNotifications = true
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleScrollChange()
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSScrollView.willStartLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isLiveScrolling = true
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isLiveScrolling = false
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSScrollView.didLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleLiveScroll()
                }
            }
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        surfaceView.frame.size = scrollView.bounds.size
        documentView.frame.size.width = scrollView.bounds.width
        synchronizeScrollView()
        synchronizeSurfaceView()
        (surfaceView as? GhosttyTerminalSurfaceView)?.updateSurfaceSize()
        if needsSurfaceAttachmentCallback {
            needsSurfaceAttachmentCallback = false
            onSurfaceAttached?()
        }
    }

    func setSurfaceView(_ newSurfaceView: NSView) {
        guard newSurfaceView !== surfaceView else { return }
        if let current = surfaceView as? GhosttyTerminalSurfaceView {
            current.scrollWrapper = nil
        }
        surfaceView.removeFromSuperview()
        surfaceView = newSurfaceView
        configureAccessibilityTreeExclusion(for: newSurfaceView)
        documentView.addSubview(newSurfaceView)
        bindScrollWrapperIfNeeded(to: newSurfaceView)
        needsSurfaceAttachmentCallback = true
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func setSurfaceAttachmentHandler(_ handler: (() -> Void)?) {
        onSurfaceAttached = handler
    }

    func updateSurfaceSize() {
        (surfaceView as? GhosttyTerminalSurfaceView)?.updateSurfaceSize()
        needsLayout = true
    }

    func updateScrollbar(total: UInt64, offset: UInt64, length: UInt64) {
        let nextScrollbar = ScrollbarState(total: total, offset: offset, length: length)
        guard scrollbar != nextScrollbar else {
            return
        }
        scrollbar = nextScrollbar
        scrollView.hasVerticalScroller = true
        synchronizeScrollView()
    }

    private func bindScrollWrapperIfNeeded(to view: NSView) {
        guard let surfaceView = view as? GhosttyTerminalSurfaceView else { return }
        surfaceView.scrollWrapper = self
    }

    private func configureAccessibilityTreeExclusion(for view: NSView) {
        view.setAccessibilityElement(false)
        view.setAccessibilityHidden(true)
    }

    private func handleScrollChange() {
        synchronizeSurfaceView()
    }

    private func synchronizeSurfaceView() {
        let visibleRect = scrollView.contentView.documentVisibleRect
        surfaceView.frame.origin = visibleRect.origin
    }

    private func synchronizeScrollView() {
        documentView.frame.size.height = documentHeight()
        if !isLiveScrolling,
           let surfaceView = surfaceView as? GhosttyTerminalSurfaceView {
            let cellHeight = surfaceView.currentCellSize().height
            if cellHeight > 0, let scrollbar {
                let offsetY = CGFloat(scrollbar.total - scrollbar.offset - scrollbar.length) * cellHeight
                scrollView.contentView.scroll(to: CGPoint(x: 0, y: offsetY))
                lastSentRow = Int(scrollbar.offset)
            }
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func handleLiveScroll() {
        guard let surfaceView = surfaceView as? GhosttyTerminalSurfaceView else { return }
        let cellHeight = surfaceView.currentCellSize().height
        guard cellHeight > 0 else { return }
        let visibleRect = scrollView.contentView.documentVisibleRect
        let documentHeight = documentView.frame.height
        let scrollOffset = documentHeight - visibleRect.origin.y - visibleRect.height
        let row = Int(scrollOffset / cellHeight)
        guard row != lastSentRow else { return }
        lastSentRow = row
        surfaceView.performBindingAction("scroll_to_row:\(row)")
    }

    private func documentHeight() -> CGFloat {
        let contentHeight = scrollView.contentSize.height
        guard let surfaceView = surfaceView as? GhosttyTerminalSurfaceView else {
            return contentHeight
        }
        let cellHeight = surfaceView.currentCellSize().height
        if cellHeight > 0, let scrollbar {
            let documentGridHeight = CGFloat(scrollbar.total) * cellHeight
            let padding = contentHeight - (CGFloat(scrollbar.length) * cellHeight)
            return documentGridHeight + padding
        }
        return contentHeight
    }
}
