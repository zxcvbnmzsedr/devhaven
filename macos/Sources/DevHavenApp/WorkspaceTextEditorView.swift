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
    var matchesWholeWords: Bool
    var usesRegularExpression: Bool
    var preservesReplacementCase: Bool

    init(
        query: String = "",
        replacement: String = "",
        revision: Int = 0,
        kind: WorkspaceTextEditorSearchRequestKind = .revealSearch,
        targetLine: Int? = nil,
        isCaseSensitive: Bool = false,
        matchesWholeWords: Bool = false,
        usesRegularExpression: Bool = false,
        preservesReplacementCase: Bool = false
    ) {
        self.query = query
        self.replacement = replacement
        self.revision = revision
        self.kind = kind
        self.targetLine = targetLine.map { max(0, $0) }
        self.isCaseSensitive = isCaseSensitive
        self.matchesWholeWords = matchesWholeWords
        self.usesRegularExpression = usesRegularExpression
        self.preservesReplacementCase = preservesReplacementCase
    }
}

struct WorkspaceTextEditorDecorationSignature: Equatable {
    var contentRevision: Int
    var syntaxStyle: WorkspaceEditorSyntaxStyle
    var highlights: [WorkspaceDiffEditorHighlight]
    var inlineHighlights: [WorkspaceDiffEditorInlineHighlight]
}

struct WorkspaceTextEditorSearchHighlightSignature: Equatable {
    var contentRevision: Int
    var query: String
    var isSearchCaseSensitive: Bool
    var matchesWholeWords: Bool
    var usesRegularExpression: Bool
    var selectedRange: NSRange
}

struct WorkspaceTextEditorMarkupSignature: Equatable {
    var contentRevision: Int
    var query: String
    var isSearchCaseSensitive: Bool
    var matchesWholeWords: Bool
    var usesRegularExpression: Bool
    var highlights: [WorkspaceDiffEditorHighlight]
    var explicitMarkupMarkers: [WorkspaceEditorMarkupMarker]
}

private struct WorkspaceTextEditorContentCacheKey: Hashable {
    var length: Int
    var fingerprint: Int
}

private struct WorkspaceTextEditorRegularExpressionCacheKey: Hashable {
    var pattern: String
    var optionsRawValue: UInt
}

private struct WorkspaceTextEditorSearchCacheKey: Hashable {
    var content: WorkspaceTextEditorContentCacheKey
    var query: String
    var isCaseSensitive: Bool
    var matchesWholeWords: Bool
    var usesRegularExpression: Bool
}

private struct WorkspaceTextEditorRegularExpressionCompileResult {
    var expression: NSRegularExpression?
    var errorMessage: String?
}

private final class WorkspaceTextEditorRegularExpressionCache: @unchecked Sendable {
    static let shared = WorkspaceTextEditorRegularExpressionCache()
    private static let maxEntryCount = 256

    private let lock = NSLock()
    private var cachedResults: [WorkspaceTextEditorRegularExpressionCacheKey: WorkspaceTextEditorRegularExpressionCompileResult] = [:]

    func result(
        pattern: String,
        options: NSRegularExpression.Options
    ) -> WorkspaceTextEditorRegularExpressionCompileResult {
        let key = WorkspaceTextEditorRegularExpressionCacheKey(
            pattern: pattern,
            optionsRawValue: options.rawValue
        )
        lock.lock()
        if let cached = cachedResults[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let result: WorkspaceTextEditorRegularExpressionCompileResult
        do {
            result = WorkspaceTextEditorRegularExpressionCompileResult(
                expression: try NSRegularExpression(pattern: pattern, options: options),
                errorMessage: nil
            )
        } catch {
            let message = (error as NSError).localizedFailureReason
                ?? error.localizedDescription
            result = WorkspaceTextEditorRegularExpressionCompileResult(
                expression: nil,
                errorMessage: "无效正则表达式：\(message)"
            )
        }
        lock.lock()
        cachedResults[key] = result
        trimIfNeeded()
        lock.unlock()
        return result
    }

    private func trimIfNeeded() {
        guard cachedResults.count > Self.maxEntryCount else {
            return
        }
        cachedResults.removeAll(keepingCapacity: true)
    }
}

private final class WorkspaceTextEditorSearchCache: @unchecked Sendable {
    static let shared = WorkspaceTextEditorSearchCache()
    private static let maxEntryCount = 192

    private let lock = NSLock()
    private var cachedResults: [WorkspaceTextEditorSearchCacheKey: WorkspaceTextEditorSearchMatchesResult] = [:]

    func result(
        query: String,
        in content: NSString,
        isCaseSensitive: Bool,
        matchesWholeWords: Bool,
        usesRegularExpression: Bool
    ) -> WorkspaceTextEditorSearchMatchesResult {
        guard !query.isEmpty, content.length > 0 else {
            return WorkspaceTextEditorSearchMatchesResult()
        }

        let key = WorkspaceTextEditorSearchCacheKey(
            content: workspaceTextEditorContentCacheKey(for: content),
            query: query,
            isCaseSensitive: isCaseSensitive,
            matchesWholeWords: matchesWholeWords,
            usesRegularExpression: usesRegularExpression
        )
        lock.lock()
        if let cached = cachedResults[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let result = workspaceTextEditorComputeSearchMatchesResult(
            query: query,
            in: content,
            isCaseSensitive: isCaseSensitive,
            matchesWholeWords: matchesWholeWords,
            usesRegularExpression: usesRegularExpression
        )
        lock.lock()
        cachedResults[key] = result
        trimIfNeeded()
        lock.unlock()
        return result
    }

    private func trimIfNeeded() {
        guard cachedResults.count > Self.maxEntryCount else {
            return
        }
        cachedResults.removeAll(keepingCapacity: true)
    }
}

struct WorkspaceTextEditorSearchSessionState: Equatable {
    var query: String
    var matchCount: Int
    var currentMatchIndex: Int?
    var errorMessage: String?

    init(
        query: String = "",
        matchCount: Int = 0,
        currentMatchIndex: Int? = nil,
        errorMessage: String? = nil
    ) {
        self.query = query
        self.matchCount = max(0, matchCount)
        self.currentMatchIndex = currentMatchIndex
        let trimmed = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.errorMessage = trimmed.isEmpty ? nil : trimmed
    }
}

struct WorkspaceTextEditorSearchMatchesResult: Equatable {
    var ranges: [NSRange]
    var errorMessage: String?

    init(ranges: [NSRange] = [], errorMessage: String? = nil) {
        self.ranges = ranges
        let trimmed = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.errorMessage = trimmed.isEmpty ? nil : trimmed
    }
}

enum WorkspaceTextEditorFocusRequestPolicy {
    static func shouldRequestFocus(
        wantsFocus: Bool,
        hasIssuedFocusRequest: Bool,
        isEditorFocused: Bool,
        currentEventType: NSEvent.EventType?
    ) -> Bool {
        guard wantsFocus else {
            return false
        }
        guard !hasIssuedFocusRequest else {
            return false
        }
        guard !isEditorFocused else {
            return false
        }
        guard !isLivePointerDrag(eventType: currentEventType) else {
            return false
        }
        return true
    }

    private static func isLivePointerDrag(eventType: NSEvent.EventType?) -> Bool {
        switch eventType {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return true
        default:
            return false
        }
    }
}

struct WorkspaceEditorOverviewMarker: Equatable {
    var kind: WorkspaceEditorMarkupMarkerKind
    var lineRange: WorkspaceDiffLineRange
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
        font: NSFont,
        markupMarkers: [WorkspaceEditorMarkupMarker] = []
    ) -> CGFloat {
        let digits = max(2, String(max(1, lineCount)).count)
        let sample = String(repeating: "8", count: digits)
        let width = (sample as NSString).size(withAttributes: [.font: font]).width
        let lineStatusWidth = markupMarkers.contains(where: {
            $0.showsInGutter && $0.lane == .lineStatus
        }) ? workspaceTextEditorLineStatusLaneWidth + workspaceTextEditorGutterLaneSpacing : 0
        let iconWidth = markupMarkers.contains(where: {
            $0.showsInGutter && $0.lane == .icons
        }) ? workspaceTextEditorIconLaneWidth + workspaceTextEditorGutterLaneSpacing : 0
        let annotationWidth = workspaceTextEditorAnnotationLaneWidth(for: markupMarkers, font: font)
        return max(
            gutterMinimumWidth,
            ceil(width + gutterHorizontalPadding * 2 + lineStatusWidth + iconWidth + annotationWidth)
        )
    }

    @MainActor
    static func lineHeight(for textView: NSTextView) -> CGFloat {
        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        return textView.layoutManager?.defaultLineHeight(for: font)
            ?? ceil(font.ascender - font.descender + font.leading)
    }
}

private let workspaceTextEditorLineStatusLaneWidth: CGFloat = 4
private let workspaceTextEditorIconLaneWidth: CGFloat = 12
private let workspaceTextEditorGutterLaneSpacing: CGFloat = 6

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

    var markers: [WorkspaceEditorMarkupMarker] = [] {
        didSet {
            guard markers != oldValue else {
                return
            }
            needsDisplay = true
        }
    }

    var totalLineCount: Int = 1 {
        didSet {
            guard totalLineCount != oldValue else {
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

    var currentLineIndex: Int = 0 {
        didSet {
            guard currentLineIndex != oldValue else {
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
            let rect = bandRect(for: marker.lineRange, totalLineCount: totalLineCount, minimumHeight: 3)
            color(for: marker.kind).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        }
    }

    private func drawCurrentLineMarker() {
        let rect = bandRect(
            for: WorkspaceDiffLineRange(startLine: currentLineIndex, lineCount: 1),
            totalLineCount: totalLineCount,
            minimumHeight: 2
        )
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

    private func bandRect(
        for lineRange: WorkspaceDiffLineRange,
        totalLineCount: Int,
        minimumHeight: CGFloat
    ) -> NSRect {
        let normalizedTotalLineCount = max(1, totalLineCount)
        let startLine = max(0, min(lineRange.startLine, normalizedTotalLineCount - 1))
        let endLineExclusive = min(normalizedTotalLineCount, startLine + max(1, lineRange.lineCount))
        let lower = CGFloat(startLine) / CGFloat(normalizedTotalLineCount)
        let upper = CGFloat(endLineExclusive) / CGFloat(normalizedTotalLineCount)
        return bandRect(for: lower...upper, minimumHeight: minimumHeight)
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

    private func color(for kind: WorkspaceEditorMarkupMarkerKind) -> NSColor {
        switch kind {
        case .searchMatch:
            return NSColor.systemYellow.withAlphaComponent(0.9)
        case .added:
            return NSColor.systemGreen.withAlphaComponent(0.9)
        case .removed, .error, .breakpoint:
            return NSColor.systemRed.withAlphaComponent(0.9)
        case .changed, .warning:
            return NSColor.systemOrange.withAlphaComponent(0.9)
        case .conflict, .foldedRegion:
            return NSColor.systemPurple.withAlphaComponent(0.9)
        case .bookmark:
            return NSColor.systemBlue.withAlphaComponent(0.9)
        case .info:
            return NSColor.systemTeal.withAlphaComponent(0.9)
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
    private static let lineStatusInsetX: CGFloat = 4

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
    private var markupMarkers: [WorkspaceEditorMarkupMarker] = []

    init(scrollView: NSScrollView, textView: WorkspaceEditorTextView) {
        self.editorTextView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        update(
            lineStartOffsets: [0],
            currentLineIndex: 0,
            highlightsCurrentLine: true,
            markupMarkers: []
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        lineStartOffsets: [Int],
        currentLineIndex: Int,
        highlightsCurrentLine: Bool,
        markupMarkers: [WorkspaceEditorMarkupMarker]
    ) {
        let normalizedLineStartOffsets = lineStartOffsets.isEmpty ? [0] : lineStartOffsets
        let clampedCurrentLineIndex = max(0, currentLineIndex)
        guard self.lineStartOffsets != normalizedLineStartOffsets
            || self.currentLineIndex != clampedCurrentLineIndex
            || self.highlightsCurrentLine != highlightsCurrentLine
            || self.markupMarkers != markupMarkers
        else {
            return
        }
        self.lineStartOffsets = normalizedLineStartOffsets
        self.currentLineIndex = clampedCurrentLineIndex
        self.highlightsCurrentLine = highlightsCurrentLine
        self.markupMarkers = markupMarkers
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

        drawChangeMarkers(
            visibleRange: visibleRange,
            contentOffsetY: contentOffsetY,
            insetTop: insetTop,
            lineHeight: lineHeight
        )
        drawIconMarkers(
            visibleRange: visibleRange,
            contentOffsetY: contentOffsetY,
            insetTop: insetTop,
            lineHeight: lineHeight
        )
        drawAnnotationMarkers(
            visibleRange: visibleRange,
            contentOffsetY: contentOffsetY,
            insetTop: insetTop,
            lineHeight: lineHeight
        )

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

    private func drawChangeMarkers(
        visibleRange: ClosedRange<Int>,
        contentOffsetY: CGFloat,
        insetTop: CGFloat,
        lineHeight: CGFloat
    ) {
        let visibleMarkers = markupMarkers.filter {
            $0.showsInGutter && $0.lane == .lineStatus
        }
        guard !visibleMarkers.isEmpty else {
            return
        }

        let markerX = Self.lineStatusInsetX
        let markerWidth = min(workspaceTextEditorLineStatusLaneWidth, max(1, bounds.width - markerX - 2))
        for marker in visibleMarkers {
            let markerStart = max(marker.lineRange.startLine, visibleRange.lowerBound)
            let markerEndExclusive = min(
                marker.lineRange.startLine + max(1, marker.lineRange.lineCount),
                visibleRange.upperBound + 1
            )
            guard markerStart < markerEndExclusive else {
                continue
            }
            let startY = WorkspaceTextEditorLineMetrics.lineOriginY(
                forLineIndex: markerStart,
                insetTop: insetTop,
                lineHeight: lineHeight
            ) - contentOffsetY
            let endY = WorkspaceTextEditorLineMetrics.lineOriginY(
                forLineIndex: markerEndExclusive,
                insetTop: insetTop,
                lineHeight: lineHeight
            ) - contentOffsetY
            let rect = NSRect(
                x: markerX,
                y: startY,
                width: markerWidth,
                height: max(3, endY - startY)
            ).intersection(bounds)
            guard !rect.isEmpty else {
                continue
            }
            gutterMarkerColor(for: marker.kind).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        }
    }

    private func drawIconMarkers(
        visibleRange: ClosedRange<Int>,
        contentOffsetY: CGFloat,
        insetTop: CGFloat,
        lineHeight: CGFloat
    ) {
        let visibleMarkers = markupMarkers.filter {
            $0.showsInGutter
                && $0.lane == .icons
                && $0.icon != nil
                && visibleRange.contains($0.lineRange.startLine)
        }
        guard !visibleMarkers.isEmpty else {
            return
        }

        let iconCenterX = Self.lineStatusInsetX
            + workspaceTextEditorLineStatusLaneWidth
            + workspaceTextEditorGutterLaneSpacing
            + workspaceTextEditorIconLaneWidth / 2
        let preferredMarkers = workspaceTextEditorPreferredGutterMarkers(
            visibleMarkers,
            for: .icons
        )
        for marker in preferredMarkers {
            let markerRect = workspaceTextEditorRulerLineRect(
                lineRange: WorkspaceDiffLineRange(startLine: marker.lineRange.startLine, lineCount: 1),
                contentOffsetY: contentOffsetY,
                insetTop: insetTop,
                lineHeight: lineHeight
            ).intersection(bounds)
            guard !markerRect.isEmpty,
                  let icon = marker.icon
            else {
                continue
            }
            let center = NSPoint(x: iconCenterX, y: markerRect.midY)
            let size = min(9, lineHeight - 4)
            workspaceTextEditorDrawGutterIcon(
                icon,
                in: NSRect(
                    x: center.x - size / 2,
                    y: center.y - size / 2,
                    width: size,
                    height: size
                ),
                color: gutterMarkerColor(for: marker.kind)
            )
        }
    }

    private func drawAnnotationMarkers(
        visibleRange: ClosedRange<Int>,
        contentOffsetY: CGFloat,
        insetTop: CGFloat,
        lineHeight: CGFloat
    ) {
        let visibleMarkers = markupMarkers.filter {
            $0.showsInGutter
                && $0.lane == .annotations
                && $0.annotationText != nil
                && visibleRange.contains($0.lineRange.startLine)
        }
        guard !visibleMarkers.isEmpty else {
            return
        }

        let preferredMarkers = workspaceTextEditorPreferredGutterMarkers(
            visibleMarkers,
            for: .annotations
        )
        let annotationX = Self.lineStatusInsetX
            + (markupMarkers.contains(where: { $0.showsInGutter && $0.lane == .lineStatus })
                ? workspaceTextEditorLineStatusLaneWidth + workspaceTextEditorGutterLaneSpacing
                : 0)
            + (markupMarkers.contains(where: { $0.showsInGutter && $0.lane == .icons })
                ? workspaceTextEditorIconLaneWidth + workspaceTextEditorGutterLaneSpacing
                : 0)

        for marker in preferredMarkers {
            guard let annotationText = marker.annotationText else {
                continue
            }
            let markerRect = workspaceTextEditorRulerLineRect(
                lineRange: WorkspaceDiffLineRange(startLine: marker.lineRange.startLine, lineCount: 1),
                contentOffsetY: contentOffsetY,
                insetTop: insetTop,
                lineHeight: lineHeight
            ).intersection(bounds)
            guard !markerRect.isEmpty else {
                continue
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: gutterMarkerColor(for: marker.kind).withAlphaComponent(0.9),
            ]
            let textRect = NSRect(
                x: annotationX,
                y: markerRect.minY + floor((markerRect.height - 11) / 2),
                width: max(0, bounds.width - annotationX - WorkspaceTextEditorLineMetrics.gutterHorizontalPadding - 18),
                height: 11
            )
            (annotationText as NSString).draw(in: textRect, withAttributes: attributes)
        }
    }

    private func updateThicknessIfNeeded() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let targetThickness = WorkspaceTextEditorLineMetrics.gutterWidth(
            lineCount: lineStartOffsets.count,
            font: font,
            markupMarkers: markupMarkers
        )
        guard abs(ruleThickness - targetThickness) > 0.5 else {
            return
        }
        ruleThickness = targetThickness
    }

    private func gutterMarkerColor(for kind: WorkspaceEditorMarkupMarkerKind) -> NSColor {
        switch kind {
        case .added:
            return NSColor.systemGreen.withAlphaComponent(0.95)
        case .removed, .error, .breakpoint:
            return NSColor.systemRed.withAlphaComponent(0.95)
        case .changed, .warning:
            return NSColor.systemBlue.withAlphaComponent(0.95)
        case .conflict, .foldedRegion:
            return NSColor.systemPurple.withAlphaComponent(0.95)
        case .searchMatch:
            return NSColor.systemYellow.withAlphaComponent(0.95)
        case .bookmark:
            return NSColor.systemOrange.withAlphaComponent(0.95)
        case .info:
            return NSColor.systemTeal.withAlphaComponent(0.95)
        }
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
    let shouldRequestFocus: Bool
    let displayOptions: WorkspaceEditorDisplayOptions
    let syntaxStyle: WorkspaceEditorSyntaxStyle
    let highlights: [WorkspaceDiffEditorHighlight]
    let inlineHighlights: [WorkspaceDiffEditorInlineHighlight]
    let markupMarkers: [WorkspaceEditorMarkupMarker]
    let searchQuery: String
    let isSearchCaseSensitive: Bool
    let matchesSearchWholeWords: Bool
    let usesRegularExpressionInSearch: Bool
    let scrollSyncState: Binding<WorkspaceTextEditorScrollSyncState>?
    let scrollRequestState: Binding<WorkspaceTextEditorScrollRequestState>?
    let searchRequestState: Binding<WorkspaceTextEditorSearchRequestState>?
    let searchSessionState: Binding<WorkspaceTextEditorSearchSessionState>?
    let selectionText: Binding<String?>?

    init(
        editorID: String,
        text: Binding<String>,
        isEditable: Bool,
        shouldRequestFocus: Bool = false,
        displayOptions: WorkspaceEditorDisplayOptions = .init(),
        syntaxStyle: WorkspaceEditorSyntaxStyle = .plainText,
        highlights: [WorkspaceDiffEditorHighlight] = [],
        inlineHighlights: [WorkspaceDiffEditorInlineHighlight] = [],
        markupMarkers: [WorkspaceEditorMarkupMarker] = [],
        searchQuery: String = "",
        isSearchCaseSensitive: Bool = false,
        matchesSearchWholeWords: Bool = false,
        usesRegularExpressionInSearch: Bool = false,
        scrollSyncState: Binding<WorkspaceTextEditorScrollSyncState>? = nil,
        scrollRequestState: Binding<WorkspaceTextEditorScrollRequestState>? = nil,
        searchRequestState: Binding<WorkspaceTextEditorSearchRequestState>? = nil,
        searchSessionState: Binding<WorkspaceTextEditorSearchSessionState>? = nil,
        selectionText: Binding<String?>? = nil
    ) {
        self.editorID = editorID
        self._text = text
        self.isEditable = isEditable
        self.shouldRequestFocus = shouldRequestFocus
        self.displayOptions = displayOptions
        self.syntaxStyle = syntaxStyle
        self.highlights = highlights
        self.inlineHighlights = inlineHighlights
        self.markupMarkers = markupMarkers
        self.searchQuery = searchQuery
        self.isSearchCaseSensitive = isSearchCaseSensitive
        self.matchesSearchWholeWords = matchesSearchWholeWords
        self.usesRegularExpressionInSearch = usesRegularExpressionInSearch
        self.scrollSyncState = scrollSyncState
        self.scrollRequestState = scrollRequestState
        self.searchRequestState = searchRequestState
        self.searchSessionState = searchSessionState
        self.selectionText = selectionText
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            editorID: editorID,
            text: $text,
            scrollSyncState: scrollSyncState,
            scrollRequestState: scrollRequestState,
            searchRequestState: searchRequestState,
            searchSessionState: searchSessionState,
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
            markupMarkers: markupMarkers,
            searchQuery: searchQuery,
            isSearchCaseSensitive: isSearchCaseSensitive,
            matchesSearchWholeWords: matchesSearchWholeWords,
            usesRegularExpressionInSearch: usesRegularExpressionInSearch,
            force: true
        )
        context.coordinator.applyFocusRequestIfNeeded(shouldRequestFocus)
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
        context.coordinator.applyDecorationsIfNeeded(
            syntaxStyle: syntaxStyle,
            highlights: highlights,
            inlineHighlights: inlineHighlights,
            markupMarkers: markupMarkers,
            searchQuery: searchQuery,
            isSearchCaseSensitive: isSearchCaseSensitive,
            matchesSearchWholeWords: matchesSearchWholeWords,
            usesRegularExpressionInSearch: usesRegularExpressionInSearch,
            force: textChanged
        )
        if !textChanged {
            context.coordinator.refreshEditorChrome()
        }
        context.coordinator.applyFocusRequestIfNeeded(shouldRequestFocus)
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
        private let searchSessionState: Binding<WorkspaceTextEditorSearchSessionState>?
        private let selectionText: Binding<String?>?
        private weak var scrollView: NSScrollView?
        private weak var textView: NSTextView?
        private weak var overviewBarView: WorkspaceEditorOverviewBarView?
        private weak var observedBoundsClipView: NSClipView?
        private var currentLineHighlightView: NSView?
        private var hasIssuedFocusRequest = false
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
        private var latestMarkupMarkers: [WorkspaceEditorMarkupMarker] = []
        private var latestSearchQuery = ""
        private var latestSearchCaseSensitive = false
        private var latestSearchWholeWords = false
        private var latestSearchUsesRegularExpression = false
        private var lastResolvedMarkupSignature: WorkspaceTextEditorMarkupSignature?
        private var cachedMarkupModel = WorkspaceEditorMarkupModel()

        init(
            editorID: String,
            text: Binding<String>,
            scrollSyncState: Binding<WorkspaceTextEditorScrollSyncState>?,
            scrollRequestState: Binding<WorkspaceTextEditorScrollRequestState>?,
            searchRequestState: Binding<WorkspaceTextEditorSearchRequestState>?,
            searchSessionState: Binding<WorkspaceTextEditorSearchSessionState>?,
            selectionText: Binding<String?>?
        ) {
            self.editorID = editorID
            self.text = text
            self.scrollSyncState = scrollSyncState
            self.scrollRequestState = scrollRequestState
            self.searchRequestState = searchRequestState
            self.searchSessionState = searchSessionState
            self.selectionText = selectionText
        }

        deinit {
            if let observedBoundsClipView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedBoundsClipView
                )
            }
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
            textView.delegate = self
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

            if let observedBoundsClipView,
               observedBoundsClipView !== scrollView.contentView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedBoundsClipView
                )
            }
            observedBoundsClipView = scrollView.contentView
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

        func applyFocusRequestIfNeeded(_ shouldRequestFocus: Bool) {
            guard let textView else {
                hasIssuedFocusRequest = false
                return
            }

            guard shouldRequestFocus else {
                hasIssuedFocusRequest = false
                return
            }

            let isEditorFocused = textView.window?.firstResponder === textView
            if isEditorFocused {
                hasIssuedFocusRequest = true
                return
            }

            let shouldIssueRequest = WorkspaceTextEditorFocusRequestPolicy.shouldRequestFocus(
                wantsFocus: shouldRequestFocus,
                hasIssuedFocusRequest: hasIssuedFocusRequest,
                isEditorFocused: isEditorFocused,
                currentEventType: NSApp.currentEvent?.type
            )
            guard shouldIssueRequest else {
                return
            }

            hasIssuedFocusRequest = true
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self else {
                    return
                }
                guard let textView,
                      let window = textView.window
                else {
                    self.hasIssuedFocusRequest = false
                    return
                }

                let didFocus = window.makeFirstResponder(textView)
                if !didFocus, window.firstResponder !== textView {
                    self.hasIssuedFocusRequest = false
                }
            }
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
            return true
        }

        func applyDecorationsIfNeeded(
            syntaxStyle: WorkspaceEditorSyntaxStyle,
            highlights: [WorkspaceDiffEditorHighlight],
            inlineHighlights: [WorkspaceDiffEditorInlineHighlight],
            markupMarkers: [WorkspaceEditorMarkupMarker],
            searchQuery: String,
            isSearchCaseSensitive: Bool,
            matchesSearchWholeWords: Bool,
            usesRegularExpressionInSearch: Bool,
            force: Bool
        ) {
            guard let textView else {
                return
            }
            latestSyntaxStyle = syntaxStyle
            latestHighlights = highlights
            latestInlineHighlights = inlineHighlights
            latestMarkupMarkers = markupMarkers
            latestSearchQuery = searchQuery
            latestSearchCaseSensitive = isSearchCaseSensitive
            latestSearchWholeWords = matchesSearchWholeWords
            latestSearchUsesRegularExpression = usesRegularExpressionInSearch
            let signature = WorkspaceTextEditorDecorationSignature(
                contentRevision: searchContentRevision,
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
                markupMarkers: latestMarkupMarkers,
                searchQuery: latestSearchQuery,
                isSearchCaseSensitive: latestSearchCaseSensitive,
                matchesSearchWholeWords: latestSearchWholeWords,
                usesRegularExpressionInSearch: latestSearchUsesRegularExpression,
                force: force
            )
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
                    isCaseSensitive: request.isCaseSensitive,
                    matchesWholeWords: request.matchesWholeWords,
                    usesRegularExpression: request.usesRegularExpression
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
                    isCaseSensitive: request.isCaseSensitive,
                    matchesWholeWords: request.matchesWholeWords,
                    usesRegularExpression: request.usesRegularExpression
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
                isCaseSensitive: request.isCaseSensitive,
                matchesWholeWords: request.matchesWholeWords,
                usesRegularExpression: request.usesRegularExpression
            ) {
                replacementRange = textView.selectedRange()
            } else if let match = workspaceTextEditorNextMatch(
                query: request.query,
                in: content,
                selectedRange: textView.selectedRange(),
                isCaseSensitive: request.isCaseSensitive,
                matchesWholeWords: request.matchesWholeWords,
                usesRegularExpression: request.usesRegularExpression
            ) {
                replacementRange = match
            } else {
                NSSound.beep()
                return
            }

            replace(
                range: replacementRange,
                matching: request.query,
                with: request.replacement,
                in: textView,
                usesRegularExpression: request.usesRegularExpression,
                preservesReplacementCase: request.preservesReplacementCase
            )
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
                isCaseSensitive: request.isCaseSensitive,
                matchesWholeWords: request.matchesWholeWords,
                usesRegularExpression: request.usesRegularExpression,
                preservesReplacementCase: request.preservesReplacementCase
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
            reapplyStoredDecorations(force: true)
        }

        private func replace(
            range: NSRange,
            matching query: String,
            with replacement: String,
            in textView: NSTextView,
            usesRegularExpression: Bool,
            preservesReplacementCase: Bool
        ) {
            guard let textStorage = textView.textStorage else {
                return
            }
            let content = textView.string as NSString
            let replacementText = workspaceTextEditorResolvedReplacement(
                replacement,
                matchingRange: range,
                query: query,
                in: content,
                usesRegularExpression: usesRegularExpression,
                preservesReplacementCase: preservesReplacementCase
            )
            textStorage.replaceCharacters(in: range, with: replacementText)
            if text.wrappedValue != textView.string {
                text.wrappedValue = textView.string
            }
            let selectionRange = NSRange(location: range.location, length: (replacementText as NSString).length)
            textView.setSelectedRange(selectionRange)
            textView.scrollRangeToVisible(selectionRange)
            lineStartOffsets = WorkspaceTextEditorLineMetrics.lineStartOffsets(in: textView.string as NSString)
            lastAppliedDecorationSignature = nil
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

            let markupModel = resolvedMarkupModel(in: textView.string as NSString)
            (scrollView.verticalRulerView as? WorkspaceLineNumberRulerView)?
                .update(
                    lineStartOffsets: lineStartOffsets,
                    currentLineIndex: currentLineIndex,
                    highlightsCurrentLine: latestDisplayOptions.highlightsCurrentLine,
                    markupMarkers: markupModel.gutterMarkers
                )
            refreshOverviewBar(
                currentLineIndex: currentLineIndex,
                scrollView: scrollView,
                markupModel: markupModel
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
            let searchResult = workspaceTextEditorSearchMatchesResult(
                query: latestSearchQuery,
                in: textView.string as NSString,
                isCaseSensitive: latestSearchCaseSensitive,
                matchesWholeWords: latestSearchWholeWords,
                usesRegularExpression: latestSearchUsesRegularExpression
            )
            let signature = workspaceTextEditorEffectiveSearchHighlightSignature(
                contentRevision: searchContentRevision,
                query: latestSearchQuery,
                isCaseSensitive: latestSearchCaseSensitive,
                matchesWholeWords: latestSearchWholeWords,
                usesRegularExpression: latestSearchUsesRegularExpression,
                selectedRange: textView.selectedRange()
            )
            guard force || lastAppliedSearchHighlightSignature != signature else {
                updateSearchSessionState(in: textView, searchResult: searchResult)
                return
            }
            applyTemporarySearchHighlights(
                searchResult: searchResult,
                selectedRange: textView.selectedRange(),
                to: textView
            )
            lastAppliedSearchHighlightSignature = signature
            updateSearchSessionState(in: textView, searchResult: searchResult)
        }

        private func resolvedMarkupModel(in content: NSString) -> WorkspaceEditorMarkupModel {
            let signature = WorkspaceTextEditorMarkupSignature(
                contentRevision: searchContentRevision,
                query: latestSearchQuery,
                isSearchCaseSensitive: latestSearchCaseSensitive,
                matchesWholeWords: latestSearchWholeWords,
                usesRegularExpression: latestSearchUsesRegularExpression,
                highlights: latestHighlights,
                explicitMarkupMarkers: latestMarkupMarkers
            )
            guard lastResolvedMarkupSignature != signature else {
                return cachedMarkupModel
            }
            let markupModel = workspaceTextEditorMarkupModel(
                highlights: latestHighlights,
                additionalMarkers: latestMarkupMarkers,
                searchQuery: latestSearchQuery,
                in: content,
                lineStartOffsets: lineStartOffsets,
                isSearchCaseSensitive: latestSearchCaseSensitive,
                matchesWholeWords: latestSearchWholeWords,
                usesRegularExpression: latestSearchUsesRegularExpression
            )
            lastResolvedMarkupSignature = signature
            cachedMarkupModel = markupModel
            return markupModel
        }

        private func refreshOverviewBar(
            currentLineIndex: Int,
            scrollView: NSScrollView,
            markupModel: WorkspaceEditorMarkupModel
        ) {
            guard let overviewBarView else {
                return
            }

            overviewBarView.totalLineCount = max(1, lineStartOffsets.count)
            overviewBarView.markers = markupModel.overviewMarkers
            overviewBarView.currentLineIndex = max(0, currentLineIndex)
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

        private func updateSearchSessionState(
            in textView: NSTextView,
            searchResult: WorkspaceTextEditorSearchMatchesResult? = nil
        ) {
            guard let searchSessionState else {
                return
            }
            let resolvedSearchResult = searchResult ?? workspaceTextEditorSearchMatchesResult(
                query: latestSearchQuery,
                in: textView.string as NSString,
                isCaseSensitive: latestSearchCaseSensitive,
                matchesWholeWords: latestSearchWholeWords,
                usesRegularExpression: latestSearchUsesRegularExpression
            )
            let currentMatchIndex = resolvedSearchResult.ranges.firstIndex(where: {
                NSEqualRanges($0, textView.selectedRange())
            }).map { $0 + 1 }
            let nextState = WorkspaceTextEditorSearchSessionState(
                query: latestSearchQuery,
                matchCount: resolvedSearchResult.ranges.count,
                currentMatchIndex: currentMatchIndex,
                errorMessage: resolvedSearchResult.errorMessage
            )
            if searchSessionState.wrappedValue != nextState {
                searchSessionState.wrappedValue = nextState
            }
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
        guard let expression = WorkspaceTextEditorRegularExpressionCache.shared
            .result(pattern: pattern, options: options)
            .expression
        else {
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

private func workspaceTextEditorContentCacheKey(for content: NSString) -> WorkspaceTextEditorContentCacheKey {
    WorkspaceTextEditorContentCacheKey(length: content.length, fingerprint: content.hash)
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

private func workspaceTextEditorRegularExpression(
    query: String,
    isCaseSensitive: Bool
) -> (expression: NSRegularExpression?, errorMessage: String?) {
    let options: NSRegularExpression.Options = isCaseSensitive ? [] : [.caseInsensitive]
    let result = WorkspaceTextEditorRegularExpressionCache.shared.result(
        pattern: query,
        options: options
    )
    return (result.expression, result.errorMessage)
}

func workspaceTextEditorSearchMatchesResult(
    query: String,
    in content: NSString,
    isCaseSensitive: Bool,
    matchesWholeWords: Bool,
    usesRegularExpression: Bool
) -> WorkspaceTextEditorSearchMatchesResult {
    WorkspaceTextEditorSearchCache.shared.result(
        query: query,
        in: content,
        isCaseSensitive: isCaseSensitive,
        matchesWholeWords: matchesWholeWords,
        usesRegularExpression: usesRegularExpression
    )
}

private func workspaceTextEditorComputeSearchMatchesResult(
    query: String,
    in content: NSString,
    isCaseSensitive: Bool,
    matchesWholeWords: Bool,
    usesRegularExpression: Bool
) -> WorkspaceTextEditorSearchMatchesResult {
    guard !query.isEmpty, content.length > 0 else {
        return WorkspaceTextEditorSearchMatchesResult()
    }

    var ranges: [NSRange] = []
    if usesRegularExpression {
        let compiled = workspaceTextEditorRegularExpression(query: query, isCaseSensitive: isCaseSensitive)
        if let expression = compiled.expression {
            let fullRange = NSRange(location: 0, length: content.length)
            expression.enumerateMatches(in: content as String, options: [], range: fullRange) { result, _, _ in
                guard let range = result?.range, range.location != NSNotFound, range.length > 0 else {
                    return
                }
                ranges.append(range)
            }
        } else if let errorMessage = compiled.errorMessage {
            return WorkspaceTextEditorSearchMatchesResult(errorMessage: errorMessage)
        }
    } else {
        let options: NSString.CompareOptions = isCaseSensitive ? [] : [.caseInsensitive]
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
    }

    if matchesWholeWords {
        ranges = ranges.filter { workspaceTextEditorRangeIsWholeWord($0, in: content) }
    }
    return WorkspaceTextEditorSearchMatchesResult(ranges: ranges)
}

func workspaceTextEditorSearchSessionState(
    query: String,
    in content: NSString,
    isCaseSensitive: Bool,
    matchesWholeWords: Bool,
    usesRegularExpression: Bool,
    selectedRange: NSRange
) -> WorkspaceTextEditorSearchSessionState {
    guard !query.isEmpty else {
        return WorkspaceTextEditorSearchSessionState()
    }

    let result = workspaceTextEditorSearchMatchesResult(
        query: query,
        in: content,
        isCaseSensitive: isCaseSensitive,
        matchesWholeWords: matchesWholeWords,
        usesRegularExpression: usesRegularExpression
    )
    let currentMatchIndex = result.ranges.firstIndex(where: { NSEqualRanges($0, selectedRange) }).map { $0 + 1 }
    return WorkspaceTextEditorSearchSessionState(
        query: query,
        matchCount: result.ranges.count,
        currentMatchIndex: currentMatchIndex,
        errorMessage: result.errorMessage
    )
}

func workspaceTextEditorEffectiveSearchHighlightSignature(
    contentRevision: Int,
    query: String,
    isCaseSensitive: Bool,
    matchesWholeWords: Bool,
    usesRegularExpression: Bool,
    selectedRange: NSRange
) -> WorkspaceTextEditorSearchHighlightSignature {
    guard !query.isEmpty else {
        return WorkspaceTextEditorSearchHighlightSignature(
            contentRevision: 0,
            query: "",
            isSearchCaseSensitive: false,
            matchesWholeWords: false,
            usesRegularExpression: false,
            selectedRange: NSRange(location: NSNotFound, length: 0)
        )
    }
    return WorkspaceTextEditorSearchHighlightSignature(
        contentRevision: contentRevision,
        query: query,
        isSearchCaseSensitive: isCaseSensitive,
        matchesWholeWords: matchesWholeWords,
        usesRegularExpression: usesRegularExpression,
        selectedRange: selectedRange
    )
}

@MainActor
private func applyTemporarySearchHighlights(
    searchResult: WorkspaceTextEditorSearchMatchesResult,
    selectedRange: NSRange,
    to textView: NSTextView
) {
    guard let layoutManager = textView.layoutManager else {
        return
    }

    let content = textView.string as NSString
    let fullRange = NSRange(location: 0, length: content.length)
    layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

    guard !searchResult.ranges.isEmpty else {
        return
    }

    let selectedRangeIsMatch = searchResult.ranges.contains(where: { NSEqualRanges($0, selectedRange) })
    for match in searchResult.ranges {
        layoutManager.addTemporaryAttribute(
            .backgroundColor,
            value: selectedRangeIsMatch && NSEqualRanges(match, selectedRange)
                ? NSColor.systemOrange.withAlphaComponent(0.42)
                : NSColor.systemYellow.withAlphaComponent(0.22),
            forCharacterRange: match
        )
    }
}

private func workspaceTextEditorRangeMatchesSearchResult(
    _ range: NSRange,
    searchResult: WorkspaceTextEditorSearchMatchesResult
) -> Bool {
    guard range.location != NSNotFound else {
        return false
    }
    return searchResult.ranges.contains(where: { NSEqualRanges($0, range) })
}

func workspaceTextEditorMatchRanges(
    query: String,
    in content: NSString,
    isCaseSensitive: Bool,
    matchesWholeWords: Bool,
    usesRegularExpression: Bool
) -> [NSRange] {
    workspaceTextEditorSearchMatchesResult(
        query: query,
        in: content,
        isCaseSensitive: isCaseSensitive,
        matchesWholeWords: matchesWholeWords,
        usesRegularExpression: usesRegularExpression
    ).ranges
}

func workspaceTextEditorRangeMatchesQuery(
    _ range: NSRange,
    query: String,
    in content: NSString,
    isCaseSensitive: Bool,
    matchesWholeWords: Bool,
    usesRegularExpression: Bool
) -> Bool {
    guard !query.isEmpty,
          range.location != NSNotFound,
          NSMaxRange(range) <= content.length
    else {
        return false
    }
    let result = workspaceTextEditorSearchMatchesResult(
        query: query,
        in: content,
        isCaseSensitive: isCaseSensitive,
        matchesWholeWords: matchesWholeWords,
        usesRegularExpression: usesRegularExpression
    )
    return workspaceTextEditorRangeMatchesSearchResult(range, searchResult: result)
}

func workspaceTextEditorNextMatch(
    query: String,
    in content: NSString,
    selectedRange: NSRange,
    isCaseSensitive: Bool,
    matchesWholeWords: Bool,
    usesRegularExpression: Bool
) -> NSRange? {
    let searchResult = workspaceTextEditorSearchMatchesResult(
        query: query,
        in: content,
        isCaseSensitive: isCaseSensitive,
        matchesWholeWords: matchesWholeWords,
        usesRegularExpression: usesRegularExpression
    )
    let matches = searchResult.ranges
    guard !matches.isEmpty else {
        return nil
    }

    let anchor = workspaceTextEditorRangeMatchesSearchResult(
        selectedRange,
        searchResult: searchResult
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
    isCaseSensitive: Bool,
    matchesWholeWords: Bool,
    usesRegularExpression: Bool
) -> NSRange? {
    let searchResult = workspaceTextEditorSearchMatchesResult(
        query: query,
        in: content,
        isCaseSensitive: isCaseSensitive,
        matchesWholeWords: matchesWholeWords,
        usesRegularExpression: usesRegularExpression
    )
    let matches = searchResult.ranges
    guard !matches.isEmpty else {
        return nil
    }

    let anchor = workspaceTextEditorRangeMatchesSearchResult(
        selectedRange,
        searchResult: searchResult
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
    isCaseSensitive: Bool,
    matchesWholeWords: Bool,
    usesRegularExpression: Bool,
    preservesReplacementCase: Bool
) -> (text: String, replacementCount: Int, firstReplacementLocation: Int?) {
    let matches = workspaceTextEditorMatchRanges(
        query: query,
        in: content,
        isCaseSensitive: isCaseSensitive,
        matchesWholeWords: matchesWholeWords,
        usesRegularExpression: usesRegularExpression
    )
    guard !matches.isEmpty else {
        return (content as String, 0, nil)
    }

    let source = content as String
    let mutable = NSMutableString(string: source)
    var offset = 0
    for match in matches {
        let adjusted = NSRange(location: match.location + offset, length: match.length)
        let replacementText = workspaceTextEditorResolvedReplacement(
            replacement,
            matchingRange: match,
            query: query,
            in: content,
            usesRegularExpression: usesRegularExpression,
            preservesReplacementCase: preservesReplacementCase
        )
        mutable.replaceCharacters(in: adjusted, with: replacementText)
        offset += (replacementText as NSString).length - match.length
    }
    return (mutable as String, matches.count, matches.first?.location)
}

func workspaceTextEditorResolvedReplacement(
    _ replacement: String,
    matchingRange: NSRange,
    query: String,
    in content: NSString,
    usesRegularExpression: Bool,
    preservesReplacementCase: Bool
) -> String {
    guard matchingRange.location != NSNotFound,
          NSMaxRange(matchingRange) <= content.length
    else {
        return replacement
    }

    let matchedText = content.substring(with: matchingRange)
    let resolvedReplacement: String
    if usesRegularExpression {
        guard let expression = workspaceTextEditorRegularExpression(
            query: query,
            isCaseSensitive: true
        ).expression else {
            resolvedReplacement = replacement
            return preservesReplacementCase
                ? workspaceTextEditorApplyingPreservedCase(replacement: resolvedReplacement, matchedText: matchedText)
                : resolvedReplacement
        }
        let fullRange = NSRange(location: 0, length: (matchedText as NSString).length)
        resolvedReplacement = expression.stringByReplacingMatches(
            in: matchedText,
            options: [],
            range: fullRange,
            withTemplate: replacement
        )
    } else {
        resolvedReplacement = replacement
    }

    guard preservesReplacementCase else {
        return resolvedReplacement
    }
    return workspaceTextEditorApplyingPreservedCase(
        replacement: resolvedReplacement,
        matchedText: matchedText
    )
}

func workspaceTextEditorApplyingPreservedCase(
    replacement: String,
    matchedText: String
) -> String {
    guard !replacement.isEmpty, !matchedText.isEmpty else {
        return replacement
    }

    if matchedText == matchedText.uppercased() {
        return replacement.uppercased()
    }
    if matchedText == matchedText.lowercased() {
        return replacement.lowercased()
    }
    if workspaceTextEditorIsCapitalizedWord(matchedText) {
        let lowered = replacement.lowercased()
        guard let first = lowered.first else {
            return replacement
        }
        return String(first).uppercased() + lowered.dropFirst()
    }
    return replacement
}

func workspaceTextEditorIsCapitalizedWord(_ value: String) -> Bool {
    guard let first = value.first else {
        return false
    }
    let tail = String(value.dropFirst())
    return String(first) == String(first).uppercased() && tail == tail.lowercased()
}

func workspaceTextEditorRangeIsWholeWord(
    _ range: NSRange,
    in content: NSString
) -> Bool {
    guard range.location != NSNotFound,
          range.length > 0,
          NSMaxRange(range) <= content.length
    else {
        return false
    }

    let lowerBoundaryIsWord = range.location > 0
        ? workspaceTextEditorIsWordCharacter(content.character(at: range.location - 1))
        : false
    let upperBoundaryIsWord = NSMaxRange(range) < content.length
        ? workspaceTextEditorIsWordCharacter(content.character(at: NSMaxRange(range)))
        : false
    return !lowerBoundaryIsWord && !upperBoundaryIsWord
}

func workspaceTextEditorIsWordCharacter(_ character: unichar) -> Bool {
    switch character {
    case 48 ... 57, 65 ... 90, 95, 97 ... 122:
        return true
    default:
        guard let scalar = UnicodeScalar(character) else {
            return false
        }
        return CharacterSet.alphanumerics.contains(scalar)
    }
}

func workspaceTextEditorMarkupModel(
    highlights: [WorkspaceDiffEditorHighlight],
    additionalMarkers: [WorkspaceEditorMarkupMarker] = [],
    searchQuery: String,
    in content: NSString,
    lineStartOffsets: [Int],
    isSearchCaseSensitive: Bool,
    matchesWholeWords: Bool,
    usesRegularExpression: Bool
) -> WorkspaceEditorMarkupModel {
    var markers = highlights.map { highlight in
        WorkspaceEditorMarkupMarker(
            id: "diff-\(highlight.kind.rawValue)-\(highlight.lineRange.startLine)-\(highlight.lineRange.lineCount)",
            kind: workspaceEditorMarkupMarkerKind(for: highlight.kind),
            lineRange: highlight.lineRange,
            lane: .lineStatus,
            showsInOverview: true,
            showsInGutter: true
        )
    }
    markers.append(contentsOf: additionalMarkers)

    let searchMatches = workspaceTextEditorMatchRanges(
        query: searchQuery,
        in: content,
        isCaseSensitive: isSearchCaseSensitive,
        matchesWholeWords: matchesWholeWords,
        usesRegularExpression: usesRegularExpression
    )
    markers.append(contentsOf: searchMatches.map { range in
        let lineIndex = WorkspaceTextEditorLineMetrics.lineIndex(
            forCharacterLocation: range.location,
            lineStartOffsets: lineStartOffsets
        )
        return WorkspaceEditorMarkupMarker(
            id: "search-\(range.location)-\(range.length)",
            kind: .searchMatch,
            lineRange: WorkspaceDiffLineRange(startLine: lineIndex, lineCount: 1),
            showsInOverview: true,
            showsInGutter: false
        )
    })

    return WorkspaceEditorMarkupModel(markers: markers)
}

func workspaceTextEditorOverviewMarkers(
    highlights: [WorkspaceDiffEditorHighlight],
    searchQuery: String,
    in content: NSString,
    lineStartOffsets: [Int],
    isSearchCaseSensitive: Bool,
    matchesWholeWords: Bool,
    usesRegularExpression: Bool
) -> [WorkspaceEditorMarkupMarker] {
    workspaceTextEditorMarkupModel(
        highlights: highlights,
        additionalMarkers: [],
        searchQuery: searchQuery,
        in: content,
        lineStartOffsets: lineStartOffsets,
        isSearchCaseSensitive: isSearchCaseSensitive,
        matchesWholeWords: matchesWholeWords,
        usesRegularExpression: usesRegularExpression
    ).overviewMarkers
}

func workspaceTextEditorAnnotationLaneWidth(
    for markupMarkers: [WorkspaceEditorMarkupMarker],
    font: NSFont
) -> CGFloat {
    let annotationTexts = markupMarkers.compactMap { marker -> String? in
        guard marker.showsInGutter, marker.lane == .annotations else {
            return nil
        }
        return marker.annotationText
    }
    guard let widest = annotationTexts.max(by: { $0.count < $1.count }) else {
        return 0
    }
    let sample = widest.prefix(10)
    let width = (String(sample) as NSString).size(withAttributes: [.font: font]).width
    guard width > 0 else {
        return 0
    }
    return ceil(width + workspaceTextEditorGutterLaneSpacing)
}

func workspaceTextEditorPreferredGutterMarkers(
    _ markers: [WorkspaceEditorMarkupMarker],
    for lane: WorkspaceEditorMarkupLane
) -> [WorkspaceEditorMarkupMarker] {
    let grouped = Dictionary(grouping: markers) { $0.lineRange.startLine }
    return grouped.values.compactMap { candidates in
        candidates
            .filter { $0.lane == lane }
            .sorted {
                if $0.priority == $1.priority {
                    return $0.kind.rawValue < $1.kind.rawValue
                }
                return $0.priority > $1.priority
            }
            .first
    }
    .sorted { $0.lineRange.startLine < $1.lineRange.startLine }
}

func workspaceTextEditorRulerLineRect(
    lineRange: WorkspaceDiffLineRange,
    contentOffsetY: CGFloat,
    insetTop: CGFloat,
    lineHeight: CGFloat
) -> NSRect {
    let startY = WorkspaceTextEditorLineMetrics.lineOriginY(
        forLineIndex: lineRange.startLine,
        insetTop: insetTop,
        lineHeight: lineHeight
    ) - contentOffsetY
    let endY = WorkspaceTextEditorLineMetrics.lineOriginY(
        forLineIndex: lineRange.startLine + max(1, lineRange.lineCount),
        insetTop: insetTop,
        lineHeight: lineHeight
    ) - contentOffsetY
    return NSRect(x: 0, y: startY, width: 0, height: max(3, endY - startY))
}

func workspaceTextEditorDrawGutterIcon(
    _ icon: WorkspaceEditorMarkupIcon,
    in rect: NSRect,
    color: NSColor
) {
    color.setFill()
    color.setStroke()
    switch icon {
    case .circle:
        NSBezierPath(ovalIn: rect).fill()
    case .bookmark:
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.line(to: NSPoint(x: rect.midX, y: rect.minY + rect.height * 0.32))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY))
        path.close()
        path.fill()
    case .triangle:
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.midX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY))
        path.close()
        path.fill()
    case .chevron:
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY))
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    case .exclamation:
        let stem = NSBezierPath(roundedRect: NSRect(
            x: rect.midX - 0.9,
            y: rect.minY + rect.height * 0.26,
            width: 1.8,
            height: rect.height * 0.54
        ), xRadius: 0.9, yRadius: 0.9)
        stem.fill()
        NSBezierPath(ovalIn: NSRect(
            x: rect.midX - 1.1,
            y: rect.minY + 0.4,
            width: 2.2,
            height: 2.2
        )).fill()
    }
}

@MainActor
func workspaceTextEditorViewportRange(for scrollView: NSScrollView) -> ClosedRange<CGFloat> {
    let documentHeight = max(scrollView.documentView?.frame.height ?? 0, 1)
    let visibleRect = scrollView.contentView.bounds
    let lower = min(max(visibleRect.minY / documentHeight, 0), 1)
    let upper = min(max(visibleRect.maxY / documentHeight, lower), 1)
    return lower...upper
}

func workspaceEditorMarkupMarkerKind(
    for highlightKind: WorkspaceDiffEditorHighlightKind
) -> WorkspaceEditorMarkupMarkerKind {
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
