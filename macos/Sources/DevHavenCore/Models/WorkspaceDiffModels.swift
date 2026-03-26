import Foundation

public enum WorkspaceDiffViewerMode: String, Equatable, Sendable {
    case sideBySide
    case unified
}

public enum WorkspaceDiffSource: Equatable, Sendable {
    case gitLogCommitFile(repositoryPath: String, commitHash: String, filePath: String)
    case workingTreeChange(repositoryPath: String, executionPath: String, filePath: String)

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
    public var originContext: WorkspaceDiffOriginContext?

    public init(
        projectPath: String,
        source: WorkspaceDiffSource,
        preferredTitle: String,
        preferredViewerMode: WorkspaceDiffViewerMode = .sideBySide,
        originContext: WorkspaceDiffOriginContext? = nil
    ) {
        self.projectPath = projectPath
        self.source = source
        self.preferredTitle = preferredTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.preferredViewerMode = preferredViewerMode
        self.originContext = originContext
    }

    public var identity: String {
        source.identity
    }
}

public struct WorkspaceDiffTabState: Identifiable, Equatable, Sendable {
    public var id: String
    public var identity: String
    public var title: String
    public var source: WorkspaceDiffSource
    public var viewerMode: WorkspaceDiffViewerMode
    public var originContext: WorkspaceDiffOriginContext?

    public init(
        id: String,
        identity: String,
        title: String,
        source: WorkspaceDiffSource,
        viewerMode: WorkspaceDiffViewerMode,
        originContext: WorkspaceDiffOriginContext? = nil
    ) {
        self.id = id
        self.identity = identity
        self.title = title
        self.source = source
        self.viewerMode = viewerMode
        self.originContext = originContext
    }
}

public enum WorkspacePresentedTabSelection: Equatable, Sendable {
    case terminal(String)
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

    public init(
        id: String,
        title: String,
        selection: WorkspacePresentedTabSelection,
        isSelected: Bool
    ) {
        self.id = id
        self.title = title
        self.selection = selection
        self.isSelected = isSelected
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

public enum WorkspaceDiffDocumentLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(WorkspaceDiffParsedDocument)
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
        guard case let .loaded(document) = loadState else {
            return nil
        }
        return document
    }

    public var errorMessage: String? {
        guard case let .failed(message) = loadState else {
            return nil
        }
        return message
    }
}
