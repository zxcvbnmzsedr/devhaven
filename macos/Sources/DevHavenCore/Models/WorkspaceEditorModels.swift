import Foundation

public enum WorkspaceEditorDocumentKind: String, Equatable, Sendable {
    case text
    case binary
    case unsupported
    case missing
}

public struct WorkspaceEditorDocumentSnapshot: Equatable, Sendable {
    public var filePath: String
    public var kind: WorkspaceEditorDocumentKind
    public var text: String
    public var isEditable: Bool
    public var message: String?
    public var modificationDate: SwiftDate?

    public init(
        filePath: String,
        kind: WorkspaceEditorDocumentKind,
        text: String = "",
        isEditable: Bool,
        message: String? = nil,
        modificationDate: SwiftDate? = nil
    ) {
        self.filePath = filePath
        self.kind = kind
        self.text = text
        self.isEditable = isEditable
        self.message = message
        self.modificationDate = modificationDate
    }
}

public struct WorkspaceEditorTabState: Identifiable, Equatable, Sendable {
    public var id: String
    public var identity: String
    public var projectPath: String
    public var filePath: String
    public var title: String
    public var kind: WorkspaceEditorDocumentKind
    public var text: String
    public var isEditable: Bool
    public var isDirty: Bool
    public var isLoading: Bool
    public var isSaving: Bool
    public var message: String?
    public var lastLoadedModificationDate: SwiftDate?

    public init(
        id: String,
        identity: String,
        projectPath: String,
        filePath: String,
        title: String,
        kind: WorkspaceEditorDocumentKind,
        text: String = "",
        isEditable: Bool = false,
        isDirty: Bool = false,
        isLoading: Bool = false,
        isSaving: Bool = false,
        message: String? = nil,
        lastLoadedModificationDate: SwiftDate? = nil
    ) {
        self.id = id
        self.identity = identity
        self.projectPath = projectPath
        self.filePath = filePath
        self.title = title
        self.kind = kind
        self.text = text
        self.isEditable = isEditable
        self.isDirty = isDirty
        self.isLoading = isLoading
        self.isSaving = isSaving
        self.message = message
        self.lastLoadedModificationDate = lastLoadedModificationDate
    }
}
