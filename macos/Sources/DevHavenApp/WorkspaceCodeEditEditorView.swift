import SwiftUI
import AppKit
import DevHavenCore
@preconcurrency import CodeEditSourceEditor
import CodeEditLanguages
@preconcurrency import CodeEditTextView

@MainActor
final class WorkspaceCodeEditEditorBridge: NSObject, @preconcurrency TextViewCoordinator {
    private static let findSelector = #selector(NSTextView.performFindPanelAction(_:))
    private static let showReplaceAction = NSFindPanelAction(rawValue: 12)
    private static let diffLineEmphasisGroup = "devhaven.diff.lines"
    private static let diffInlineEmphasisGroup = "devhaven.diff.inline"
    private static let remoteScrollTolerance: CGFloat = 2
    private static let localScrollEmissionThreshold: CGFloat = 0.01

    private weak var controller: TextViewController?
    private weak var observedScrollClipView: NSClipView?
    private var editorID: String?
    private var normalizedScrollChangeHandler: ((CGFloat) -> Void)?
    private var latestDecorationSnapshot = WorkspaceCodeEditEditorDecorationSnapshot()
    private var pendingScrollSyncState: WorkspaceTextEditorScrollSyncState?
    private var pendingScrollRequestState: WorkspaceTextEditorScrollRequestState?
    private var lastAppliedScrollSyncRevision = -1
    private var lastAppliedScrollRequestRevision = -1
    private var isApplyingRemoteScroll = false
    private var lastProgrammaticScrollOriginY: CGFloat?
    private var lastProgrammaticScrollRevision: Int?

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
        installScrollObserverIfNeeded()
        applyDecorationsIfNeeded()
        applyPendingScrollStatesIfNeeded()
    }

    func destroy() {
        removeScrollObserver()
        clearDecorations()
        controller = nil
    }

    func requestFocus() {
        guard let controller else {
            return
        }
        controller.view.window?.makeFirstResponder(controller.textView)
    }

    func showFindPanel() {
        performFindAction(.showFindPanel)
    }

    func showReplacePanel() {
        if let action = Self.showReplaceAction {
            performFindAction(action)
        }
    }

    func findNext() {
        performFindAction(.next)
    }

    func findPrevious() {
        performFindAction(.previous)
    }

    func useSelectionForFind() {
        performFindAction(.setFindString)
    }

    func hideFindPanel() {
        requestFocus()
        controller?.textView.perform(#selector(NSResponder.cancelOperation(_:)), with: nil)
    }

    func goToLine(_ line: Int) {
        guard line > 0, let controller else {
            return
        }
        requestFocus()
        controller.setCursorPositions(
            [CursorPosition(line: line, column: 1)],
            scrollToVisible: true
        )
    }

    func configureRuntime(
        editorID: String?,
        normalizedScrollChangeHandler: ((CGFloat) -> Void)?
    ) {
        self.editorID = editorID
        self.normalizedScrollChangeHandler = normalizedScrollChangeHandler
        installScrollObserverIfNeeded()
    }

    func updateDecorations(
        highlights: [WorkspaceDiffEditorHighlight],
        inlineHighlights: [WorkspaceDiffEditorInlineHighlight]
    ) {
        let nextSnapshot = WorkspaceCodeEditEditorDecorationSnapshot(
            highlights: highlights,
            inlineHighlights: inlineHighlights
        )
        guard latestDecorationSnapshot != nextSnapshot else {
            return
        }
        latestDecorationSnapshot = nextSnapshot
        applyDecorationsIfNeeded()
    }

    func updateScrollSyncState(_ state: WorkspaceTextEditorScrollSyncState?) {
        pendingScrollSyncState = state
        applyPendingScrollSyncIfNeeded()
    }

    func updateScrollRequestState(_ state: WorkspaceTextEditorScrollRequestState?) {
        pendingScrollRequestState = state
        applyPendingScrollRequestIfNeeded()
    }

    private func performFindAction(_ action: NSFindPanelAction) {
        requestFocus()
        let item = NSMenuItem()
        item.tag = Int(action.rawValue)
        controller?.textView.perform(Self.findSelector, with: item)
    }

    @MainActor
    private func installScrollObserverIfNeeded() {
        removeScrollObserver()
        guard let controller, normalizedScrollChangeHandler != nil else {
            return
        }
        let clipView = controller.scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollBoundsDidChangeNotification(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
        observedScrollClipView = clipView
    }

    @objc
    private func handleScrollBoundsDidChangeNotification(_ notification: Notification) {
        handleScrollBoundsDidChange()
    }

    @MainActor
    private func removeScrollObserver() {
        if let observedScrollClipView {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: observedScrollClipView
            )
            self.observedScrollClipView = nil
        }
    }

    @MainActor
    private func handleScrollBoundsDidChange() {
        guard
              let controller,
              let scrollView = controller.scrollView,
              let normalizedScrollChangeHandler
        else {
            return
        }

        let currentOriginY = scrollView.contentView.bounds.origin.y
        let currentState = pendingScrollSyncState

        if let lastProgrammaticScrollRevision,
           let lastProgrammaticScrollOriginY,
           ((currentState?.revision == lastProgrammaticScrollRevision)
            || (pendingScrollRequestState?.revision == lastProgrammaticScrollRevision)),
           abs(currentOriginY - lastProgrammaticScrollOriginY) < Self.remoteScrollTolerance {
            isApplyingRemoteScroll = false
            return
        }

        if isApplyingRemoteScroll {
            isApplyingRemoteScroll = false
            lastProgrammaticScrollOriginY = nil
            lastProgrammaticScrollRevision = nil
            return
        }

        let normalizedOffset = normalizedYOffset(for: scrollView)
        if let currentState,
           currentState.sourceID == editorID,
           abs(currentState.normalizedYOffset - normalizedOffset) < Self.localScrollEmissionThreshold {
            return
        }
        if let currentState,
           currentState.sourceID != editorID,
           abs(currentState.normalizedYOffset - normalizedOffset) < Self.localScrollEmissionThreshold {
            lastProgrammaticScrollOriginY = nil
            lastProgrammaticScrollRevision = nil
            isApplyingRemoteScroll = false
            return
        }

        lastProgrammaticScrollOriginY = nil
        lastProgrammaticScrollRevision = nil
        normalizedScrollChangeHandler(normalizedOffset)
    }

    @MainActor
    private func applyPendingScrollStatesIfNeeded() {
        applyPendingScrollSyncIfNeeded()
        applyPendingScrollRequestIfNeeded()
    }

    @MainActor
    private func applyPendingScrollSyncIfNeeded() {
        guard let state = pendingScrollSyncState,
              let controller,
              let editorID,
              state.sourceID != editorID,
              state.revision != lastAppliedScrollSyncRevision
        else {
            return
        }
        let clipView = controller.scrollView.contentView
        let maxOffset = maxVerticalOffset(for: controller.scrollView)
        let targetY = min(maxOffset, max(0, maxOffset * state.normalizedYOffset))
        isApplyingRemoteScroll = true
        lastAppliedScrollSyncRevision = state.revision
        if abs(clipView.bounds.origin.y - targetY) < Self.remoteScrollTolerance {
            isApplyingRemoteScroll = false
            lastProgrammaticScrollOriginY = nil
            lastProgrammaticScrollRevision = nil
            return
        }
        performProgrammaticScroll(
            to: CGPoint(x: clipView.bounds.origin.x, y: targetY),
            in: controller.scrollView
        )
        lastProgrammaticScrollOriginY = targetY
        lastProgrammaticScrollRevision = state.revision
    }

    @MainActor
    private func applyPendingScrollRequestIfNeeded() {
        guard let state = pendingScrollRequestState,
              let controller,
              let editorID,
              state.revision != lastAppliedScrollRequestRevision,
              let targetLine = state.lineTargets[editorID]
        else {
            return
        }
        let clampedLine = min(
            max(0, targetLine),
            max(controller.textView.layoutManager.lineCount - 1, 0)
        )
        guard let linePosition = controller.textView.layoutManager.textLineForIndex(clampedLine) else {
            return
        }
        let clipView = controller.scrollView.contentView
        let maxOffset = maxVerticalOffset(for: controller.scrollView)
        let targetY = min(maxOffset, max(0, linePosition.yPos - 28))
        isApplyingRemoteScroll = true
        lastAppliedScrollRequestRevision = state.revision
        performProgrammaticScroll(
            to: CGPoint(x: clipView.bounds.origin.x, y: targetY),
            in: controller.scrollView
        )
        lastProgrammaticScrollOriginY = targetY
        lastProgrammaticScrollRevision = state.revision
    }

    @MainActor
    private func performProgrammaticScroll(to point: CGPoint, in scrollView: NSScrollView) {
        scrollView.contentView.scroll(to: point)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    @MainActor
    private func applyDecorationsIfNeeded() {
        guard let controller else {
            return
        }
        let content = controller.textView.string as NSString
        let emphasisManager = controller.textView.emphasisManager
        emphasisManager?.replaceEmphases(
            workspaceCodeEditLineEmphases(
                highlights: latestDecorationSnapshot.highlights,
                in: content
            ),
            for: Self.diffLineEmphasisGroup
        )
        emphasisManager?.replaceEmphases(
            workspaceCodeEditInlineEmphases(
                inlineHighlights: latestDecorationSnapshot.inlineHighlights,
                in: content
            ),
            for: Self.diffInlineEmphasisGroup
        )
    }

    @MainActor
    private func clearDecorations() {
        guard let emphasisManager = controller?.textView.emphasisManager else {
            return
        }
        emphasisManager.removeEmphases(for: Self.diffLineEmphasisGroup)
        emphasisManager.removeEmphases(for: Self.diffInlineEmphasisGroup)
    }

    @MainActor
    private func maxVerticalOffset(for scrollView: NSScrollView) -> CGFloat {
        let documentHeight = scrollView.documentView?.frame.height ?? 0
        return max(0, documentHeight - scrollView.contentView.bounds.height)
    }

    @MainActor
    private func normalizedYOffset(for scrollView: NSScrollView) -> CGFloat {
        let maxOffset = maxVerticalOffset(for: scrollView)
        guard maxOffset > 0 else {
            return 0
        }
        return min(max(scrollView.contentView.bounds.origin.y / maxOffset, 0), 1)
    }
}

private struct WorkspaceCodeEditEditorDecorationSnapshot: Equatable {
    var highlights: [WorkspaceDiffEditorHighlight] = []
    var inlineHighlights: [WorkspaceDiffEditorInlineHighlight] = []
}

struct WorkspaceCodeEditEditorView: View {
    let filePath: String
    @Binding var text: String
    let isEditable: Bool
    let shouldRequestFocus: Bool
    let displayOptions: WorkspaceEditorDisplayOptions
    let bridge: WorkspaceCodeEditEditorBridge
    var editorID: String? = nil
    var highlights: [WorkspaceDiffEditorHighlight] = []
    var inlineHighlights: [WorkspaceDiffEditorInlineHighlight] = []
    var scrollSyncState: Binding<WorkspaceTextEditorScrollSyncState>? = nil
    var scrollRequestState: Binding<WorkspaceTextEditorScrollRequestState>? = nil

    @State private var editorState = SourceEditorState()

    var body: some View {
        SourceEditor(
            $text,
            language: detectedLanguage,
            configuration: configuration,
            state: $editorState,
            coordinators: [bridge]
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: WorkspaceCodeEditEditorTheme.background))
        .onAppear {
            bridge.configureRuntime(
                editorID: editorID,
                normalizedScrollChangeHandler: handleNormalizedScrollChange(_:)
            )
            bridge.updateDecorations(highlights: highlights, inlineHighlights: inlineHighlights)
            bridge.updateScrollSyncState(scrollSyncState?.wrappedValue)
            bridge.updateScrollRequestState(scrollRequestState?.wrappedValue)
            if shouldRequestFocus {
                bridge.requestFocus()
            }
        }
        .onChange(of: editorID) { _, nextValue in
            bridge.configureRuntime(
                editorID: nextValue,
                normalizedScrollChangeHandler: handleNormalizedScrollChange(_:)
            )
        }
        .onChange(of: decorationSnapshot) { _, nextValue in
            bridge.updateDecorations(
                highlights: nextValue.highlights,
                inlineHighlights: nextValue.inlineHighlights
            )
        }
        .onChange(of: shouldRequestFocus) { _, nextValue in
            if nextValue {
                bridge.requestFocus()
            }
        }
        .onChange(of: scrollSyncState?.wrappedValue) { _, nextValue in
            bridge.updateScrollSyncState(nextValue)
        }
        .onChange(of: scrollRequestState?.wrappedValue) { _, nextValue in
            bridge.updateScrollRequestState(nextValue)
        }
    }

    private var detectedLanguage: CodeLanguage {
        CodeLanguage.detectLanguageFrom(
            url: URL(filePath: filePath),
            prefixBuffer: String(text.prefix(2_048)),
            suffixBuffer: String(text.suffix(2_048))
        )
    }

    private var configuration: SourceEditorConfiguration {
        SourceEditorConfiguration(
            appearance: .init(
                theme: WorkspaceCodeEditEditorTheme.theme(
                    highlightsCurrentLine: displayOptions.highlightsCurrentLine
                ),
                font: .monospacedSystemFont(ofSize: 12, weight: .regular),
                wrapLines: displayOptions.usesSoftWraps,
                tabWidth: 4
            ),
            behavior: .init(
                isEditable: isEditable,
                indentOption: .spaces(count: 4),
                reformatAtColumn: displayOptions.rightMarginColumn
            ),
            peripherals: .init(
                showGutter: displayOptions.showsLineNumbers,
                showMinimap: false,
                showReformattingGuide: displayOptions.showsRightMargin,
                showFoldingRibbon: displayOptions.showsLineNumbers,
                invisibleCharactersConfiguration: displayOptions.showsWhitespaceCharacters
                    ? InvisibleCharactersConfiguration(
                        showSpaces: true,
                        showTabs: true,
                        showLineEndings: false
                    )
                    : .empty
            )
        )
    }

    private var decorationSnapshot: WorkspaceCodeEditEditorDecorationSnapshot {
        WorkspaceCodeEditEditorDecorationSnapshot(
            highlights: highlights,
            inlineHighlights: inlineHighlights
        )
    }

    private func handleNormalizedScrollChange(_ normalizedYOffset: CGFloat) {
        guard let scrollSyncState,
              let editorID
        else {
            return
        }
        let currentState = scrollSyncState.wrappedValue
        let clampedOffset = min(max(normalizedYOffset, 0), 1)
        if currentState.sourceID == editorID,
           abs(currentState.normalizedYOffset - clampedOffset) < 0.0005 {
            return
        }
        scrollSyncState.wrappedValue = WorkspaceTextEditorScrollSyncState(
            sourceID: editorID,
            normalizedYOffset: clampedOffset,
            revision: currentState.revision + 1
        )
    }
}

private enum WorkspaceCodeEditEditorTheme {
    static let background = dynamicColor(
        light: NSColor(calibratedRed: 0.985, green: 0.987, blue: 0.995, alpha: 1),
        dark: NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.10, alpha: 1)
    )

    private static let text = attribute(
        light: NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.18, alpha: 0.96),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.96)
    )

    private static let insertionPoint = dynamicColor(
        light: NSColor(calibratedRed: 0.13, green: 0.36, blue: 0.96, alpha: 1),
        dark: NSColor(calibratedRed: 0.34, green: 0.33, blue: 1.0, alpha: 1)
    )

    private static let invisibles = attribute(
        light: NSColor(calibratedRed: 0.28, green: 0.33, blue: 0.43, alpha: 0.55),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.4)
    )

    private static let highlightedLineBackground = dynamicColor(
        light: NSColor(calibratedRed: 0.91, green: 0.94, blue: 0.98, alpha: 1),
        dark: NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.15, alpha: 1)
    )

    private static let selection = dynamicColor(
        light: NSColor(calibratedRed: 0.13, green: 0.36, blue: 0.96, alpha: 0.22),
        dark: NSColor(calibratedRed: 0.34, green: 0.33, blue: 1.0, alpha: 0.24)
    )

    private static let keywords = attribute(
        light: NSColor.systemBlue,
        dark: NSColor.systemPurple
    )

    private static let commands = attribute(
        light: NSColor.systemBlue,
        dark: NSColor.systemPurple
    )

    private static let types = attribute(
        light: NSColor.systemTeal,
        dark: NSColor.systemMint
    )

    private static let attributes = attribute(
        light: NSColor.systemOrange,
        dark: NSColor.systemOrange
    )

    private static let variables = attribute(
        light: NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.18, alpha: 0.96),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.92)
    )

    private static let values = attribute(
        light: NSColor.systemIndigo,
        dark: NSColor.systemIndigo
    )

    private static let numbers = attribute(
        light: NSColor.systemOrange,
        dark: NSColor.systemOrange
    )

    private static let strings = attribute(
        light: NSColor.systemRed,
        dark: NSColor.systemRed
    )

    private static let characters = attribute(
        light: NSColor.systemRed,
        dark: NSColor.systemRed
    )

    private static let comments = attribute(
        light: NSColor.systemGreen,
        dark: NSColor.systemGreen
    )

    private static let themeWithCurrentLineHighlight = makeTheme(lineHighlight: highlightedLineBackground)
    private static let themeWithoutCurrentLineHighlight = makeTheme(lineHighlight: .clear)

    static func theme(highlightsCurrentLine: Bool) -> EditorTheme {
        if highlightsCurrentLine {
            return themeWithCurrentLineHighlight
        }
        return themeWithoutCurrentLineHighlight
    }

    private static func makeTheme(lineHighlight: NSColor) -> EditorTheme {
        EditorTheme(
            text: text,
            insertionPoint: insertionPoint,
            invisibles: invisibles,
            background: background,
            lineHighlight: lineHighlight,
            selection: selection,
            keywords: keywords,
            commands: commands,
            types: types,
            attributes: attributes,
            variables: variables,
            values: values,
            numbers: numbers,
            strings: strings,
            characters: characters,
            comments: comments
        )
    }

    private static func attribute(light: NSColor, dark: NSColor) -> EditorTheme.Attribute {
        EditorTheme.Attribute(color: dynamicColor(light: light, dark: dark))
    }

    private static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .aqua:
                return light
            default:
                return dark
            }
        }
    }
}

private func workspaceCodeEditLineEmphases(
    highlights: [WorkspaceDiffEditorHighlight],
    in content: NSString
) -> [Emphasis] {
    highlights.compactMap { highlight in
        let range = workspaceCodeEditCharacterRange(for: highlight.lineRange, in: content)
        guard range.location != NSNotFound, range.length > 0 else {
            return nil
        }
        return Emphasis(
            range: range,
            style: .outline(color: workspaceCodeEditHighlightColor(for: highlight.kind), fill: true),
            inactive: true
        )
    }
}

private func workspaceCodeEditInlineEmphases(
    inlineHighlights: [WorkspaceDiffEditorInlineHighlight],
    in content: NSString
) -> [Emphasis] {
    inlineHighlights.compactMap { inlineHighlight in
        let range = workspaceCodeEditCharacterRange(
            forLineIndex: inlineHighlight.lineIndex,
            inlineRange: inlineHighlight.range,
            in: content
        )
        guard range.location != NSNotFound, range.length > 0 else {
            return nil
        }
        return Emphasis(
            range: range,
            style: .outline(color: workspaceCodeEditInlineHighlightColor(for: inlineHighlight.kind), fill: true),
            inactive: true
        )
    }
}

private func workspaceCodeEditHighlightColor(for kind: WorkspaceDiffEditorHighlightKind) -> NSColor {
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

private func workspaceCodeEditInlineHighlightColor(for kind: WorkspaceDiffEditorHighlightKind) -> NSColor {
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

private func workspaceCodeEditCharacterRange(
    for lineRange: WorkspaceDiffLineRange,
    in content: NSString
) -> NSRange {
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
        content.getLineStart(
            nil,
            end: &lineEnd,
            contentsEnd: nil,
            for: NSRange(location: searchLocation, length: 0)
        )
        searchLocation = max(lineEnd, searchLocation + 1)
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

private func workspaceCodeEditCharacterRange(
    forLineIndex lineIndex: Int,
    inlineRange: WorkspaceDiffInlineRange,
    in content: NSString
) -> NSRange {
    guard lineIndex >= 0, inlineRange.length > 0 else {
        return NSRange(location: NSNotFound, length: 0)
    }
    let lineRange = workspaceCodeEditCharacterRange(
        for: WorkspaceDiffLineRange(startLine: lineIndex, lineCount: 1),
        in: content
    )
    guard lineRange.location != NSNotFound else {
        return NSRange(location: NSNotFound, length: 0)
    }
    let contentsEnd = max(
        lineRange.location,
        lineRange.location + lineRange.length - workspaceCodeEditLineRangeTerminatorLength(in: content, lineRange: lineRange)
    )
    let safeStart = min(lineRange.location + inlineRange.startColumn, contentsEnd)
    let safeEnd = min(safeStart + inlineRange.length, contentsEnd)
    return NSRange(location: safeStart, length: max(0, safeEnd - safeStart))
}

private func workspaceCodeEditLineRangeTerminatorLength(in content: NSString, lineRange: NSRange) -> Int {
    guard lineRange.length > 0 else {
        return 0
    }
    let lastCharacter = content.substring(with: NSRange(location: lineRange.location + lineRange.length - 1, length: 1))
    if lastCharacter == "\n" {
        if lineRange.length >= 2 {
            let previousCharacter = content.substring(
                with: NSRange(location: lineRange.location + lineRange.length - 2, length: 1)
            )
            if previousCharacter == "\r" {
                return 2
            }
        }
        return 1
    }
    if lastCharacter == "\r" {
        return 1
    }
    return 0
}
