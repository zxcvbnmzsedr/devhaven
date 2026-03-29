import SwiftUI
import AppKit
import DevHavenCore

struct WorkspaceTextEditorScrollSyncState: Equatable {
    var sourceID: String?
    var normalizedYOffset: CGFloat
    var revision: Int

    init(sourceID: String? = nil, normalizedYOffset: CGFloat = 0, revision: Int = 0) {
        self.sourceID = sourceID
        self.normalizedYOffset = normalizedYOffset
        self.revision = revision
    }
}

enum WorkspaceTextEditorScrollRequestKind: Equatable {
    case manual
    case selectedDifference
}

struct WorkspaceTextEditorScrollRequestState: Equatable {
    var lineTargets: [String: Int]
    var revision: Int
    var kind: WorkspaceTextEditorScrollRequestKind

    init(
        lineTargets: [String: Int] = [:],
        revision: Int = 0,
        kind: WorkspaceTextEditorScrollRequestKind = .manual
    ) {
        self.lineTargets = lineTargets.mapValues { max(0, $0) }
        self.revision = revision
        self.kind = kind
    }
}

enum WorkspaceTextEditorSearchRequestKind: Equatable {
    case revealSearch
    case findNext
    case findPrevious
    case replaceCurrent
    case replaceAll
    case goToLine
}

struct WorkspaceTextEditorSearchRequestState: Equatable {
    var query: String
    var replacement: String
    var revision: Int
    var kind: WorkspaceTextEditorSearchRequestKind
    var targetLine: Int?
    var isCaseSensitive: Bool

    init(
        query: String = "",
        replacement: String = "",
        revision: Int = 0,
        kind: WorkspaceTextEditorSearchRequestKind = .revealSearch,
        targetLine: Int? = nil,
        isCaseSensitive: Bool = false
    ) {
        self.query = query
        self.replacement = replacement
        self.revision = revision
        self.kind = kind
        self.targetLine = targetLine.map { max(0, $0) }
        self.isCaseSensitive = isCaseSensitive
    }
}

struct WorkspaceTextEditorDecorationSignature: Equatable {
    var text: String
    var syntaxStyle: WorkspaceEditorSyntaxStyle
    var highlights: [WorkspaceDiffEditorHighlight]
    var inlineHighlights: [WorkspaceDiffEditorInlineHighlight]
}

struct WorkspaceTextEditorSearchHighlightSignature: Equatable {
    var contentRevision: Int
    var query: String
    var isSearchCaseSensitive: Bool
    var selectedRange: NSRange
}

struct WorkspaceTextEditorLineMetrics {
    static let gutterMinimumWidth: CGFloat = 44
    static let gutterHorizontalPadding: CGFloat = 10

    static func lineStartOffsets(in content: NSString) -> [Int] {
        guard content.length > 0 else {
            return [0]
        }

        var offsets = [0]
        var index = 0
        while index < content.length {
            let character = content.character(at: index)
            switch character {
            case 0x0A: // \n
                offsets.append(index + 1)
            case 0x0D: // \r or \r\n
                if index + 1 < content.length, content.character(at: index + 1) == 0x0A {
                    offsets.append(index + 2)
                    index += 1
                } else {
                    offsets.append(index + 1)
                }
            default:
                break
            }
            index += 1
        }
        return offsets
    }

    static func lineIndex(
        forCharacterLocation characterLocation: Int,
        lineStartOffsets: [Int]
    ) -> Int {
        guard !lineStartOffsets.isEmpty else {
            return 0
        }

        let clampedLocation = max(0, characterLocation)
        var low = 0
        var high = lineStartOffsets.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStartOffsets[mid] <= clampedLocation {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }

    static func visibleLineRange(
        contentOffsetY: CGFloat,
        viewportHeight: CGFloat,
        insetTop: CGFloat,
        lineHeight: CGFloat,
        totalLineCount: Int
    ) -> ClosedRange<Int>? {
        guard totalLineCount > 0, lineHeight > 0 else {
            return nil
        }

        let start = max(0, Int(floor((contentOffsetY - insetTop) / lineHeight)))
        let end = max(
            start,
            Int(ceil((contentOffsetY + viewportHeight - insetTop) / lineHeight))
        )
        return min(totalLineCount - 1, start)...min(totalLineCount - 1, end)
    }

    static func lineOriginY(
        forLineIndex lineIndex: Int,
        insetTop: CGFloat,
        lineHeight: CGFloat
    ) -> CGFloat {
        insetTop + CGFloat(max(0, lineIndex)) * lineHeight
    }

    static func gutterWidth(
        lineCount: Int,
        font: NSFont
    ) -> CGFloat {
        let digits = max(2, String(max(1, lineCount)).count)
        let sample = String(repeating: "8", count: digits)
        let width = (sample as NSString).size(withAttributes: [.font: font]).width
        return max(gutterMinimumWidth, ceil(width + gutterHorizontalPadding * 2))
    }

    @MainActor
    static func lineHeight(for textView: NSTextView) -> CGFloat {
        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        return textView.layoutManager?.defaultLineHeight(for: font)
            ?? ceil(font.ascender - font.descender + font.leading)
    }
}

enum WorkspaceTextEditorOverviewMarkerKind: Equatable {
    case searchMatch
    case added
    case removed
    case changed
    case conflict
}

struct WorkspaceTextEditorOverviewMarker: Equatable {
    var kind: WorkspaceTextEditorOverviewMarkerKind
    var startFraction: CGFloat
    var endFraction: CGFloat
}

@MainActor
private final class WorkspaceEditorTextView: NSTextView {
    var lineStartOffsets: [Int] = [0] {
        didSet {
            guard lineStartOffsets != oldValue else {
                return
            }
            needsDisplay = true
        }
    }

    var currentLineIndex: Int = 0

    var currentLineBackgroundColor = NSColor(
        calibratedRed: 0.18,
        green: 0.19,
        blue: 0.28,
        alpha: 0.55
    )
    var rightMarginGuideColor = NSColor.white.withAlphaComponent(0.08)
    weak var currentLineHighlightView: NSView?
    var displayOptions = WorkspaceEditorDisplayOptions() {
        didSet {
            guard displayOptions != oldValue else {
                return
            }
            needsDisplay = true
        }
    }

    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting stillSelectingFlag: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        repositionCurrentLineHighlightImmediately()
    }

    func repositionCurrentLineHighlightImmediately() {
        guard let highlightView = currentLineHighlightView,
              displayOptions.highlightsCurrentLine
        else {
            currentLineHighlightView?.isHidden = true
            return
        }
        let lineIndex = WorkspaceTextEditorLineMetrics.lineIndex(
            forCharacterLocation: selectedRange().location,
            lineStartOffsets: lineStartOffsets
        )
        currentLineIndex = lineIndex
        let lineHeight = WorkspaceTextEditorLineMetrics.lineHeight(for: self)
        let lineOriginY = WorkspaceTextEditorLineMetrics.lineOriginY(
            forLineIndex: lineIndex,
            insetTop: textContainerInset.height,
            lineHeight: lineHeight
        )
        let width = max(visibleRect.width, bounds.width)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlightView.frame = NSRect(
            x: 0,
            y: lineOriginY,
            width: width,
            height: lineHeight
        )
        highlightView.isHidden = false
        CATransaction.commit()
        CATransaction.flush()
    }

    override func drawBackground(in rect: NSRect) {
        drawRightMarginGuide(in: rect)
        super.drawBackground(in: rect)
    }

    private func drawRightMarginGuide(in rect: NSRect) {
        guard displayOptions.showsRightMargin,
              let font = font
        else {
            return
        }

        let sampleWidth = ("M" as NSString).size(withAttributes: [.font: font]).width
        guard sampleWidth > 0 else {
            return
        }

        let guideX = textContainerInset.width
            + sampleWidth * CGFloat(displayOptions.rightMarginColumn)
            - 0.5
        guard guideX >= rect.minX, guideX <= rect.maxX else {
            return
        }

        rightMarginGuideColor.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: guideX, y: rect.minY))
        path.line(to: NSPoint(x: guideX, y: rect.maxY))
        path.lineWidth = 1
        path.stroke()
    }
}

@MainActor
final class WorkspaceEditorOverviewBarView: NSView {
    private let trackBackgroundColor = NSColor.white.withAlphaComponent(0.05)
    private let separatorColor = NSColor.white.withAlphaComponent(0.08)
    private let viewportColor = NSColor.white.withAlphaComponent(0.12)
    private let currentLineColor = NSColor.systemBlue.withAlphaComponent(0.75)

    var markers: [WorkspaceTextEditorOverviewMarker] = [] {
        didSet {
            guard markers != oldValue else {
                return
            }
            needsDisplay = true
        }
    }

    var viewportRange: ClosedRange<CGFloat> = 0...1 {
        didSet {
            guard viewportRange != oldValue else {
                return
            }
            needsDisplay = true
        }
    }

    var currentLineFraction: CGFloat = 0 {
        didSet {
            guard currentLineFraction != oldValue else {
                return
            }
            needsDisplay = true
        }
    }

    var onNavigateToFraction: ((CGFloat) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        trackBackgroundColor.setFill()
        bounds.fill()

        drawViewport()
        drawMarkers()
        drawCurrentLineMarker()
        drawSeparator()
    }

    override func mouseDown(with event: NSEvent) {
        navigate(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        navigate(with: event)
    }

    private func navigate(with event: NSEvent) {
        guard bounds.height > 0 else {
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        let fraction = min(max(location.y / bounds.height, 0), 1)
        onNavigateToFraction?(fraction)
    }

    private func drawViewport() {
        let rect = bandRect(for: viewportRange, minimumHeight: 14)
        viewportColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
    }

    private func drawMarkers() {
        for marker in markers {
            let rect = bandRect(for: marker.startFraction...marker.endFraction, minimumHeight: 3)
            color(for: marker.kind).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        }
    }

    private func drawCurrentLineMarker() {
        let rect = bandRect(for: currentLineFraction...currentLineFraction, minimumHeight: 2)
        currentLineColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
    }

    private func drawSeparator() {
        separatorColor.setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: bounds.minX + 0.5, y: bounds.minY))
        separator.line(to: NSPoint(x: bounds.minX + 0.5, y: bounds.maxY))
        separator.lineWidth = 1
        separator.stroke()
    }

    private func bandRect(for range: ClosedRange<CGFloat>, minimumHeight: CGFloat) -> NSRect {
        let clampedLower = min(max(range.lowerBound, 0), 1)
        let clampedUpper = min(max(range.upperBound, clampedLower), 1)
        let x = bounds.minX + 3
        let width = max(2, bounds.width - 6)
        let lowerY = bounds.minY + bounds.height * clampedLower
        let upperY = bounds.minY + bounds.height * clampedUpper
        let rawHeight = max(minimumHeight, upperY - lowerY)
        let availableHeight = max(0, bounds.height - rawHeight)
        let y = min(max(lowerY, bounds.minY), bounds.minY + availableHeight)
        return NSRect(x: x, y: y, width: width, height: rawHeight)
    }

    private func color(for kind: WorkspaceTextEditorOverviewMarkerKind) -> NSColor {
        switch kind {
        case .searchMatch:
            return NSColor.systemYellow.withAlphaComponent(0.9)
        case .added:
            return NSColor.systemGreen.withAlphaComponent(0.9)
        case .removed:
            return NSColor.systemRed.withAlphaComponent(0.9)
        case .changed:
            return NSColor.systemOrange.withAlphaComponent(0.9)
        case .conflict:
            return NSColor.systemPurple.withAlphaComponent(0.9)
        }
    }
}

@MainActor
final class WorkspaceEditorContainerView: NSView {
    private static let overviewBarWidth: CGFloat = 12

    let scrollView: NSScrollView
    let overviewBarView: WorkspaceEditorOverviewBarView

    init(scrollView: NSScrollView, overviewBarView: WorkspaceEditorOverviewBarView) {
        self.scrollView = scrollView
        self.overviewBarView = overviewBarView
        super.init(frame: .zero)
        addSubview(scrollView)
        addSubview(overviewBarView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let barWidth = Self.overviewBarWidth
        let overviewFrame = NSRect(
            x: bounds.maxX - barWidth,
            y: bounds.minY,
            width: barWidth,
            height: bounds.height
        )
        overviewBarView.frame = overviewFrame
        scrollView.frame = NSRect(
            x: bounds.minX,
            y: bounds.minY,
            width: max(0, bounds.width - barWidth),
            height: bounds.height
        )
    }
}

@MainActor
private final class WorkspaceLineNumberRulerView: NSRulerView {
    private weak var editorTextView: WorkspaceEditorTextView?

    private let gutterBackgroundColor = NSColor(
        calibratedRed: 0.10,
        green: 0.11,
        blue: 0.13,
        alpha: 1
    )
    private let separatorColor = NSColor.white.withAlphaComponent(0.06)
    private let textColor = NSColor.white.withAlphaComponent(0.42)
    private let currentLineTextColor = NSColor.white.withAlphaComponent(0.92)
    private let currentLineBackgroundColor = NSColor(
        calibratedRed: 0.19,
        green: 0.20,
        blue: 0.30,
        alpha: 0.72
    )

    private var lineStartOffsets: [Int] = [0]
    private var currentLineIndex = 0
    private var highlightsCurrentLine = true

    init(scrollView: NSScrollView, textView: WorkspaceEditorTextView) {
        self.editorTextView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        update(lineStartOffsets: [0], currentLineIndex: 0, highlightsCurrentLine: true)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        lineStartOffsets: [Int],
        currentLineIndex: Int,
        highlightsCurrentLine: Bool
    ) {
        let normalizedLineStartOffsets = lineStartOffsets.isEmpty ? [0] : lineStartOffsets
        let clampedCurrentLineIndex = max(0, currentLineIndex)
        guard self.lineStartOffsets != normalizedLineStartOffsets
            || self.currentLineIndex != clampedCurrentLineIndex
            || self.highlightsCurrentLine != highlightsCurrentLine
        else {
            return
        }
        self.lineStartOffsets = normalizedLineStartOffsets
        self.currentLineIndex = clampedCurrentLineIndex
        self.highlightsCurrentLine = highlightsCurrentLine
        updateThicknessIfNeeded()
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let scrollView,
              let textView = editorTextView
        else {
            return
        }

        gutterBackgroundColor.setFill()
        bounds.fill()

        let contentOffsetY = scrollView.contentView.bounds.origin.y
        let viewportHeight = scrollView.contentView.bounds.height
        let lineHeight = WorkspaceTextEditorLineMetrics.lineHeight(for: textView)
        let insetTop = textView.textContainerInset.height
        guard let visibleRange = WorkspaceTextEditorLineMetrics.visibleLineRange(
            contentOffsetY: contentOffsetY,
            viewportHeight: viewportHeight,
            insetTop: insetTop,
            lineHeight: lineHeight,
            totalLineCount: lineStartOffsets.count
        ) else {
            drawSeparator()
            return
        }

        let currentLineRect = NSRect(
            x: 0,
            y: WorkspaceTextEditorLineMetrics.lineOriginY(
                forLineIndex: currentLineIndex,
                insetTop: insetTop,
                lineHeight: lineHeight
            ) - contentOffsetY,
            width: bounds.width,
            height: lineHeight
        ).intersection(bounds)
        if highlightsCurrentLine, !currentLineRect.isEmpty {
            currentLineBackgroundColor.setFill()
            currentLineRect.fill()
        }

        for lineIndex in visibleRange {
            let lineOriginY = WorkspaceTextEditorLineMetrics.lineOriginY(
                forLineIndex: lineIndex,
                insetTop: insetTop,
                lineHeight: lineHeight
            ) - contentOffsetY
            let label = "\(lineIndex + 1)"
            let isCurrentLine = highlightsCurrentLine && lineIndex == currentLineIndex
            let font = NSFont.monospacedDigitSystemFont(
                ofSize: 11,
                weight: isCurrentLine ? .semibold : .regular
            )
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: isCurrentLine ? currentLineTextColor : textColor,
            ]
            let labelSize = (label as NSString).size(withAttributes: attributes)
            let labelRect = NSRect(
                x: bounds.width - WorkspaceTextEditorLineMetrics.gutterHorizontalPadding - labelSize.width,
                y: lineOriginY + floor((lineHeight - labelSize.height) / 2),
                width: labelSize.width,
                height: labelSize.height
            )
            (label as NSString).draw(in: labelRect, withAttributes: attributes)
        }

        drawSeparator()
    }

    private func updateThicknessIfNeeded() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let targetThickness = WorkspaceTextEditorLineMetrics.gutterWidth(
            lineCount: lineStartOffsets.count,
            font: font
        )
        guard abs(ruleThickness - targetThickness) > 0.5 else {
            return
        }
        ruleThickness = targetThickness
    }

    private func drawSeparator() {
        separatorColor.setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        separator.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        separator.lineWidth = 1
        separator.stroke()
    }
}

struct WorkspaceTextEditorView: NSViewRepresentable {
    let editorID: String
    @Binding var text: String
    let isEditable: Bool
    let displayOptions: WorkspaceEditorDisplayOptions
    let syntaxStyle: WorkspaceEditorSyntaxStyle
    let highlights: [WorkspaceDiffEditorHighlight]
    let inlineHighlights: [WorkspaceDiffEditorInlineHighlight]
    let searchQuery: String
    let isSearchCaseSensitive: Bool
    let scrollSyncState: Binding<WorkspaceTextEditorScrollSyncState>?
    let scrollRequestState: Binding<WorkspaceTextEditorScrollRequestState>?
    let searchRequestState: Binding<WorkspaceTextEditorSearchRequestState>?
    let selectionText: Binding<String?>?

    init(
        editorID: String,
        text: Binding<String>,
        isEditable: Bool,
        displayOptions: WorkspaceEditorDisplayOptions = .init(),
        syntaxStyle: WorkspaceEditorSyntaxStyle = .plainText,
        highlights: [WorkspaceDiffEditorHighlight] = [],
        inlineHighlights: [WorkspaceDiffEditorInlineHighlight] = [],
        searchQuery: String = "",
        isSearchCaseSensitive: Bool = false,
        scrollSyncState: Binding<WorkspaceTextEditorScrollSyncState>? = nil,
        scrollRequestState: Binding<WorkspaceTextEditorScrollRequestState>? = nil,
        searchRequestState: Binding<WorkspaceTextEditorSearchRequestState>? = nil,
        selectionText: Binding<String?>? = nil
    ) {
        self.editorID = editorID
        self._text = text
        self.isEditable = isEditable
        self.displayOptions = displayOptions
        self.syntaxStyle = syntaxStyle
        self.highlights = highlights
        self.inlineHighlights = inlineHighlights
        self.searchQuery = searchQuery
        self.isSearchCaseSensitive = isSearchCaseSensitive
        self.scrollSyncState = scrollSyncState
        self.scrollRequestState = scrollRequestState
        self.searchRequestState = searchRequestState
        self.selectionText = selectionText
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            editorID: editorID,
            text: $text,
            scrollSyncState: scrollSyncState,
            scrollRequestState: scrollRequestState,
            searchRequestState: searchRequestState,
            selectionText: selectionText
        )
    }

    func makeNSView(context: Context) -> WorkspaceEditorContainerView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = WorkspaceEditorTextView()
        textView.isRichText = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.string = text
        textView.delegate = context.coordinator

        let overviewBarView = WorkspaceEditorOverviewBarView()
        scrollView.documentView = textView
        scrollView.verticalRulerView = WorkspaceLineNumberRulerView(scrollView: scrollView, textView: textView)
        let containerView = WorkspaceEditorContainerView(
            scrollView: scrollView,
            overviewBarView: overviewBarView
        )
        context.coordinator.attach(
            scrollView: scrollView,
            textView: textView,
            overviewBarView: overviewBarView
        )
        context.coordinator.applyDisplayOptionsIfNeeded(displayOptions, to: scrollView, textView: textView, force: true)
        context.coordinator.applyDecorationsIfNeeded(
            syntaxStyle: syntaxStyle,
            highlights: highlights,
            inlineHighlights: inlineHighlights,
            searchQuery: searchQuery,
            isSearchCaseSensitive: isSearchCaseSensitive,
            force: true
        )
        return containerView
    }

    func updateNSView(_ containerView: WorkspaceEditorContainerView, context: Context) {
        let scrollView = containerView.scrollView
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }
        context.coordinator.attach(
            scrollView: scrollView,
            textView: textView,
            overviewBarView: containerView.overviewBarView
        )
        let selectedRanges = textView.selectedRanges
        let textChanged = context.coordinator.applyTextIfNeeded(text, to: textView)
        if textChanged {
            textView.selectedRanges = selectedRanges
        }
        textView.isEditable = isEditable
        context.coordinator.applyDisplayOptionsIfNeeded(displayOptions, to: scrollView, textView: textView, force: textChanged)
        context.coordinator.refreshEditorChrome()
        context.coordinator.applyDecorationsIfNeeded(
            syntaxStyle: syntaxStyle,
            highlights: highlights,
            inlineHighlights: inlineHighlights,
            searchQuery: searchQuery,
            isSearchCaseSensitive: isSearchCaseSensitive,
            force: textChanged
        )
        context.coordinator.applySyncedScrollIfNeeded()
        context.coordinator.scrollToRequestedLineIfNeeded()
        context.coordinator.applySearchRequestIfNeeded()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private static let remoteScrollTolerance: CGFloat = 2
        private static let localScrollEmissionThreshold: CGFloat = 0.01

        private let editorID: String
        private var text: Binding<String>
        private let scrollSyncState: Binding<WorkspaceTextEditorScrollSyncState>?
        private let scrollRequestState: Binding<WorkspaceTextEditorScrollRequestState>?
        private let searchRequestState: Binding<WorkspaceTextEditorSearchRequestState>?
        private let selectionText: Binding<String?>?
        private weak var scrollView: NSScrollView?
        private weak var textView: NSTextView?
        private weak var overviewBarView: WorkspaceEditorOverviewBarView?
        private var currentLineHighlightView: NSView?
        private var isApplyingRemoteScroll = false
        private var lastAppliedRevision = -1
        private var lastAppliedScrollRequestRevision = -1
        private var lastAppliedSearchRequestRevision = -1
        private var lastAppliedDecorationSignature: WorkspaceTextEditorDecorationSignature?
        private var lastAppliedSearchHighlightSignature: WorkspaceTextEditorSearchHighlightSignature?
        private var lastAppliedDisplayOptions: WorkspaceEditorDisplayOptions?
        private var lastProgrammaticScrollOriginY: CGFloat?
        private var lastProgrammaticScrollRevision: Int?
        private var lineStartOffsets: [Int] = [0]
        private var searchContentRevision = 0
        private var latestDisplayOptions = WorkspaceEditorDisplayOptions()
        private var latestSyntaxStyle: WorkspaceEditorSyntaxStyle = .plainText
        private var latestHighlights: [WorkspaceDiffEditorHighlight] = []
        private var latestInlineHighlights: [WorkspaceDiffEditorInlineHighlight] = []
        private var latestSearchQuery = ""
        private var latestSearchCaseSensitive = false

        init(
            editorID: String,
            text: Binding<String>,
            scrollSyncState: Binding<WorkspaceTextEditorScrollSyncState>?,
            scrollRequestState: Binding<WorkspaceTextEditorScrollRequestState>?,
            searchRequestState: Binding<WorkspaceTextEditorSearchRequestState>?,
            selectionText: Binding<String?>?
        ) {
            self.editorID = editorID
            self.text = text
            self.scrollSyncState = scrollSyncState
            self.scrollRequestState = scrollRequestState
            self.searchRequestState = searchRequestState
            self.selectionText = selectionText
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(
            scrollView: NSScrollView,
            textView: NSTextView,
            overviewBarView: WorkspaceEditorOverviewBarView
        ) {
            let scrollViewChanged = self.scrollView !== scrollView
            self.scrollView = scrollView
            self.textView = textView
            self.overviewBarView = overviewBarView
            lineStartOffsets = WorkspaceTextEditorLineMetrics.lineStartOffsets(in: textView.string as NSString)
            overviewBarView.onNavigateToFraction = { [weak self] fraction in
                self?.scrollToOverviewFraction(fraction)
            }
            installCurrentLineHighlightViewIfNeeded(in: scrollView, textView: textView)
            guard scrollViewChanged else {
                refreshEditorChrome()
                updateSelectionText(in: textView)
                return
            }

            NotificationCenter.default.removeObserver(self)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleBoundsDidChangeNotification(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            refreshEditorChrome()
            updateSelectionText(in: textView)
        }

        private func installCurrentLineHighlightViewIfNeeded(
            in scrollView: NSScrollView,
            textView: NSTextView
        ) {
            if let existing = currentLineHighlightView, existing.superview != nil {
                (textView as? WorkspaceEditorTextView)?.currentLineHighlightView = existing
                return
            }
            let highlightView = NSView()
            highlightView.wantsLayer = true
            highlightView.layer?.backgroundColor = NSColor(
                calibratedRed: 0.18,
                green: 0.19,
                blue: 0.28,
                alpha: 0.55
            ).cgColor
            let clipView = scrollView.contentView
            clipView.addSubview(highlightView, positioned: .below, relativeTo: textView)
            currentLineHighlightView = highlightView
            (textView as? WorkspaceEditorTextView)?.currentLineHighlightView = highlightView
        }

        func applyTextIfNeeded(_ text: String, to textView: NSTextView) -> Bool {
            guard textView.string != text else {
                return false
            }
            textView.string = text
            lineStartOffsets = WorkspaceTextEditorLineMetrics.lineStartOffsets(in: text as NSString)
            searchContentRevision += 1
            lastAppliedDecorationSignature = nil
            lastAppliedSearchHighlightSignature = nil
            refreshEditorChrome()
            return true
        }

        func applyDecorationsIfNeeded(
            syntaxStyle: WorkspaceEditorSyntaxStyle,
            highlights: [WorkspaceDiffEditorHighlight],
            inlineHighlights: [WorkspaceDiffEditorInlineHighlight],
            searchQuery: String,
            isSearchCaseSensitive: Bool,
            force: Bool
        ) {
            guard let textView else {
                return
            }
            latestSyntaxStyle = syntaxStyle
            latestHighlights = highlights
            latestInlineHighlights = inlineHighlights
            latestSearchQuery = searchQuery
            latestSearchCaseSensitive = isSearchCaseSensitive
            let signature = WorkspaceTextEditorDecorationSignature(
                text: textView.string,
                syntaxStyle: syntaxStyle,
                highlights: highlights,
                inlineHighlights: inlineHighlights
            )
            guard force || lastAppliedDecorationSignature != signature else {
                applySearchHighlightsIfNeeded(force: force)
                return
            }

            applyTextPresentation(
                syntaxStyle: syntaxStyle,
                highlights: highlights,
                inlineHighlights: inlineHighlights,
                to: textView
            )
            lastAppliedDecorationSignature = signature
            lastAppliedSearchHighlightSignature = nil
            applySearchHighlightsIfNeeded(force: true)
            refreshEditorChrome(redrawTextView: false)
        }

        func applyDisplayOptionsIfNeeded(
            _ options: WorkspaceEditorDisplayOptions,
            to scrollView: NSScrollView,
            textView: NSTextView,
            force: Bool
        ) {
            latestDisplayOptions = options
            guard force || lastAppliedDisplayOptions != options else {
                return
            }
            configureDisplayOptions(options, in: scrollView, textView: textView)
            lastAppliedDisplayOptions = options
        }

        private func reapplyStoredDecorations(force: Bool) {
            applyDecorationsIfNeeded(
                syntaxStyle: latestSyntaxStyle,
                highlights: latestHighlights,
                inlineHighlights: latestInlineHighlights,
                searchQuery: latestSearchQuery,
                isSearchCaseSensitive: latestSearchCaseSensitive,
                force: force
            )
            applySearchHighlightsIfNeeded(force: force)
        }

        private func configureDisplayOptions(
            _ options: WorkspaceEditorDisplayOptions,
            in scrollView: NSScrollView,
            textView: NSTextView
        ) {
            scrollView.hasVerticalRuler = options.showsLineNumbers
            scrollView.rulersVisible = options.showsLineNumbers
            scrollView.hasHorizontalScroller = !options.usesSoftWraps

            textView.isHorizontallyResizable = !options.usesSoftWraps
            textView.textContainer?.widthTracksTextView = options.usesSoftWraps
            textView.textContainer?.containerSize = NSSize(
                width: options.usesSoftWraps
                    ? max(scrollView.contentSize.width, 0)
                    : CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.layoutManager?.showsInvisibleCharacters = options.showsWhitespaceCharacters

            if let editorTextView = textView as? WorkspaceEditorTextView {
                editorTextView.displayOptions = options
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            if text.wrappedValue != textView.string {
                text.wrappedValue = textView.string
            }
            lineStartOffsets = WorkspaceTextEditorLineMetrics.lineStartOffsets(in: textView.string as NSString)
            searchContentRevision += 1
            lastAppliedDecorationSignature = nil
            lastAppliedSearchHighlightSignature = nil
            refreshEditorChrome()
            updateSelectionText(in: textView)
            reapplyStoredDecorations(force: true)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            refreshEditorChrome()
            if let textView = notification.object as? NSTextView {
                updateSelectionText(in: textView)
            }
            applySearchHighlightsIfNeeded(force: false)
        }

        func applySyncedScrollIfNeeded() {
            guard let scrollView,
                  let scrollSyncState,
                  scrollSyncState.wrappedValue.sourceID != editorID,
                  scrollSyncState.wrappedValue.revision != lastAppliedRevision
            else {
                return
            }

            isApplyingRemoteScroll = true
            lastAppliedRevision = scrollSyncState.wrappedValue.revision
            let clipView = scrollView.contentView
            let targetY = maxVerticalOffset(for: scrollView) * scrollSyncState.wrappedValue.normalizedYOffset
            if abs(clipView.bounds.origin.y - targetY) < Self.remoteScrollTolerance {
                isApplyingRemoteScroll = false
                lastProgrammaticScrollOriginY = nil
                lastProgrammaticScrollRevision = nil
                return
            }
            var origin = clipView.bounds.origin
            origin.y = targetY
            lastProgrammaticScrollOriginY = targetY
            lastProgrammaticScrollRevision = scrollSyncState.wrappedValue.revision
            clipView.scroll(to: origin)
            scrollView.reflectScrolledClipView(clipView)
        }

        func scrollToRequestedLineIfNeeded() {
            guard let scrollRequestState,
                  scrollRequestState.wrappedValue.revision != lastAppliedScrollRequestRevision,
                  let targetLine = scrollRequestState.wrappedValue.lineTargets[editorID]
            else {
                return
            }

            lastAppliedScrollRequestRevision = scrollRequestState.wrappedValue.revision
            guard let textView else {
                return
            }

            let content = textView.string as NSString
            guard let location = lineStartLocation(for: targetLine, in: content) else {
                return
            }

            isApplyingRemoteScroll = true
            textView.scrollRangeToVisible(NSRange(location: location, length: 0))
            if let scrollView {
                lastProgrammaticScrollOriginY = scrollView.contentView.bounds.origin.y
                lastProgrammaticScrollRevision = scrollRequestState.wrappedValue.revision
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        func applySearchRequestIfNeeded() {
            guard let searchRequestState,
                  searchRequestState.wrappedValue.revision != lastAppliedSearchRequestRevision
            else {
                return
            }

            lastAppliedSearchRequestRevision = searchRequestState.wrappedValue.revision
            guard let textView else {
                return
            }

            let request = searchRequestState.wrappedValue
            let content = textView.string as NSString
            switch request.kind {
            case .revealSearch:
                reapplyStoredDecorations(force: false)
            case .findNext:
                guard let match = workspaceTextEditorNextMatch(
                    query: request.query,
                    in: content,
                    selectedRange: textView.selectedRange(),
                    isCaseSensitive: request.isCaseSensitive
                ) else {
                    NSSound.beep()
                    return
                }
                selectAndReveal(range: match, in: textView)
            case .findPrevious:
                guard let match = workspaceTextEditorPreviousMatch(
                    query: request.query,
                    in: content,
                    selectedRange: textView.selectedRange(),
                    isCaseSensitive: request.isCaseSensitive
                ) else {
                    NSSound.beep()
                    return
                }
                selectAndReveal(range: match, in: textView)
            case .replaceCurrent:
                replaceCurrentMatch(using: request, in: textView)
            case .replaceAll:
                replaceAllMatches(using: request, in: textView)
            case .goToLine:
                guard let targetLine = request.targetLine,
                      let location = lineStartLocation(for: targetLine, in: content)
                else {
                    NSSound.beep()
                    return
                }
                selectAndReveal(range: NSRange(location: location, length: 0), in: textView)
            }
        }

        private func replaceCurrentMatch(
            using request: WorkspaceTextEditorSearchRequestState,
            in textView: NSTextView
        ) {
            let content = textView.string as NSString
            guard !request.query.isEmpty else {
                NSSound.beep()
                return
            }

            let replacementRange: NSRange
            if workspaceTextEditorRangeMatchesQuery(
                textView.selectedRange(),
                query: request.query,
                in: content,
                isCaseSensitive: request.isCaseSensitive
            ) {
                replacementRange = textView.selectedRange()
            } else if let match = workspaceTextEditorNextMatch(
                query: request.query,
                in: content,
                selectedRange: textView.selectedRange(),
                isCaseSensitive: request.isCaseSensitive
            ) {
                replacementRange = match
            } else {
                NSSound.beep()
                return
            }

            replace(range: replacementRange, with: request.replacement, in: textView)
        }

        private func replaceAllMatches(
            using request: WorkspaceTextEditorSearchRequestState,
            in textView: NSTextView
        ) {
            let content = textView.string as NSString
            let replaced = workspaceTextEditorReplaceAll(
                query: request.query,
                replacement: request.replacement,
                in: content,
                isCaseSensitive: request.isCaseSensitive
            )
            guard replaced.replacementCount > 0 else {
                NSSound.beep()
                return
            }

            textView.string = replaced.text
            text.wrappedValue = replaced.text
            lineStartOffsets = WorkspaceTextEditorLineMetrics.lineStartOffsets(in: replaced.text as NSString)
            let selectionLocation = min(replaced.firstReplacementLocation ?? 0, (replaced.text as NSString).length)
            textView.setSelectedRange(NSRange(location: selectionLocation, length: 0))
            textView.scrollRangeToVisible(NSRange(location: selectionLocation, length: 0))
            lastAppliedDecorationSignature = nil
            refreshEditorChrome()
            reapplyStoredDecorations(force: true)
        }

        private func replace(range: NSRange, with replacement: String, in textView: NSTextView) {
            guard let textStorage = textView.textStorage else {
                return
            }
            textStorage.replaceCharacters(in: range, with: replacement)
            if text.wrappedValue != textView.string {
                text.wrappedValue = textView.string
            }
            let selectionRange = NSRange(location: range.location, length: (replacement as NSString).length)
            textView.setSelectedRange(selectionRange)
            textView.scrollRangeToVisible(selectionRange)
            lineStartOffsets = WorkspaceTextEditorLineMetrics.lineStartOffsets(in: textView.string as NSString)
            lastAppliedDecorationSignature = nil
            refreshEditorChrome()
            reapplyStoredDecorations(force: true)
        }

        private func selectAndReveal(range: NSRange, in textView: NSTextView) {
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            refreshEditorChrome()
            reapplyStoredDecorations(force: false)
        }

        @objc
        private func handleBoundsDidChangeNotification(_ notification: Notification) {
            handleBoundsDidChange()
        }

        private func handleBoundsDidChange() {
            guard let scrollView else {
                return
            }
            if latestDisplayOptions.usesSoftWraps,
               let textView {
                textView.textContainer?.containerSize.width = max(scrollView.contentSize.width, 0)
            }
            guard let scrollSyncState else {
                refreshEditorChrome(redrawTextView: false)
                return
            }
            let currentOriginY = scrollView.contentView.bounds.origin.y
            let currentState = scrollSyncState.wrappedValue
            refreshEditorChrome(redrawTextView: false)

            if let lastProgrammaticScrollRevision,
               let lastProgrammaticScrollOriginY,
               (currentState.revision == lastProgrammaticScrollRevision
                || scrollRequestState?.wrappedValue.revision == lastProgrammaticScrollRevision),
               abs(currentOriginY - lastProgrammaticScrollOriginY) < Self.remoteScrollTolerance
            {
                isApplyingRemoteScroll = false
                return
            }

            if isApplyingRemoteScroll {
                isApplyingRemoteScroll = false
                lastProgrammaticScrollOriginY = nil
                lastProgrammaticScrollRevision = nil
                return
            }

            let normalizedYOffset = normalizedYOffset(for: scrollView)
            if currentState.sourceID == editorID,
               abs(currentState.normalizedYOffset - normalizedYOffset) < Self.localScrollEmissionThreshold
            {
                return
            }
            if currentState.sourceID != editorID,
               abs(currentState.normalizedYOffset - normalizedYOffset) < Self.localScrollEmissionThreshold
            {
                lastProgrammaticScrollOriginY = nil
                lastProgrammaticScrollRevision = nil
                isApplyingRemoteScroll = false
                return
            }
            lastProgrammaticScrollOriginY = nil
            lastProgrammaticScrollRevision = nil
            scrollSyncState.wrappedValue = WorkspaceTextEditorScrollSyncState(
                sourceID: editorID,
                normalizedYOffset: normalizedYOffset,
                revision: currentState.revision + 1
            )
        }

        private func normalizedYOffset(for scrollView: NSScrollView) -> CGFloat {
            let maxOffset = maxVerticalOffset(for: scrollView)
            guard maxOffset > 0 else {
                return 0
            }
            return min(max(scrollView.contentView.bounds.origin.y / maxOffset, 0), 1)
        }

        private func maxVerticalOffset(for scrollView: NSScrollView) -> CGFloat {
            let documentHeight = scrollView.documentView?.frame.height ?? 0
            let visibleHeight = scrollView.contentView.bounds.height
            return max(0, documentHeight - visibleHeight)
        }

        func refreshEditorChrome(
            redrawTextView: Bool = true,
            forceImmediateDisplay: Bool = false
        ) {
            guard let scrollView,
                  let textView = textView as? WorkspaceEditorTextView
            else {
                return
            }

            let currentLineIndex = WorkspaceTextEditorLineMetrics.lineIndex(
                forCharacterLocation: textView.selectedRange().location,
                lineStartOffsets: lineStartOffsets
            )
            textView.lineStartOffsets = lineStartOffsets
            textView.currentLineIndex = currentLineIndex

            repositionCurrentLineHighlight(
                lineIndex: currentLineIndex,
                textView: textView,
                scrollView: scrollView
            )

            (scrollView.verticalRulerView as? WorkspaceLineNumberRulerView)?
                .update(
                    lineStartOffsets: lineStartOffsets,
                    currentLineIndex: currentLineIndex,
                    highlightsCurrentLine: latestDisplayOptions.highlightsCurrentLine
                )
            refreshOverviewBar(
                currentLineIndex: currentLineIndex,
                scrollView: scrollView
            )

            guard forceImmediateDisplay else {
                return
            }
            scrollView.verticalRulerView?.displayIfNeeded()
            overviewBarView?.displayIfNeeded()
        }

        private func repositionCurrentLineHighlight(
            lineIndex: Int,
            textView: NSTextView,
            scrollView: NSScrollView
        ) {
            guard let highlightView = currentLineHighlightView,
                  latestDisplayOptions.highlightsCurrentLine
            else {
                currentLineHighlightView?.isHidden = true
                return
            }
            let lineHeight = WorkspaceTextEditorLineMetrics.lineHeight(for: textView)
            let lineOriginY = WorkspaceTextEditorLineMetrics.lineOriginY(
                forLineIndex: lineIndex,
                insetTop: textView.textContainerInset.height,
                lineHeight: lineHeight
            )
            let clipView = scrollView.contentView
            // Use a large width to cover any horizontal scroll position.
            let width = max(clipView.bounds.width, textView.bounds.width)
            highlightView.frame = NSRect(
                x: 0,
                y: lineOriginY,
                width: width,
                height: lineHeight
            )
            highlightView.isHidden = false
        }

        private func updateSelectionText(in textView: NSTextView) {
            guard let selectionText else {
                return
            }
            let selectedRange = textView.selectedRange()
            guard selectedRange.location != NSNotFound,
                  selectedRange.length > 0,
                  let content = textView.string as NSString?
            else {
                if selectionText.wrappedValue != nil {
                    selectionText.wrappedValue = nil
                }
                return
            }
            let newValue = content.substring(with: selectedRange)
            if selectionText.wrappedValue != newValue {
                selectionText.wrappedValue = newValue
            }
        }

        private func applySearchHighlightsIfNeeded(force: Bool) {
            guard let textView else {
                return
            }
            let signature = workspaceTextEditorEffectiveSearchHighlightSignature(
                contentRevision: searchContentRevision,
                query: latestSearchQuery,
                isCaseSensitive: latestSearchCaseSensitive,
                selectedRange: textView.selectedRange()
            )
            guard force || lastAppliedSearchHighlightSignature != signature else {
                return
            }
            applyTemporarySearchHighlights(
                query: latestSearchQuery,
                isCaseSensitive: latestSearchCaseSensitive,
                selectedRange: textView.selectedRange(),
                to: textView
            )
            lastAppliedSearchHighlightSignature = signature
        }

        private func refreshOverviewBar(
            currentLineIndex: Int,
            scrollView: NSScrollView
        ) {
            guard let overviewBarView,
                  let content = textView?.string as NSString?
            else {
                return
            }

            overviewBarView.markers = workspaceTextEditorOverviewMarkers(
                highlights: latestHighlights,
                searchQuery: latestSearchQuery,
                in: content,
                lineStartOffsets: lineStartOffsets,
                isSearchCaseSensitive: latestSearchCaseSensitive
            )
            overviewBarView.currentLineFraction = workspaceTextEditorNormalizedLineFraction(
                lineIndex: currentLineIndex,
                totalLineCount: lineStartOffsets.count
            )
            overviewBarView.viewportRange = workspaceTextEditorViewportRange(for: scrollView)
        }

        private func scrollToOverviewFraction(_ fraction: CGFloat) {
            guard let scrollView else {
                return
            }
            let maxOffset = maxVerticalOffset(for: scrollView)
            var origin = scrollView.contentView.bounds.origin
            origin.y = maxOffset * min(max(fraction, 0), 1)
            isApplyingRemoteScroll = true
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            refreshEditorChrome(redrawTextView: false)
        }
    }
}

@MainActor
private func applyTextPresentation(
    syntaxStyle: WorkspaceEditorSyntaxStyle,
    highlights: [WorkspaceDiffEditorHighlight],
    inlineHighlights: [WorkspaceDiffEditorInlineHighlight],
    to textView: NSTextView
) {
    guard let textStorage = textView.textStorage else {
        return
    }
    let content = textView.string as NSString
    let fullRange = NSRange(location: 0, length: content.length)
    textStorage.beginEditing()
    textStorage.setAttributes(
        [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ],
        range: fullRange
    )

    applySyntaxHighlighting(
        syntaxStyle: syntaxStyle,
        textStorage: textStorage,
        content: content
    )

    for highlight in highlights {
        let range = characterRange(for: highlight.lineRange, in: content)
        guard range.location != NSNotFound, range.length > 0 else {
            continue
        }
        textStorage.addAttribute(
            .backgroundColor,
            value: highlightColor(for: highlight.kind),
            range: range
        )
    }
    for inlineHighlight in inlineHighlights {
        let range = characterRange(
            forLineIndex: inlineHighlight.lineIndex,
            inlineRange: inlineHighlight.range,
            in: content
        )
        guard range.location != NSNotFound, range.length > 0 else {
            continue
        }
        textStorage.addAttribute(
            .backgroundColor,
            value: inlineHighlightColor(for: inlineHighlight.kind),
            range: range
        )
    }
    textStorage.endEditing()
}

@MainActor
private func applySyntaxHighlighting(
    syntaxStyle: WorkspaceEditorSyntaxStyle,
    textStorage: NSTextStorage,
    content: NSString
) {
    guard syntaxStyle != .plainText else {
        return
    }

    let fullString = content as String
    let fullRange = NSRange(location: 0, length: content.length)

    let apply: (String, NSRegularExpression.Options, NSColor) -> Void = { pattern, options, color in
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return
        }
        expression.enumerateMatches(in: fullString, options: [], range: fullRange) { result, _, _ in
            guard let range = result?.range, range.location != NSNotFound else {
                return
            }
            textStorage.addAttribute(.foregroundColor, value: color, range: range)
        }
    }

    switch syntaxStyle {
    case .swift:
        apply(#"\b(import|struct|class|actor|enum|protocol|extension|func|let|var|if|else|guard|return|switch|case|for|while|in|where|break|continue|throw|throws|try|catch|async|await|public|private|fileprivate|internal|open|static|mutating|nonmutating|self|super|nil|true|false)\b"#, [], NSColor.systemPurple)
        apply(#""([^"\\]|\\.)*""#, [], NSColor.systemRed)
        apply(#"//.*"#, [.anchorsMatchLines], NSColor.systemGreen)
        apply(#"/\*[\s\S]*?\*/"#, [.dotMatchesLineSeparators], NSColor.systemGreen)
    case .objectiveC, .cpp, .csharp:
        apply(#"\b(import|include|namespace|using|class|struct|interface|enum|protocol|template|public|protected|private|internal|static|const|readonly|virtual|override|final|abstract|sealed|extends|implements|return|if|else|switch|case|default|for|while|do|break|continue|throw|throws|try|catch|finally|new|null|true|false|this|self|super)\b"#, [], NSColor.systemPurple)
        apply(#"@\"([^\"\\]|\\.)*\""#, [], NSColor.systemRed)
        apply(#""([^"\\]|\\.)*""#, [], NSColor.systemRed)
        apply(#"'([^'\\]|\\.)*'"#, [], NSColor.systemRed)
        apply(#"//.*"#, [.anchorsMatchLines], NSColor.systemGreen)
        apply(#"/\*[\s\S]*?\*/"#, [.dotMatchesLineSeparators], NSColor.systemGreen)
        apply(#"\b\d+(\.\d+)?\b"#, [], NSColor.systemOrange)
    case .json:
        apply(#""([^"\\]|\\.)*"\s*:"# , [], NSColor.systemBlue)
        apply(#""([^"\\]|\\.)*""#, [], NSColor.systemRed)
        apply(#"\b(true|false|null)\b"#, [], NSColor.systemPurple)
        apply(#"-?\b\d+(\.\d+)?\b"#, [], NSColor.systemOrange)
    case .markdown:
        apply(#"^#{1,6}.*$"#, [.anchorsMatchLines], NSColor.systemBlue)
        apply(#"`[^`\n]+`"#, [], NSColor.systemRed)
        apply(#"^\s*[-*+]\s.*$"#, [.anchorsMatchLines], NSColor.systemOrange)
        apply(#"\[[^\]]+\]\([^)]+\)"#, [], NSColor.systemPurple)
    case .yaml:
        apply(#"^[\t ]*[-]?\s*[A-Za-z0-9_.\"'-]+\s*:"# , [.anchorsMatchLines], NSColor.systemBlue)
        apply(#""([^"\\]|\\.)*""#, [], NSColor.systemRed)
        apply(#"\b(true|false|null|yes|no|on|off)\b"#, [], NSColor.systemPurple)
    case .shell:
        apply(#"(^|\s)(if|then|else|elif|fi|for|while|do|done|case|esac|function|select|in|export|local|readonly|return)\b"#, [.anchorsMatchLines], NSColor.systemPurple)
        apply(#"\$[A-Za-z_][A-Za-z0-9_]*"#, [], NSColor.systemBlue)
        apply(#""([^"\\]|\\.)*""#, [], NSColor.systemRed)
        apply(#"'[^']*'"#, [], NSColor.systemRed)
        apply(#"#.*"#, [.anchorsMatchLines], NSColor.systemGreen)
    case .xml, .html:
        apply(#"</?[A-Za-z_:][A-Za-z0-9:._-]*"#, [], NSColor.systemBlue)
        apply(#"\s[A-Za-z_:][A-Za-z0-9:._-]*(?==)"#, [], NSColor.systemPurple)
        apply(#""([^"\\]|\\.)*""#, [], NSColor.systemRed)
        apply(#"<!--[\s\S]*?-->"#, [.dotMatchesLineSeparators], NSColor.systemGreen)
    case .css:
        apply(#"[.#]?[A-Za-z_-][A-Za-z0-9_-]*(?=\s*\{)"#, [], NSColor.systemBlue)
        apply(#"[A-Za-z-]+(?=\s*:)"#, [], NSColor.systemPurple)
        apply(#"#[0-9A-Fa-f]{3,8}\b"#, [], NSColor.systemRed)
        apply(#"\b\d+(\.\d+)?(px|em|rem|vh|vw|%)?\b"#, [], NSColor.systemOrange)
        apply(#"/\*[\s\S]*?\*/"#, [.dotMatchesLineSeparators], NSColor.systemGreen)
    case .javascript, .typescript, .java, .kotlin:
        apply(#"\b(import|export|from|class|interface|enum|extends|implements|function|fun|const|let|var|if|else|switch|case|for|while|do|return|break|continue|try|catch|finally|throw|throws|async|await|new|public|private|protected|internal|static|final|open|override|package|null|true|false|this|super|val)\b"#, [], NSColor.systemPurple)
        apply(#""([^"\\]|\\.)*""#, [], NSColor.systemRed)
        apply(#"'([^'\\]|\\.)*'"#, [], NSColor.systemRed)
        apply(#"//.*"#, [.anchorsMatchLines], NSColor.systemGreen)
        apply(#"/\*[\s\S]*?\*/"#, [.dotMatchesLineSeparators], NSColor.systemGreen)
        apply(#"\b\d+(\.\d+)?\b"#, [], NSColor.systemOrange)
    case .python, .ruby:
        apply(#"\b(import|from|class|def|module|end|return|if|elif|else|unless|case|when|for|while|break|next|continue|raise|begin|rescue|ensure|finally|with|as|lambda|yield|async|await|self|super|None|True|False|nil|true|false)\b"#, [], NSColor.systemPurple)
        apply(#"\"\"\"[\s\S]*?\"\"\""#, [.dotMatchesLineSeparators], NSColor.systemRed)
        apply(#"'''[\s\S]*?'''"#, [.dotMatchesLineSeparators], NSColor.systemRed)
        apply(#""([^"\\]|\\.)*""#, [], NSColor.systemRed)
        apply(#"'([^'\\]|\\.)*'"#, [], NSColor.systemRed)
        apply(#"#.*"#, [.anchorsMatchLines], NSColor.systemGreen)
    case .go, .rust:
        apply(#"\b(package|import|struct|interface|enum|impl|trait|fn|func|let|var|const|mut|pub|return|if|else|match|switch|case|for|while|loop|break|continue|defer|go|select|chan|range|try|catch|throw|new|nil|true|false|self|Self)\b"#, [], NSColor.systemPurple)
        apply(#"`[^`]*`"#, [], NSColor.systemRed)
        apply(#""([^"\\]|\\.)*""#, [], NSColor.systemRed)
        apply(#"'([^'\\]|\\.)*'"#, [], NSColor.systemRed)
        apply(#"//.*"#, [.anchorsMatchLines], NSColor.systemGreen)
        apply(#"/\*[\s\S]*?\*/"#, [.dotMatchesLineSeparators], NSColor.systemGreen)
        apply(#"\b\d+(\.\d+)?\b"#, [], NSColor.systemOrange)
    case .properties:
        apply(#"^[A-Za-z0-9_.-]+\s*(?==|:)"#, [.anchorsMatchLines], NSColor.systemBlue)
        apply(#"(?<==|:).*"#, [.anchorsMatchLines], NSColor.systemRed)
        apply(#"^\s*[#!].*$"#, [.anchorsMatchLines], NSColor.systemGreen)
    case .sql:
        apply(#"\b(SELECT|FROM|WHERE|GROUP|BY|ORDER|HAVING|LIMIT|OFFSET|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|ALTER|DROP|TABLE|INDEX|VIEW|JOIN|LEFT|RIGHT|INNER|OUTER|ON|AND|OR|NOT|NULL|TRUE|FALSE|AS|DISTINCT|UNION|ALL|CASE|WHEN|THEN|ELSE|END)\b"#, [.caseInsensitive], NSColor.systemPurple)
        apply(#""([^"\\]|\\.)*""#, [], NSColor.systemRed)
        apply(#"'([^'\\]|\\.)*'"#, [], NSColor.systemRed)
        apply(#"--.*"#, [.anchorsMatchLines], NSColor.systemGreen)
        apply(#"/\*[\s\S]*?\*/"#, [.dotMatchesLineSeparators], NSColor.systemGreen)
    case .plainText:
        break
    }
}

private func highlightColor(for kind: WorkspaceDiffEditorHighlightKind) -> NSColor {
    switch kind {
    case .added:
        return NSColor.systemGreen.withAlphaComponent(0.16)
    case .removed:
        return NSColor.systemRed.withAlphaComponent(0.14)
    case .changed:
        return NSColor.systemYellow.withAlphaComponent(0.20)
    case .conflict:
        return NSColor.systemOrange.withAlphaComponent(0.20)
    }
}

private func inlineHighlightColor(for kind: WorkspaceDiffEditorHighlightKind) -> NSColor {
    switch kind {
    case .added:
        return NSColor.systemGreen.withAlphaComponent(0.28)
    case .removed:
        return NSColor.systemRed.withAlphaComponent(0.24)
    case .changed:
        return NSColor.systemYellow.withAlphaComponent(0.34)
    case .conflict:
        return NSColor.systemOrange.withAlphaComponent(0.34)
    }
}

func workspaceTextEditorEffectiveSearchHighlightSignature(
    contentRevision: Int,
    query: String,
    isCaseSensitive: Bool,
    selectedRange: NSRange
) -> WorkspaceTextEditorSearchHighlightSignature {
    guard !query.isEmpty else {
        return WorkspaceTextEditorSearchHighlightSignature(
            contentRevision: 0,
            query: "",
            isSearchCaseSensitive: false,
            selectedRange: NSRange(location: NSNotFound, length: 0)
        )
    }
    return WorkspaceTextEditorSearchHighlightSignature(
        contentRevision: contentRevision,
        query: query,
        isSearchCaseSensitive: isCaseSensitive,
        selectedRange: selectedRange
    )
}

@MainActor
private func applyTemporarySearchHighlights(
    query: String,
    isCaseSensitive: Bool,
    selectedRange: NSRange,
    to textView: NSTextView
) {
    guard let layoutManager = textView.layoutManager else {
        return
    }

    let content = textView.string as NSString
    let fullRange = NSRange(location: 0, length: content.length)
    layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

    guard !query.isEmpty else {
        return
    }

    let matches = workspaceTextEditorMatchRanges(
        query: query,
        in: content,
        isCaseSensitive: isCaseSensitive
    )
    for match in matches {
        layoutManager.addTemporaryAttribute(
            .backgroundColor,
            value: workspaceTextEditorRangeMatchesQuery(
                selectedRange,
                query: query,
                in: content,
                isCaseSensitive: isCaseSensitive
            ) && NSEqualRanges(match, selectedRange)
                ? NSColor.systemOrange.withAlphaComponent(0.42)
                : NSColor.systemYellow.withAlphaComponent(0.22),
            forCharacterRange: match
        )
    }
}

func workspaceTextEditorMatchRanges(
    query: String,
    in content: NSString,
    isCaseSensitive: Bool
) -> [NSRange] {
    guard !query.isEmpty, content.length > 0 else {
        return []
    }

    let options: NSString.CompareOptions = isCaseSensitive ? [] : [.caseInsensitive]
    var ranges: [NSRange] = []
    var searchLocation = 0
    while searchLocation <= content.length {
        let remainingLength = content.length - searchLocation
        let searchRange = NSRange(location: searchLocation, length: max(0, remainingLength))
        let match = content.range(of: query, options: options, range: searchRange)
        guard match.location != NSNotFound, match.length > 0 else {
            break
        }
        ranges.append(match)
        searchLocation = match.location + max(match.length, 1)
    }
    return ranges
}

func workspaceTextEditorRangeMatchesQuery(
    _ range: NSRange,
    query: String,
    in content: NSString,
    isCaseSensitive: Bool
) -> Bool {
    guard !query.isEmpty,
          range.location != NSNotFound,
          range.length == (query as NSString).length,
          NSMaxRange(range) <= content.length
    else {
        return false
    }
    let candidate = content.substring(with: range)
    if isCaseSensitive {
        return candidate == query
    }
    return candidate.caseInsensitiveCompare(query) == .orderedSame
}

func workspaceTextEditorNextMatch(
    query: String,
    in content: NSString,
    selectedRange: NSRange,
    isCaseSensitive: Bool
) -> NSRange? {
    let matches = workspaceTextEditorMatchRanges(
        query: query,
        in: content,
        isCaseSensitive: isCaseSensitive
    )
    guard !matches.isEmpty else {
        return nil
    }

    let anchor = workspaceTextEditorRangeMatchesQuery(
        selectedRange,
        query: query,
        in: content,
        isCaseSensitive: isCaseSensitive
    ) ? NSMaxRange(selectedRange) : max(0, selectedRange.location)
    if let next = matches.first(where: { $0.location >= anchor }) {
        return next
    }
    return matches.first
}

func workspaceTextEditorPreviousMatch(
    query: String,
    in content: NSString,
    selectedRange: NSRange,
    isCaseSensitive: Bool
) -> NSRange? {
    let matches = workspaceTextEditorMatchRanges(
        query: query,
        in: content,
        isCaseSensitive: isCaseSensitive
    )
    guard !matches.isEmpty else {
        return nil
    }

    let anchor = workspaceTextEditorRangeMatchesQuery(
        selectedRange,
        query: query,
        in: content,
        isCaseSensitive: isCaseSensitive
    ) ? selectedRange.location : max(0, selectedRange.location)
    if let previous = matches.last(where: { NSMaxRange($0) <= anchor }) {
        return previous
    }
    return matches.last
}

func workspaceTextEditorReplaceAll(
    query: String,
    replacement: String,
    in content: NSString,
    isCaseSensitive: Bool
) -> (text: String, replacementCount: Int, firstReplacementLocation: Int?) {
    let matches = workspaceTextEditorMatchRanges(
        query: query,
        in: content,
        isCaseSensitive: isCaseSensitive
    )
    guard !matches.isEmpty else {
        return (content as String, 0, nil)
    }

    let source = content as String
    let mutable = NSMutableString(string: source)
    var offset = 0
    for match in matches {
        let adjusted = NSRange(location: match.location + offset, length: match.length)
        mutable.replaceCharacters(in: adjusted, with: replacement)
        offset += (replacement as NSString).length - match.length
    }
    return (mutable as String, matches.count, matches.first?.location)
}

func workspaceTextEditorOverviewMarkers(
    highlights: [WorkspaceDiffEditorHighlight],
    searchQuery: String,
    in content: NSString,
    lineStartOffsets: [Int],
    isSearchCaseSensitive: Bool
) -> [WorkspaceTextEditorOverviewMarker] {
    let totalLineCount = max(1, lineStartOffsets.count)
    var markers = highlights.compactMap { highlight in
        workspaceTextEditorOverviewMarker(
            kind: overviewMarkerKind(for: highlight.kind),
            lineRange: highlight.lineRange,
            totalLineCount: totalLineCount
        )
    }

    let searchMatches = workspaceTextEditorMatchRanges(
        query: searchQuery,
        in: content,
        isCaseSensitive: isSearchCaseSensitive
    )
    markers.append(contentsOf: searchMatches.compactMap { range in
        let lineIndex = WorkspaceTextEditorLineMetrics.lineIndex(
            forCharacterLocation: range.location,
            lineStartOffsets: lineStartOffsets
        )
        return workspaceTextEditorOverviewMarker(
            kind: .searchMatch,
            lineRange: WorkspaceDiffLineRange(startLine: lineIndex, lineCount: 1),
            totalLineCount: totalLineCount
        )
    })
    return markers
}

func workspaceTextEditorNormalizedLineFraction(
    lineIndex: Int,
    totalLineCount: Int
) -> CGFloat {
    let denominator = max(1, totalLineCount)
    return min(max(CGFloat(max(0, lineIndex)) / CGFloat(denominator), 0), 1)
}

@MainActor
func workspaceTextEditorViewportRange(for scrollView: NSScrollView) -> ClosedRange<CGFloat> {
    let documentHeight = max(scrollView.documentView?.frame.height ?? 0, 1)
    let visibleRect = scrollView.contentView.bounds
    let lower = min(max(visibleRect.minY / documentHeight, 0), 1)
    let upper = min(max(visibleRect.maxY / documentHeight, lower), 1)
    return lower...upper
}

private func workspaceTextEditorOverviewMarker(
    kind: WorkspaceTextEditorOverviewMarkerKind,
    lineRange: WorkspaceDiffLineRange,
    totalLineCount: Int
) -> WorkspaceTextEditorOverviewMarker? {
    guard totalLineCount > 0 else {
        return nil
    }
    let startLine = max(0, min(lineRange.startLine, totalLineCount - 1))
    let rawLineCount = max(1, lineRange.lineCount)
    let endLineExclusive = min(totalLineCount, startLine + rawLineCount)
    let startFraction = CGFloat(startLine) / CGFloat(totalLineCount)
    let endFraction = CGFloat(endLineExclusive) / CGFloat(totalLineCount)
    return WorkspaceTextEditorOverviewMarker(
        kind: kind,
        startFraction: min(max(startFraction, 0), 1),
        endFraction: min(max(endFraction, startFraction), 1)
    )
}

private func overviewMarkerKind(
    for highlightKind: WorkspaceDiffEditorHighlightKind
) -> WorkspaceTextEditorOverviewMarkerKind {
    switch highlightKind {
    case .added:
        return .added
    case .removed:
        return .removed
    case .changed:
        return .changed
    case .conflict:
        return .conflict
    }
}

private func characterRange(for lineRange: WorkspaceDiffLineRange, in content: NSString) -> NSRange {
    guard lineRange.lineCount > 0 else {
        return NSRange(location: NSNotFound, length: 0)
    }

    var currentLine = 0
    var searchLocation = 0
    var startLocation: Int?
    var endLocation: Int?

    while searchLocation < content.length {
        if currentLine == lineRange.startLine {
            startLocation = searchLocation
        }
        if currentLine == lineRange.endLine {
            endLocation = searchLocation
            break
        }

        var lineEnd = 0
        content.getLineStart(nil, end: &lineEnd, contentsEnd: nil, for: NSRange(location: searchLocation, length: 0))
        searchLocation = lineEnd
        currentLine += 1
    }

    if startLocation == nil, currentLine == lineRange.startLine {
        startLocation = searchLocation
    }
    if endLocation == nil {
        endLocation = content.length
    }

    guard let startLocation, let endLocation else {
        return NSRange(location: NSNotFound, length: 0)
    }
    return NSRange(location: startLocation, length: max(0, endLocation - startLocation))
}

private func characterRange(
    forLineIndex lineIndex: Int,
    inlineRange: WorkspaceDiffInlineRange,
    in content: NSString
) -> NSRange {
    guard let startLocation = lineStartLocation(for: lineIndex, in: content) else {
        return NSRange(location: NSNotFound, length: 0)
    }

    let lineRange = content.lineRange(for: NSRange(location: startLocation, length: 0))
    let contentsEnd = max(lineRange.location, lineRange.location + lineRange.length - lineRangeTerminatorLength(in: content, lineRange: lineRange))
    let safeStart = min(lineRange.location + inlineRange.startColumn, contentsEnd)
    let safeEnd = min(safeStart + inlineRange.length, contentsEnd)
    return NSRange(location: safeStart, length: max(0, safeEnd - safeStart))
}

private func lineStartLocation(for targetLineIndex: Int, in content: NSString) -> Int? {
    guard targetLineIndex >= 0 else {
        return nil
    }
    var currentLine = 0
    var searchLocation = 0

    while searchLocation < content.length {
        if currentLine == targetLineIndex {
            return searchLocation
        }
        var lineEnd = 0
        content.getLineStart(nil, end: &lineEnd, contentsEnd: nil, for: NSRange(location: searchLocation, length: 0))
        searchLocation = lineEnd
        currentLine += 1
    }

    return currentLine == targetLineIndex ? searchLocation : nil
}

private func lineRangeTerminatorLength(in content: NSString, lineRange: NSRange) -> Int {
    guard lineRange.length > 0 else {
        return 0
    }
    let lastCharacter = content.substring(with: NSRange(location: lineRange.location + lineRange.length - 1, length: 1))
    return lastCharacter == "\n" ? 1 : 0
}
