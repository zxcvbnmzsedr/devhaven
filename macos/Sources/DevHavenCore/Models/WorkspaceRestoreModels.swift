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
    public var projectPath: String
    public var rootProjectPath: String
    public var isQuickTerminal: Bool
    public var workspaceRootContext: WorkspaceRootSessionContext?
    public var workspaceId: String
    public var selectedTabId: String?
    public var nextTabNumber: Int
    public var nextPaneNumber: Int
    public var tabs: [WorkspaceTabRestoreSnapshot]

    public init(
        projectPath: String,
        rootProjectPath: String,
        isQuickTerminal: Bool,
        workspaceRootContext: WorkspaceRootSessionContext? = nil,
        workspaceId: String,
        selectedTabId: String?,
        nextTabNumber: Int,
        nextPaneNumber: Int,
        tabs: [WorkspaceTabRestoreSnapshot]
    ) {
        self.projectPath = projectPath
        self.rootProjectPath = rootProjectPath
        self.isQuickTerminal = isQuickTerminal
        self.workspaceRootContext = workspaceRootContext
        self.workspaceId = workspaceId
        self.selectedTabId = selectedTabId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.nextTabNumber = max(nextTabNumber, 1)
        self.nextPaneNumber = max(nextPaneNumber, 1)
        self.tabs = tabs
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

public struct WorkspacePaneRestoreSnapshot: Equatable, Sendable {
    public var paneId: String
    public var surfaceId: String
    public var terminalSessionId: String
    public var restoredWorkingDirectory: String?
    public var restoredTitle: String?
    public var agentSummary: String?
    public var snapshotTextRef: WorkspacePaneSnapshotTextRef?
    public var snapshotText: String?

    public init(
        paneId: String,
        surfaceId: String,
        terminalSessionId: String,
        restoredWorkingDirectory: String?,
        restoredTitle: String?,
        agentSummary: String?,
        snapshotTextRef: WorkspacePaneSnapshotTextRef?,
        snapshotText: String?
    ) {
        self.paneId = paneId
        self.surfaceId = surfaceId
        self.terminalSessionId = terminalSessionId
        self.restoredWorkingDirectory = restoredWorkingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.restoredTitle = restoredTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.agentSummary = agentSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.snapshotTextRef = snapshotTextRef
        self.snapshotText = snapshotText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

extension WorkspacePaneRestoreSnapshot: Codable {
    enum CodingKeys: String, CodingKey {
        case paneId
        case surfaceId
        case terminalSessionId
        case restoredWorkingDirectory
        case restoredTitle
        case agentSummary
        case snapshotTextRef
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            paneId: try container.decode(String.self, forKey: .paneId),
            surfaceId: try container.decode(String.self, forKey: .surfaceId),
            terminalSessionId: try container.decode(String.self, forKey: .terminalSessionId),
            restoredWorkingDirectory: try container.decodeIfPresent(String.self, forKey: .restoredWorkingDirectory),
            restoredTitle: try container.decodeIfPresent(String.self, forKey: .restoredTitle),
            agentSummary: try container.decodeIfPresent(String.self, forKey: .agentSummary),
            snapshotTextRef: try container.decodeIfPresent(WorkspacePaneSnapshotTextRef.self, forKey: .snapshotTextRef),
            snapshotText: nil
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(paneId, forKey: .paneId)
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
