import Foundation

public struct WorkspaceRestoreSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var savedAt: Date
    public var activeProjectPath: String?
    public var selectedProjectPath: String?
    public var sessions: [ProjectWorkspaceRestoreSnapshot]

    public init(
        version: Int = Self.currentVersion,
        savedAt: Date = Date(),
        activeProjectPath: String?,
        selectedProjectPath: String?,
        sessions: [ProjectWorkspaceRestoreSnapshot]
    ) {
        self.version = version
        self.savedAt = savedAt
        self.activeProjectPath = activeProjectPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.selectedProjectPath = selectedProjectPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.sessions = sessions
    }

    public var isEmpty: Bool {
        sessions.isEmpty
    }
}

public struct ProjectWorkspaceRestoreSnapshot: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case projectPath
        case rootProjectPath
        case isQuickTerminal
        case transientDisplayProject
        case workspaceRootContext
        case workspaceAlignmentGroupID
        case workspaceId
        case selectedTabId
        case selectedPresentedTab
        case nextTabNumber
        case nextPaneNumber
        case editorTabs
        case editorPresentation
        case tabs
    }

    public var projectPath: String
    public var rootProjectPath: String
    public var isQuickTerminal: Bool
    public var transientDisplayProject: Project?
    public var workspaceRootContext: WorkspaceRootSessionContext?
    public var workspaceAlignmentGroupID: String?
    public var workspaceId: String
    public var selectedTabId: String?
    public var selectedPresentedTab: WorkspaceRestorePresentedTabSelection?
    public var nextTabNumber: Int
    public var nextPaneNumber: Int
    public var editorTabs: [WorkspaceEditorTabRestoreSnapshot]
    public var editorPresentation: WorkspaceEditorPresentationState?
    public var tabs: [WorkspaceTabRestoreSnapshot]

    public init(
        projectPath: String,
        rootProjectPath: String,
        isQuickTerminal: Bool,
        transientDisplayProject: Project? = nil,
        workspaceRootContext: WorkspaceRootSessionContext? = nil,
        workspaceAlignmentGroupID: String? = nil,
        workspaceId: String,
        selectedTabId: String?,
        selectedPresentedTab: WorkspaceRestorePresentedTabSelection? = nil,
        nextTabNumber: Int,
        nextPaneNumber: Int,
        editorTabs: [WorkspaceEditorTabRestoreSnapshot] = [],
        editorPresentation: WorkspaceEditorPresentationState? = nil,
        tabs: [WorkspaceTabRestoreSnapshot]
    ) {
        self.projectPath = projectPath
        self.rootProjectPath = rootProjectPath
        self.isQuickTerminal = isQuickTerminal
        self.transientDisplayProject = transientDisplayProject
        self.workspaceRootContext = workspaceRootContext
        self.workspaceAlignmentGroupID = workspaceAlignmentGroupID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.workspaceId = workspaceId
        self.selectedTabId = selectedTabId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.selectedPresentedTab = selectedPresentedTab
        self.nextTabNumber = max(nextTabNumber, 1)
        self.nextPaneNumber = max(nextPaneNumber, 1)
        self.editorTabs = editorTabs
        self.editorPresentation = editorPresentation
        self.tabs = tabs
    }

}

extension ProjectWorkspaceRestoreSnapshot {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            projectPath: try container.decode(String.self, forKey: .projectPath),
            rootProjectPath: try container.decode(String.self, forKey: .rootProjectPath),
            isQuickTerminal: try container.decode(Bool.self, forKey: .isQuickTerminal),
            transientDisplayProject: try container.decodeIfPresent(Project.self, forKey: .transientDisplayProject),
            workspaceRootContext: try container.decodeIfPresent(WorkspaceRootSessionContext.self, forKey: .workspaceRootContext),
            workspaceAlignmentGroupID: try container.decodeIfPresent(String.self, forKey: .workspaceAlignmentGroupID),
            workspaceId: try container.decode(String.self, forKey: .workspaceId),
            selectedTabId: try container.decodeIfPresent(String.self, forKey: .selectedTabId),
            selectedPresentedTab: try container.decodeIfPresent(WorkspaceRestorePresentedTabSelection.self, forKey: .selectedPresentedTab),
            nextTabNumber: try container.decode(Int.self, forKey: .nextTabNumber),
            nextPaneNumber: try container.decode(Int.self, forKey: .nextPaneNumber),
            editorTabs: try container.decodeIfPresent([WorkspaceEditorTabRestoreSnapshot].self, forKey: .editorTabs) ?? [],
            editorPresentation: try container.decodeIfPresent(WorkspaceEditorPresentationState.self, forKey: .editorPresentation),
            tabs: try container.decode([WorkspaceTabRestoreSnapshot].self, forKey: .tabs)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projectPath, forKey: .projectPath)
        try container.encode(rootProjectPath, forKey: .rootProjectPath)
        try container.encode(isQuickTerminal, forKey: .isQuickTerminal)
        try container.encodeIfPresent(transientDisplayProject, forKey: .transientDisplayProject)
        try container.encodeIfPresent(workspaceRootContext, forKey: .workspaceRootContext)
        try container.encodeIfPresent(workspaceAlignmentGroupID, forKey: .workspaceAlignmentGroupID)
        try container.encode(workspaceId, forKey: .workspaceId)
        try container.encodeIfPresent(selectedTabId, forKey: .selectedTabId)
        try container.encodeIfPresent(selectedPresentedTab, forKey: .selectedPresentedTab)
        try container.encode(nextTabNumber, forKey: .nextTabNumber)
        try container.encode(nextPaneNumber, forKey: .nextPaneNumber)
        try container.encode(editorTabs, forKey: .editorTabs)
        try container.encodeIfPresent(editorPresentation, forKey: .editorPresentation)
        try container.encode(tabs, forKey: .tabs)
    }
}

public enum WorkspaceRestorePresentedTabSelection: Equatable, Sendable {
    case terminal(String)
    case editor(String)
}

extension WorkspaceRestorePresentedTabSelection: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case id
    }

    enum SelectionType: String, Codable {
        case terminal
        case editor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SelectionType.self, forKey: .type)
        let id = try container.decode(String.self, forKey: .id)
        switch type {
        case .terminal:
            self = .terminal(id)
        case .editor:
            self = .editor(id)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .terminal(id):
            try container.encode(SelectionType.terminal, forKey: .type)
            try container.encode(id, forKey: .id)
        case let .editor(id):
            try container.encode(SelectionType.editor, forKey: .type)
            try container.encode(id, forKey: .id)
        }
    }
}

public struct WorkspaceEditorTabRestoreSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var filePath: String
    public var title: String
    public var isPinned: Bool

    public init(
        id: String,
        filePath: String,
        title: String,
        isPinned: Bool
    ) {
        self.id = id
        self.filePath = filePath
        self.title = title
        self.isPinned = isPinned
    }
}

public struct WorkspaceTabRestoreSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var focusedPaneId: String
    public var tree: WorkspacePaneTreeRestoreSnapshot

    public init(id: String, title: String, focusedPaneId: String, tree: WorkspacePaneTreeRestoreSnapshot) {
        self.id = id
        self.title = title
        self.focusedPaneId = focusedPaneId
        self.tree = tree
    }
}

public struct WorkspacePaneTreeRestoreSnapshot: Codable, Equatable, Sendable {
    public indirect enum Node: Codable, Equatable, Sendable {
        case leaf(WorkspacePaneRestoreSnapshot)
        case split(WorkspaceSplitRestoreSnapshot)

        enum CodingKeys: String, CodingKey {
            case type
            case leaf
            case split
        }

        enum NodeType: String, Codable {
            case leaf
            case split
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(NodeType.self, forKey: .type)
            switch type {
            case .leaf:
                self = .leaf(try container.decode(WorkspacePaneRestoreSnapshot.self, forKey: .leaf))
            case .split:
                self = .split(try container.decode(WorkspaceSplitRestoreSnapshot.self, forKey: .split))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .leaf(pane):
                try container.encode(NodeType.leaf, forKey: .type)
                try container.encode(pane, forKey: .leaf)
            case let .split(split):
                try container.encode(NodeType.split, forKey: .type)
                try container.encode(split, forKey: .split)
            }
        }
    }

    public var root: Node
    public var zoomedPaneId: String?

    public init(root: Node, zoomedPaneId: String?) {
        self.root = root
        self.zoomedPaneId = zoomedPaneId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var leaves: [WorkspacePaneRestoreSnapshot] {
        root.leaves
    }
}

public struct WorkspaceSplitRestoreSnapshot: Codable, Equatable, Sendable {
    public var direction: WorkspaceSplitAxis
    public var ratio: Double
    public var left: WorkspacePaneTreeRestoreSnapshot.Node
    public var right: WorkspacePaneTreeRestoreSnapshot.Node

    public init(
        direction: WorkspaceSplitAxis,
        ratio: Double,
        left: WorkspacePaneTreeRestoreSnapshot.Node,
        right: WorkspacePaneTreeRestoreSnapshot.Node
    ) {
        self.direction = direction
        self.ratio = min(max(ratio, 0.1), 0.9)
        self.left = left
        self.right = right
    }
}

public struct WorkspacePaneSnapshotTextRef: Codable, Equatable, Sendable {
    public var storageKey: String

    public init(storageKey: String) {
        self.storageKey = storageKey
    }

    public static func forPaneID(_ paneID: String) -> Self {
        Self(storageKey: makeStorageKey(rawValue: paneID))
    }

    public static func forPaneSnapshot(_ paneID: String, generationID: String) -> Self {
        Self(storageKey: makeStorageKey(rawValue: "\(generationID)|\(paneID)"))
    }

    private static func makeStorageKey(rawValue: String) -> String {
        let encoded = Data(rawValue.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return encoded
    }
}

public struct WorkspacePaneItemRestoreSnapshot: Equatable, Sendable {
    public var surfaceId: String
    public var terminalSessionId: String
    public var kind: WorkspacePaneItemKind
    public var restoredWorkingDirectory: String?
    public var restoredTitle: String?
    public var agentSummary: String?
    public var snapshotTextRef: WorkspacePaneSnapshotTextRef?
    public var snapshotText: String?
    public var browserTitle: String?
    public var browserURLString: String?
    public var browserIsLoading: Bool?

    public init(
        surfaceId: String,
        terminalSessionId: String,
        kind: WorkspacePaneItemKind = .terminal,
        restoredWorkingDirectory: String?,
        restoredTitle: String?,
        agentSummary: String?,
        snapshotTextRef: WorkspacePaneSnapshotTextRef?,
        snapshotText: String?,
        browserTitle: String? = nil,
        browserURLString: String? = nil,
        browserIsLoading: Bool? = nil
    ) {
        self.surfaceId = surfaceId
        self.terminalSessionId = terminalSessionId
        self.kind = kind
        self.restoredWorkingDirectory = restoredWorkingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.restoredTitle = restoredTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.agentSummary = agentSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.snapshotTextRef = snapshotTextRef
        self.snapshotText = snapshotText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.browserTitle = browserTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.browserURLString = browserURLString?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.browserIsLoading = browserIsLoading
    }
}

public struct WorkspacePaneRestoreSnapshot: Equatable, Sendable {
    public var paneId: String
    public var selectedItemId: String?
    public var items: [WorkspacePaneItemRestoreSnapshot]

    public var selectedItem: WorkspacePaneItemRestoreSnapshot? {
        if let selectedItemId,
           let selected = items.first(where: { $0.surfaceId == selectedItemId }) {
            return selected
        }
        return items.last ?? items.first
    }

    public var surfaceId: String {
        selectedItem?.surfaceId ?? ""
    }

    public var terminalSessionId: String {
        selectedItem?.terminalSessionId ?? ""
    }

    public var restoredWorkingDirectory: String? {
        selectedItem?.restoredWorkingDirectory
    }

    public var restoredTitle: String? {
        selectedItem?.restoredTitle
    }

    public var agentSummary: String? {
        selectedItem?.agentSummary
    }

    public var snapshotTextRef: WorkspacePaneSnapshotTextRef? {
        selectedItem?.snapshotTextRef
    }

    public var snapshotText: String? {
        selectedItem?.snapshotText
    }

    public init(
        paneId: String,
        selectedItemId: String?,
        items: [WorkspacePaneItemRestoreSnapshot]
    ) {
        self.paneId = paneId
        self.selectedItemId = selectedItemId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.items = items
    }

    public func item(for surfaceId: String?) -> WorkspacePaneItemRestoreSnapshot? {
        guard let surfaceId else { return nil }
        return items.first(where: { $0.surfaceId == surfaceId })
    }
}

extension WorkspacePaneItemRestoreSnapshot: Codable {
    enum CodingKeys: String, CodingKey {
        case surfaceId
        case terminalSessionId
        case kind
        case restoredWorkingDirectory
        case restoredTitle
        case agentSummary
        case snapshotTextRef
        case browserTitle
        case browserURLString
        case browserIsLoading
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            surfaceId: try container.decode(String.self, forKey: .surfaceId),
            terminalSessionId: try container.decode(String.self, forKey: .terminalSessionId),
            kind: try container.decodeIfPresent(WorkspacePaneItemKind.self, forKey: .kind) ?? .terminal,
            restoredWorkingDirectory: try container.decodeIfPresent(String.self, forKey: .restoredWorkingDirectory),
            restoredTitle: try container.decodeIfPresent(String.self, forKey: .restoredTitle),
            agentSummary: try container.decodeIfPresent(String.self, forKey: .agentSummary),
            snapshotTextRef: try container.decodeIfPresent(WorkspacePaneSnapshotTextRef.self, forKey: .snapshotTextRef),
            snapshotText: nil,
            browserTitle: try container.decodeIfPresent(String.self, forKey: .browserTitle),
            browserURLString: try container.decodeIfPresent(String.self, forKey: .browserURLString),
            browserIsLoading: try container.decodeIfPresent(Bool.self, forKey: .browserIsLoading)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(surfaceId, forKey: .surfaceId)
        try container.encode(terminalSessionId, forKey: .terminalSessionId)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(restoredWorkingDirectory, forKey: .restoredWorkingDirectory)
        try container.encodeIfPresent(restoredTitle, forKey: .restoredTitle)
        try container.encodeIfPresent(agentSummary, forKey: .agentSummary)
        try container.encodeIfPresent(snapshotTextRef, forKey: .snapshotTextRef)
        try container.encodeIfPresent(browserTitle, forKey: .browserTitle)
        try container.encodeIfPresent(browserURLString, forKey: .browserURLString)
        try container.encodeIfPresent(browserIsLoading, forKey: .browserIsLoading)
    }
}

extension WorkspacePaneRestoreSnapshot: Codable {
    enum CodingKeys: String, CodingKey {
        case paneId
        case selectedItemId
        case items
        case surfaceId
        case terminalSessionId
        case restoredWorkingDirectory
        case restoredTitle
        case agentSummary
        case snapshotTextRef
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let paneId = try container.decode(String.self, forKey: .paneId)
        if let items = try container.decodeIfPresent([WorkspacePaneItemRestoreSnapshot].self, forKey: .items),
           !items.isEmpty {
            self.init(
                paneId: paneId,
                selectedItemId: try container.decodeIfPresent(String.self, forKey: .selectedItemId),
                items: items
            )
            return
        }

        let legacyItem = WorkspacePaneItemRestoreSnapshot(
            surfaceId: try container.decode(String.self, forKey: .surfaceId),
            terminalSessionId: try container.decode(String.self, forKey: .terminalSessionId),
            restoredWorkingDirectory: try container.decodeIfPresent(String.self, forKey: .restoredWorkingDirectory),
            restoredTitle: try container.decodeIfPresent(String.self, forKey: .restoredTitle),
            agentSummary: try container.decodeIfPresent(String.self, forKey: .agentSummary),
            snapshotTextRef: try container.decodeIfPresent(WorkspacePaneSnapshotTextRef.self, forKey: .snapshotTextRef),
            snapshotText: nil
        )
        self.init(
            paneId: paneId,
            selectedItemId: legacyItem.surfaceId,
            items: [legacyItem]
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(paneId, forKey: .paneId)
        try container.encodeIfPresent(selectedItemId, forKey: .selectedItemId)
        try container.encode(items, forKey: .items)
        try container.encode(surfaceId, forKey: .surfaceId)
        try container.encode(terminalSessionId, forKey: .terminalSessionId)
        try container.encodeIfPresent(restoredWorkingDirectory, forKey: .restoredWorkingDirectory)
        try container.encodeIfPresent(restoredTitle, forKey: .restoredTitle)
        try container.encodeIfPresent(agentSummary, forKey: .agentSummary)
        try container.encodeIfPresent(snapshotTextRef, forKey: .snapshotTextRef)
    }
}

private extension WorkspacePaneTreeRestoreSnapshot.Node {
    var leaves: [WorkspacePaneRestoreSnapshot] {
        switch self {
        case let .leaf(pane):
            return [pane]
        case let .split(split):
            return split.left.leaves + split.right.leaves
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
