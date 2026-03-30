import Foundation

// 本文件只保留 runtime diff tab 本体与 compare / merge / patch 文档模型。
// request chain / session / pane metadata 等框架层结构已拆到独立模型文件中。

public enum WorkspaceDiffViewerMode: String, Equatable, Sendable {
    case sideBySide
    case unified
}

public enum WorkspaceDiffSource: Equatable, Sendable {
    case gitLogCommitFile(repositoryPath: String, commitHash: String, filePath: String)
    case workingTreeChange(
        repositoryPath: String,
        executionPath: String,
        filePath: String,
        group: WorkspaceCommitChangeGroup?,
        status: WorkspaceCommitChangeStatus?,
        oldPath: String?
    )

    public var identity: String {
        switch self {
        case let .gitLogCommitFile(repositoryPath, commitHash, filePath):
            return "git-log|\(repositoryPath)|\(commitHash)|\(filePath)"
        case let .workingTreeChange(_, executionPath, filePath, _, _, _):
            return "working-tree|\(executionPath)|\(filePath)"
        }
    }
}

public struct WorkspaceDiffOpenRequest: Equatable, Sendable {
    public var projectPath: String
    public var source: WorkspaceDiffSource
    public var preferredTitle: String
    public var preferredViewerMode: WorkspaceDiffViewerMode
    public var requestChain: WorkspaceDiffRequestChain?
    public var identityOverride: String?
    public var originContext: WorkspaceDiffOriginContext?

    public init(
        projectPath: String,
        source: WorkspaceDiffSource,
        preferredTitle: String,
        preferredViewerMode: WorkspaceDiffViewerMode = .sideBySide,
        requestChain: WorkspaceDiffRequestChain? = nil,
        identityOverride: String? = nil,
        originContext: WorkspaceDiffOriginContext? = nil
    ) {
        self.projectPath = projectPath
        self.source = source
        self.preferredTitle = preferredTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.preferredViewerMode = preferredViewerMode
        self.requestChain = requestChain
        self.identityOverride = identityOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.originContext = originContext
    }

    public var identity: String {
        if let identityOverride, !identityOverride.isEmpty {
            return identityOverride
        }
        return source.identity
    }
}

public struct WorkspaceDiffTabState: Identifiable, Equatable, Sendable {
    public var id: String
    public var identity: String
    public var title: String
    public var source: WorkspaceDiffSource
    public var viewerMode: WorkspaceDiffViewerMode
    public var requestChain: WorkspaceDiffRequestChain?
    public var originContext: WorkspaceDiffOriginContext?

    public init(
        id: String,
        identity: String,
        title: String,
        source: WorkspaceDiffSource,
        viewerMode: WorkspaceDiffViewerMode,
        requestChain: WorkspaceDiffRequestChain? = nil,
        originContext: WorkspaceDiffOriginContext? = nil
    ) {
        self.id = id
        self.identity = identity
        self.title = title
        self.source = source
        self.viewerMode = viewerMode
        self.requestChain = requestChain
        self.originContext = originContext
    }
}

public enum WorkspacePresentedTabSelection: Equatable, Sendable {
    case terminal(String)
    case editor(String)
    case diff(String)
}

public struct WorkspaceDiffOriginContext: Equatable, Sendable {
    public var presentedTabSelection: WorkspacePresentedTabSelection?
    public var focusedArea: WorkspaceFocusedArea

    public init(
        presentedTabSelection: WorkspacePresentedTabSelection?,
        focusedArea: WorkspaceFocusedArea
    ) {
        self.presentedTabSelection = presentedTabSelection
        self.focusedArea = focusedArea
    }
}

public struct WorkspacePresentedTabItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var selection: WorkspacePresentedTabSelection
    public var isSelected: Bool
    public var isPinned: Bool
    public var isPreview: Bool

    public init(
        id: String,
        title: String,
        selection: WorkspacePresentedTabSelection,
        isSelected: Bool,
        isPinned: Bool = false,
        isPreview: Bool = false
    ) {
        self.id = id
        self.title = title
        self.selection = selection
        self.isSelected = isSelected
        self.isPinned = isPinned
        self.isPreview = isPreview
    }
}

public enum WorkspaceDiffDocumentKind: Equatable, Sendable {
    case text
    case empty
    case binary
    case unsupported
}

public enum WorkspaceDiffLineKind: Equatable, Sendable {
    case context
    case removed
    case added
    case meta
}

public struct WorkspaceDiffLine: Equatable, Sendable {
    public var kind: WorkspaceDiffLineKind
    public var oldLineNumber: Int?
    public var newLineNumber: Int?
    public var text: String

    public init(kind: WorkspaceDiffLineKind, oldLineNumber: Int?, newLineNumber: Int?, text: String) {
        self.kind = kind
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.text = text
    }
}

public struct WorkspaceDiffSideBySideRow: Equatable, Sendable {
    public var leftLine: WorkspaceDiffLine?
    public var rightLine: WorkspaceDiffLine?

    public init(leftLine: WorkspaceDiffLine?, rightLine: WorkspaceDiffLine?) {
        self.leftLine = leftLine
        self.rightLine = rightLine
    }
}

public struct WorkspaceDiffHunk: Equatable, Sendable {
    public var header: String
    public var lines: [WorkspaceDiffLine]
    public var sideBySideRows: [WorkspaceDiffSideBySideRow]

    public init(header: String, lines: [WorkspaceDiffLine], sideBySideRows: [WorkspaceDiffSideBySideRow]) {
        self.header = header
        self.lines = lines
        self.sideBySideRows = sideBySideRows
    }
}

public struct WorkspaceDiffParsedDocument: Equatable, Sendable {
    public var kind: WorkspaceDiffDocumentKind
    public var oldPath: String?
    public var newPath: String?
    public var headerLines: [String]
    public var hunks: [WorkspaceDiffHunk]
    public var message: String?

    public init(
        kind: WorkspaceDiffDocumentKind,
        oldPath: String?,
        newPath: String?,
        headerLines: [String],
        hunks: [WorkspaceDiffHunk],
        message: String? = nil
    ) {
        self.kind = kind
        self.oldPath = oldPath
        self.newPath = newPath
        self.headerLines = headerLines
        self.hunks = hunks
        self.message = message
    }
}

public enum WorkspaceDiffCompareMode: String, Equatable, Sendable {
    case staged
    case unstaged
    case untracked
}

public struct WorkspaceDiffLineRange: Equatable, Sendable {
    public var startLine: Int
    public var lineCount: Int

    public init(startLine: Int, lineCount: Int) {
        self.startLine = max(0, startLine)
        self.lineCount = max(0, lineCount)
    }

    public var endLine: Int {
        startLine + lineCount
    }

    public var displayText: String {
        let displayStart = lineCount == 0 ? startLine : startLine + 1
        let displayEnd = lineCount == 0 ? displayStart : startLine + lineCount
        if displayStart == displayEnd {
            return "\(displayStart)"
        }
        return "\(displayStart)-\(displayEnd)"
    }
}

public enum WorkspaceDiffEditorHighlightKind: String, Equatable, Sendable {
    case added
    case removed
    case changed
    case conflict
}

public struct WorkspaceDiffEditorHighlight: Equatable, Sendable {
    public var kind: WorkspaceDiffEditorHighlightKind
    public var lineRange: WorkspaceDiffLineRange

    public init(kind: WorkspaceDiffEditorHighlightKind, lineRange: WorkspaceDiffLineRange) {
        self.kind = kind
        self.lineRange = lineRange
    }
}

public struct WorkspaceDiffInlineRange: Equatable, Sendable {
    public var startColumn: Int
    public var length: Int

    public init(startColumn: Int, length: Int) {
        self.startColumn = max(0, startColumn)
        self.length = max(0, length)
    }
}

public struct WorkspaceDiffEditorInlineHighlight: Equatable, Sendable {
    public var kind: WorkspaceDiffEditorHighlightKind
    public var lineIndex: Int
    public var range: WorkspaceDiffInlineRange

    public init(kind: WorkspaceDiffEditorHighlightKind, lineIndex: Int, range: WorkspaceDiffInlineRange) {
        self.kind = kind
        self.lineIndex = max(0, lineIndex)
        self.range = range
    }
}

public enum WorkspaceDiffCompareBlockAction: String, Equatable, Sendable {
    case stage
    case unstage
    case revert
}

public struct WorkspaceDiffCompareBlock: Equatable, Sendable, Identifiable {
    public var id: String
    public var summary: String
    public var leftLineRange: WorkspaceDiffLineRange
    public var rightLineRange: WorkspaceDiffLineRange
    public var leftLines: [String]
    public var rightLines: [String]
    public var leftHasTrailingNewline: Bool
    public var rightHasTrailingNewline: Bool

    public init(
        id: String,
        summary: String,
        leftLineRange: WorkspaceDiffLineRange,
        rightLineRange: WorkspaceDiffLineRange,
        leftLines: [String],
        rightLines: [String],
        leftHasTrailingNewline: Bool = false,
        rightHasTrailingNewline: Bool = false
    ) {
        self.id = id
        self.summary = summary
        self.leftLineRange = leftLineRange
        self.rightLineRange = rightLineRange
        self.leftLines = leftLines
        self.rightLines = rightLines
        self.leftHasTrailingNewline = leftHasTrailingNewline
        self.rightHasTrailingNewline = rightHasTrailingNewline
    }
}

public struct WorkspaceDiffMergeConflictBlock: Equatable, Sendable, Identifiable {
    public var id: String
    public var summary: String
    public var resultLineRange: WorkspaceDiffLineRange
    public var resultOursLineRange: WorkspaceDiffLineRange?
    public var resultTheirsLineRange: WorkspaceDiffLineRange?
    public var oursLineRange: WorkspaceDiffLineRange?
    public var theirsLineRange: WorkspaceDiffLineRange?
    public var oursText: String
    public var theirsText: String
    public var baseText: String?

    public init(
        id: String,
        summary: String,
        resultLineRange: WorkspaceDiffLineRange,
        resultOursLineRange: WorkspaceDiffLineRange?,
        resultTheirsLineRange: WorkspaceDiffLineRange?,
        oursLineRange: WorkspaceDiffLineRange?,
        theirsLineRange: WorkspaceDiffLineRange?,
        oursText: String,
        theirsText: String,
        baseText: String? = nil
    ) {
        self.id = id
        self.summary = summary
        self.resultLineRange = resultLineRange
        self.resultOursLineRange = resultOursLineRange
        self.resultTheirsLineRange = resultTheirsLineRange
        self.oursLineRange = oursLineRange
        self.theirsLineRange = theirsLineRange
        self.oursText = oursText
        self.theirsText = theirsText
        self.baseText = baseText
    }
}

public struct WorkspaceDiffEditorPane: Equatable, Sendable {
    public var title: String
    public var path: String?
    public var text: String
    public var isEditable: Bool
    public var highlights: [WorkspaceDiffEditorHighlight]
    public var inlineHighlights: [WorkspaceDiffEditorInlineHighlight]

    public init(
        title: String,
        path: String?,
        text: String,
        isEditable: Bool,
        highlights: [WorkspaceDiffEditorHighlight] = [],
        inlineHighlights: [WorkspaceDiffEditorInlineHighlight] = []
    ) {
        self.title = title
        self.path = path
        self.text = text
        self.isEditable = isEditable
        self.highlights = highlights
        self.inlineHighlights = inlineHighlights
    }
}

public struct WorkspaceDiffCompareDocument: Equatable, Sendable {
    public var mode: WorkspaceDiffCompareMode
    public var leftPane: WorkspaceDiffEditorPane
    public var rightPane: WorkspaceDiffEditorPane
    public var blocks: [WorkspaceDiffCompareBlock]

    public init(
        mode: WorkspaceDiffCompareMode,
        leftPane: WorkspaceDiffEditorPane,
        rightPane: WorkspaceDiffEditorPane,
        blocks: [WorkspaceDiffCompareBlock] = []
    ) {
        self.mode = mode
        self.leftPane = leftPane
        self.rightPane = rightPane
        self.blocks = blocks
    }
}

public struct WorkspaceDiffMergeDocument: Equatable, Sendable {
    public var oursPane: WorkspaceDiffEditorPane
    public var basePane: WorkspaceDiffEditorPane
    public var theirsPane: WorkspaceDiffEditorPane
    public var resultPane: WorkspaceDiffEditorPane
    public var conflictBlocks: [WorkspaceDiffMergeConflictBlock]

    public init(
        oursPane: WorkspaceDiffEditorPane,
        basePane: WorkspaceDiffEditorPane,
        theirsPane: WorkspaceDiffEditorPane,
        resultPane: WorkspaceDiffEditorPane,
        conflictBlocks: [WorkspaceDiffMergeConflictBlock] = []
    ) {
        self.oursPane = oursPane
        self.basePane = basePane
        self.theirsPane = theirsPane
        self.resultPane = resultPane
        self.conflictBlocks = conflictBlocks
    }
}

public struct WorkspaceDiffConflictFileContents: Equatable, Sendable {
    public var base: String
    public var ours: String
    public var theirs: String
    public var result: String

    public init(base: String, ours: String, theirs: String, result: String) {
        self.base = base
        self.ours = ours
        self.theirs = theirs
        self.result = result
    }
}

public enum WorkspaceDiffLoadedDocument: Equatable, Sendable {
    case patch(WorkspaceDiffParsedDocument)
    case compare(WorkspaceDiffCompareDocument)
    case merge(WorkspaceDiffMergeDocument)
}

public enum WorkspaceDiffMergeAction: Equatable, Sendable {
    case acceptOurs
    case acceptTheirs
    case acceptBoth
}

public enum WorkspaceDiffDocumentLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(WorkspaceDiffLoadedDocument)
    case failed(String)
}

public struct WorkspaceDiffDocumentState: Equatable, Sendable {
    public var title: String
    public var viewerMode: WorkspaceDiffViewerMode
    public var loadState: WorkspaceDiffDocumentLoadState

    public init(
        title: String,
        viewerMode: WorkspaceDiffViewerMode,
        loadState: WorkspaceDiffDocumentLoadState = .idle
    ) {
        self.title = title
        self.viewerMode = viewerMode
        self.loadState = loadState
    }

    public var loadedDocument: WorkspaceDiffParsedDocument? {
        guard case let .loaded(document) = loadState,
              case let .patch(patchDocument) = document
        else {
            return nil
        }
        return patchDocument
    }

    public var loadedPatchDocument: WorkspaceDiffParsedDocument? {
        loadedDocument
    }

    public var loadedCompareDocument: WorkspaceDiffCompareDocument? {
        guard case let .loaded(document) = loadState,
              case let .compare(compareDocument) = document
        else {
            return nil
        }
        return compareDocument
    }

    public var loadedMergeDocument: WorkspaceDiffMergeDocument? {
        guard case let .loaded(document) = loadState,
              case let .merge(mergeDocument) = document
        else {
            return nil
        }
        return mergeDocument
    }

    public var errorMessage: String? {
        guard case let .failed(message) = loadState else {
            return nil
        }
        return message
    }
}
