import Foundation

public enum WorkspaceEditorDocumentKind: String, Equatable, Sendable {
    case text
    case binary
    case unsupported
    case missing
}

public enum WorkspaceEditorExternalChangeState: String, Equatable, Sendable {
    case inSync
    case modifiedOnDisk
    case removedOnDisk
}

public enum WorkspaceEditorTabOpeningPolicy: String, Equatable, Sendable {
    case preview
    case regular
    case pinned
}

public func workspaceEditorContentFingerprint(_ text: String) -> UInt64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    hash ^= UInt64(text.utf8.count)
    hash &*= 1_099_511_628_211
    return hash
}

public enum WorkspaceEditorSyntaxStyle: String, Equatable, Sendable {
    case plainText
    case swift
    case objectiveC
    case cpp
    case csharp
    case json
    case markdown
    case yaml
    case shell
    case xml
    case html
    case css
    case javascript
    case typescript
    case properties
    case java
    case kotlin
    case python
    case ruby
    case go
    case rust
    case sql

    public static func infer(fromFilePath filePath: String) -> WorkspaceEditorSyntaxStyle {
        let fileExtension = URL(fileURLWithPath: filePath).pathExtension.lowercased()
        switch fileExtension {
        case "swift":
            return .swift
        case "m", "mm", "h":
            return .objectiveC
        case "c", "cc", "cpp", "cxx", "hpp", "hh", "hxx":
            return .cpp
        case "cs":
            return .csharp
        case "json":
            return .json
        case "md", "markdown":
            return .markdown
        case "yml", "yaml":
            return .yaml
        case "sh", "bash", "zsh", "fish", "command":
            return .shell
        case "xml", "plist", "xib", "storyboard", "svg":
            return .xml
        case "html", "htm", "xhtml":
            return .html
        case "css", "scss", "less":
            return .css
        case "js", "mjs", "cjs", "jsx":
            return .javascript
        case "ts", "tsx":
            return .typescript
        case "properties", "env", "toml", "ini":
            return .properties
        case "java":
            return .java
        case "kt", "kts":
            return .kotlin
        case "py":
            return .python
        case "rb":
            return .ruby
        case "go":
            return .go
        case "rs":
            return .rust
        case "sql":
            return .sql
        default:
            return .plainText
        }
    }
}

public struct WorkspaceEditorDisplayOptions: Codable, Equatable, Sendable {
    public var showsLineNumbers: Bool
    public var highlightsCurrentLine: Bool
    public var usesSoftWraps: Bool
    public var showsWhitespaceCharacters: Bool
    public var showsRightMargin: Bool
    public var rightMarginColumn: Int

    public init(
        showsLineNumbers: Bool = true,
        highlightsCurrentLine: Bool = true,
        usesSoftWraps: Bool = false,
        showsWhitespaceCharacters: Bool = false,
        showsRightMargin: Bool = false,
        rightMarginColumn: Int = 120
    ) {
        self.showsLineNumbers = showsLineNumbers
        self.highlightsCurrentLine = highlightsCurrentLine
        self.usesSoftWraps = usesSoftWraps
        self.showsWhitespaceCharacters = showsWhitespaceCharacters
        self.showsRightMargin = showsRightMargin
        self.rightMarginColumn = min(max(rightMarginColumn, 40), 240)
    }
}

public struct WorkspaceEditorSearchPresentationState: Equatable, Sendable {
    public var query: String
    public var replacement: String
    public var isPresented: Bool
    public var showsReplace: Bool
    public var isCaseSensitive: Bool
    public var matchesWholeWords: Bool
    public var usesRegularExpression: Bool
    public var preservesReplacementCase: Bool

    public init(
        query: String = "",
        replacement: String = "",
        isPresented: Bool = false,
        showsReplace: Bool = false,
        isCaseSensitive: Bool = false,
        matchesWholeWords: Bool = false,
        usesRegularExpression: Bool = false,
        preservesReplacementCase: Bool = false
    ) {
        self.query = query
        self.replacement = replacement
        self.isPresented = isPresented
        self.showsReplace = showsReplace
        self.isCaseSensitive = isCaseSensitive
        self.matchesWholeWords = matchesWholeWords
        self.usesRegularExpression = usesRegularExpression
        self.preservesReplacementCase = preservesReplacementCase
    }
}

public struct WorkspaceEditorRuntimeSessionState: Equatable, Sendable {
    public var searchPresentation: WorkspaceEditorSearchPresentationState

    public init(searchPresentation: WorkspaceEditorSearchPresentationState = .init()) {
        self.searchPresentation = searchPresentation
    }
}

public struct WorkspaceEditorGroupState: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var tabIDs: [String]
    public var selectedTabID: String?

    public init(
        id: String,
        tabIDs: [String] = [],
        selectedTabID: String? = nil
    ) {
        self.id = id
        self.tabIDs = tabIDs
        self.selectedTabID = selectedTabID
    }
}

public struct WorkspaceEditorPresentationState: Codable, Equatable, Sendable {
    public static let defaultSplitRatio = 0.5

    public var groups: [WorkspaceEditorGroupState]
    public var activeGroupID: String?
    public var splitAxis: WorkspaceSplitAxis?
    public var splitRatio: Double

    public init(
        groups: [WorkspaceEditorGroupState] = [],
        activeGroupID: String? = nil,
        splitAxis: WorkspaceSplitAxis? = nil,
        splitRatio: Double = WorkspaceEditorPresentationState.defaultSplitRatio
    ) {
        self.groups = groups
        self.activeGroupID = activeGroupID
        self.splitAxis = splitAxis
        self.splitRatio = min(max(splitRatio, 0.15), 0.85)
    }
}

public struct WorkspaceEditorDocumentSnapshot: Equatable, Sendable {
    public var filePath: String
    public var kind: WorkspaceEditorDocumentKind
    public var text: String
    public var isEditable: Bool
    public var message: String?
    public var modificationDate: SwiftDate?
    public var contentFingerprint: UInt64?

    public init(
        filePath: String,
        kind: WorkspaceEditorDocumentKind,
        text: String = "",
        isEditable: Bool,
        message: String? = nil,
        modificationDate: SwiftDate? = nil,
        contentFingerprint: UInt64? = nil
    ) {
        self.filePath = filePath
        self.kind = kind
        self.text = text
        self.isEditable = isEditable
        self.message = message
        self.modificationDate = modificationDate
        self.contentFingerprint = contentFingerprint
    }
}

public struct WorkspaceEditorTabState: Identifiable, Equatable, Sendable {
    public var id: String
    public var identity: String
    public var projectPath: String
    public var filePath: String
    public var title: String
    public var isPinned: Bool
    public var isPreview: Bool
    public var kind: WorkspaceEditorDocumentKind
    public var text: String
    public var isEditable: Bool
    public var isDirty: Bool
    public var isLoading: Bool
    public var isSaving: Bool
    public var externalChangeState: WorkspaceEditorExternalChangeState
    public var message: String?
    public var lastLoadedModificationDate: SwiftDate?
    public var savedContentFingerprint: UInt64?

    public init(
        id: String,
        identity: String,
        projectPath: String,
        filePath: String,
        title: String,
        isPinned: Bool = false,
        isPreview: Bool = false,
        kind: WorkspaceEditorDocumentKind,
        text: String = "",
        isEditable: Bool = false,
        isDirty: Bool = false,
        isLoading: Bool = false,
        isSaving: Bool = false,
        externalChangeState: WorkspaceEditorExternalChangeState = .inSync,
        message: String? = nil,
        lastLoadedModificationDate: SwiftDate? = nil,
        savedContentFingerprint: UInt64? = nil
    ) {
        self.id = id
        self.identity = identity
        self.projectPath = projectPath
        self.filePath = filePath
        self.title = title
        self.isPinned = isPinned
        self.isPreview = isPreview
        self.kind = kind
        self.text = text
        self.isEditable = isEditable
        self.isDirty = isDirty
        self.isLoading = isLoading
        self.isSaving = isSaving
        self.externalChangeState = externalChangeState
        self.message = message
        self.lastLoadedModificationDate = lastLoadedModificationDate
        self.savedContentFingerprint = savedContentFingerprint
    }
}

public struct WorkspaceEditorCloseRequest: Identifiable, Equatable, Sendable {
    public var id: String { "\(projectPath)|\(tabID)" }
    public var projectPath: String
    public var tabID: String
    public var title: String
    public var filePath: String
    public var isDirty: Bool
    public var externalChangeState: WorkspaceEditorExternalChangeState

    public init(
        projectPath: String,
        tabID: String,
        title: String,
        filePath: String,
        isDirty: Bool,
        externalChangeState: WorkspaceEditorExternalChangeState
    ) {
        self.projectPath = projectPath
        self.tabID = tabID
        self.title = title
        self.filePath = filePath
        self.isDirty = isDirty
        self.externalChangeState = externalChangeState
    }
}
