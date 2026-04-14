import AppKit
import Dispatch

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
    private var windowObservers: [NSObjectProtocol] = []
    private var isLiveScrolling = false
    private var lastSentRow: Int?
    private var scrollbar: ScrollbarState?
    private var onSurfaceAttached: ((NSView) -> Void)?
    private var onLiveScrollChange: ((Bool) -> Void)?
    private var needsSurfaceAttachmentCallback = true
    private var pendingLiveScrollRow: Int?
    private var isLiveScrollFlushScheduled = false
    private weak var lastAttachedSuperview: NSView?
    private weak var lastAttachedWindow: NSWindow?

    init(
        surfaceView: NSView,
        onSurfaceAttached: ((NSView) -> Void)? = nil,
        onLiveScrollChange: ((Bool) -> Void)? = nil
    ) {
        self.surfaceView = surfaceView
        self.onSurfaceAttached = onSurfaceAttached
        self.onLiveScrollChange = onLiveScrollChange
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
                MainActor.assumeIsolated {
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
                MainActor.assumeIsolated {
                    self?.setLiveScrolling(true)
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.flushPendingLiveScrollRow()
                    self?.setLiveScrolling(false)
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSScrollView.didLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
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
        let center = NotificationCenter.default
        observers.forEach { center.removeObserver($0) }
        windowObservers.forEach { center.removeObserver($0) }
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        surfaceView.frame.size = scrollView.bounds.size
        documentView.frame.size.width = scrollView.bounds.width
        synchronizeScrollView()
        synchronizeSurfaceView()
        (surfaceView as? GhosttyTerminalSurfaceView)?.updateSurfaceSize()
        if shouldFireSurfaceAttachmentCallback {
            needsSurfaceAttachmentCallback = false
            onSurfaceAttached?(surfaceView)
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        rearmSurfaceAttachmentIfNeededAfterHierarchyChange()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindowObservers()
        rearmSurfaceAttachmentIfNeededAfterHierarchyChange()
    }

    func setSurfaceView(_ newSurfaceView: NSView) {
        guard newSurfaceView !== surfaceView else { return }
        if let current = surfaceView as? GhosttyTerminalSurfaceView {
            current.prepareForContainerReuse()
            current.scrollWrapper = nil
        }
        (newSurfaceView as? GhosttyTerminalSurfaceView)?.prepareForContainerReuse()
        surfaceView.removeFromSuperview()
        surfaceView = newSurfaceView
        configureAccessibilityTreeExclusion(for: newSurfaceView)
        documentView.addSubview(newSurfaceView)
        bindScrollWrapperIfNeeded(to: newSurfaceView)
        needsSurfaceAttachmentCallback = true
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func setSurfaceAttachmentHandler(_ handler: ((NSView) -> Void)?) {
        onSurfaceAttached = handler
    }

    func setLiveScrollChangeHandler(_ handler: ((Bool) -> Void)?) {
        onLiveScrollChange = handler
        handler?(isLiveScrolling)
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

    private var shouldFireSurfaceAttachmentCallback: Bool {
        needsSurfaceAttachmentCallback
        && window != nil
        && superview != nil
        && surfaceView.isDescendant(of: documentView)
        && surfaceView.window === window
        && bounds.width > 0
        && bounds.height > 0
    }

    private func rearmSurfaceAttachmentIfNeededAfterHierarchyChange() {
        guard let superview, let window else {
            lastAttachedSuperview = nil
            lastAttachedWindow = nil
            clearWindowObservers()
            return
        }

        let superviewChanged = lastAttachedSuperview !== superview
        let windowChanged = lastAttachedWindow !== window
        guard superviewChanged || windowChanged else {
            return
        }

        lastAttachedSuperview = superview
        lastAttachedWindow = window
        needsSurfaceAttachmentCallback = true
        needsLayout = true
    }

    private func updateWindowObservers() {
        clearWindowObservers()
        guard let window else {
            return
        }
        let center = NotificationCenter.default
        windowObservers.append(
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main,
                using: { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.replaySurfaceAttachmentAfterWindowActivity()
                    }
                }
            )
        )
        windowObservers.append(
            center.addObserver(
                forName: NSWindow.didBecomeMainNotification,
                object: window,
                queue: .main,
                using: { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.replaySurfaceAttachmentAfterWindowActivity()
                    }
                }
            )
        )
        windowObservers.append(
            center.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main,
                using: { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.replaySurfaceAttachmentAfterWindowActivity()
                    }
                }
            )
        )
    }

    private func clearWindowObservers() {
        let center = NotificationCenter.default
        for observer in windowObservers {
            center.removeObserver(observer)
        }
        windowObservers.removeAll()
    }

    func replaySurfaceAttachmentAfterWindowActivity() {
        guard let window else {
            return
        }
        guard window.isKeyWindow || window.occlusionState.contains(.visible) else {
            return
        }
        needsSurfaceAttachmentCallback = true
        if shouldFireSurfaceAttachmentCallback {
            needsSurfaceAttachmentCallback = false
            onSurfaceAttached?(surfaceView)
        } else {
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
        window.displayIfNeeded()
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
        guard surfaceView.frame.origin != visibleRect.origin else {
            return
        }
        surfaceView.frame.origin = visibleRect.origin
    }

    private func synchronizeScrollView(forceReflect: Bool = false) {
        let nextDocumentHeight = documentHeight()
        let documentHeightChanged = abs(documentView.frame.height - nextDocumentHeight) > .ulpOfOne
        if documentHeightChanged {
            documentView.frame.size.height = nextDocumentHeight
        }

        var didScrollProgrammatically = false
        if !isLiveScrolling,
           let surfaceView = surfaceView as? GhosttyTerminalSurfaceView {
            let cellHeight = surfaceView.currentCellSize().height
            if cellHeight > 0, let scrollbar {
                let offsetY = CGFloat(scrollbar.total - scrollbar.offset - scrollbar.length) * cellHeight
                let currentOrigin = scrollView.contentView.bounds.origin
                if abs(currentOrigin.y - offsetY) > .ulpOfOne {
                    scrollView.contentView.scroll(to: CGPoint(x: currentOrigin.x, y: offsetY))
                    didScrollProgrammatically = true
                }
                lastSentRow = Int(scrollbar.offset)
                pendingLiveScrollRow = nil
            }
        }

        if forceReflect || documentHeightChanged || didScrollProgrammatically {
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
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
        pendingLiveScrollRow = row
        scheduleLiveScrollRowFlush()
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

    private func setLiveScrolling(_ isLiveScrolling: Bool) {
        guard self.isLiveScrolling != isLiveScrolling else {
            return
        }
        self.isLiveScrolling = isLiveScrolling
        onLiveScrollChange?(isLiveScrolling)
    }

    private func scheduleLiveScrollRowFlush() {
        guard !isLiveScrollFlushScheduled else {
            return
        }
        isLiveScrollFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.flushPendingLiveScrollRow()
            }
        }
    }

    private func flushPendingLiveScrollRow() {
        isLiveScrollFlushScheduled = false
        guard let row = pendingLiveScrollRow,
              let surfaceView = surfaceView as? GhosttyTerminalSurfaceView
        else {
            return
        }
        pendingLiveScrollRow = nil
        guard row != lastSentRow else {
            return
        }
        lastSentRow = row
        surfaceView.performBindingAction("scroll_to_row:\(row)")
    }
}
