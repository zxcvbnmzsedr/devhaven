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

struct WorkspaceTextEditorDecorationSignature: Equatable {
    var text: String
    var highlights: [WorkspaceDiffEditorHighlight]
    var inlineHighlights: [WorkspaceDiffEditorInlineHighlight]
}

struct WorkspaceTextEditorView: NSViewRepresentable {
    let editorID: String
    @Binding var text: String
    let isEditable: Bool
    let highlights: [WorkspaceDiffEditorHighlight]
    let inlineHighlights: [WorkspaceDiffEditorInlineHighlight]
    let scrollSyncState: Binding<WorkspaceTextEditorScrollSyncState>?
    let scrollRequestState: Binding<WorkspaceTextEditorScrollRequestState>?

    init(
        editorID: String,
        text: Binding<String>,
        isEditable: Bool,
        highlights: [WorkspaceDiffEditorHighlight] = [],
        inlineHighlights: [WorkspaceDiffEditorInlineHighlight] = [],
        scrollSyncState: Binding<WorkspaceTextEditorScrollSyncState>? = nil,
        scrollRequestState: Binding<WorkspaceTextEditorScrollRequestState>? = nil
    ) {
        self.editorID = editorID
        self._text = text
        self.isEditable = isEditable
        self.highlights = highlights
        self.inlineHighlights = inlineHighlights
        self.scrollSyncState = scrollSyncState
        self.scrollRequestState = scrollRequestState
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            editorID: editorID,
            text: $text,
            scrollSyncState: scrollSyncState,
            scrollRequestState: scrollRequestState
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = NSTextView()
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
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.string = text
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        context.coordinator.attach(scrollView: scrollView, textView: textView)
        context.coordinator.applyDecorationsIfNeeded(
            highlights: highlights,
            inlineHighlights: inlineHighlights,
            force: true
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }
        context.coordinator.attach(scrollView: scrollView, textView: textView)
        let selectedRanges = textView.selectedRanges
        let textChanged = context.coordinator.applyTextIfNeeded(text, to: textView)
        if textChanged {
            textView.selectedRanges = selectedRanges
        }
        textView.isEditable = isEditable
        context.coordinator.applyDecorationsIfNeeded(
            highlights: highlights,
            inlineHighlights: inlineHighlights,
            force: textChanged
        )
        context.coordinator.applySyncedScrollIfNeeded()
        context.coordinator.scrollToRequestedLineIfNeeded()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private static let remoteScrollTolerance: CGFloat = 2
        private static let localScrollEmissionThreshold: CGFloat = 0.01

        private let editorID: String
        private var text: Binding<String>
        private let scrollSyncState: Binding<WorkspaceTextEditorScrollSyncState>?
        private let scrollRequestState: Binding<WorkspaceTextEditorScrollRequestState>?
        private weak var scrollView: NSScrollView?
        private weak var textView: NSTextView?
        private var isApplyingRemoteScroll = false
        private var lastAppliedRevision = -1
        private var lastAppliedScrollRequestRevision = -1
        private var lastAppliedDecorationSignature: WorkspaceTextEditorDecorationSignature?
        private var lastProgrammaticScrollOriginY: CGFloat?
        private var lastProgrammaticScrollRevision: Int?

        init(
            editorID: String,
            text: Binding<String>,
            scrollSyncState: Binding<WorkspaceTextEditorScrollSyncState>?,
            scrollRequestState: Binding<WorkspaceTextEditorScrollRequestState>?
        ) {
            self.editorID = editorID
            self.text = text
            self.scrollSyncState = scrollSyncState
            self.scrollRequestState = scrollRequestState
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(scrollView: NSScrollView, textView: NSTextView) {
            let scrollViewChanged = self.scrollView !== scrollView
            self.scrollView = scrollView
            self.textView = textView
            guard scrollViewChanged else {
                return
            }

            NotificationCenter.default.removeObserver(self)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleBoundsDidChangeNotification(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func applyTextIfNeeded(_ text: String, to textView: NSTextView) -> Bool {
            guard textView.string != text else {
                return false
            }
            textView.string = text
            lastAppliedDecorationSignature = nil
            return true
        }

        func applyDecorationsIfNeeded(
            highlights: [WorkspaceDiffEditorHighlight],
            inlineHighlights: [WorkspaceDiffEditorInlineHighlight],
            force: Bool
        ) {
            guard let textView else {
                return
            }
            let signature = WorkspaceTextEditorDecorationSignature(
                text: textView.string,
                highlights: highlights,
                inlineHighlights: inlineHighlights
            )
            guard force || lastAppliedDecorationSignature != signature else {
                return
            }

            applyHighlights(highlights, to: textView)
            applyInlineHighlights(inlineHighlights, to: textView)
            lastAppliedDecorationSignature = signature
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            if text.wrappedValue != textView.string {
                text.wrappedValue = textView.string
            }
            lastAppliedDecorationSignature = nil
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

        @objc
        private func handleBoundsDidChangeNotification(_ notification: Notification) {
            handleBoundsDidChange()
        }

        private func handleBoundsDidChange() {
            guard let scrollView,
                  let scrollSyncState
            else {
                return
            }
            let currentOriginY = scrollView.contentView.bounds.origin.y
            let currentState = scrollSyncState.wrappedValue

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
    }
}

@MainActor
private func applyHighlights(_ highlights: [WorkspaceDiffEditorHighlight], to textView: NSTextView) {
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
    textStorage.endEditing()
}

@MainActor
private func applyInlineHighlights(_ inlineHighlights: [WorkspaceDiffEditorInlineHighlight], to textView: NSTextView) {
    guard let textStorage = textView.textStorage else {
        return
    }
    let content = textView.string as NSString
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
