import Foundation

public enum WorkspaceProjectTreeNodeKind: String, Equatable, Sendable {
    case directory
    case file
    case symlink

    public var isDirectoryLike: Bool {
        self == .directory
    }
}

public struct WorkspaceProjectTreeNode: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var path: String
    public var parentPath: String?
    public var name: String
    public var kind: WorkspaceProjectTreeNodeKind
    public var isHidden: Bool

    public init(
        path: String,
        parentPath: String?,
        name: String,
        kind: WorkspaceProjectTreeNodeKind,
        isHidden: Bool
    ) {
        self.path = path
        self.parentPath = parentPath
        self.name = name
        self.kind = kind
        self.isHidden = isHidden
    }

    public var isDirectory: Bool {
        kind.isDirectoryLike
    }
}

public struct WorkspaceProjectTreeState: Equatable, Sendable {
    public var rootProjectPath: String
    public var rootNodes: [WorkspaceProjectTreeNode]
    public var childrenByDirectoryPath: [String: [WorkspaceProjectTreeNode]]
    public var expandedDirectoryPaths: Set<String>
    public var loadingDirectoryPaths: Set<String>
    public var selectedPath: String?
    public var errorMessage: String?

    public init(
        rootProjectPath: String,
        rootNodes: [WorkspaceProjectTreeNode] = [],
        childrenByDirectoryPath: [String: [WorkspaceProjectTreeNode]] = [:],
        expandedDirectoryPaths: Set<String> = [],
        loadingDirectoryPaths: Set<String> = [],
        selectedPath: String? = nil,
        errorMessage: String? = nil
    ) {
        self.rootProjectPath = rootProjectPath
        self.rootNodes = rootNodes
        self.childrenByDirectoryPath = childrenByDirectoryPath
        self.expandedDirectoryPaths = expandedDirectoryPaths
        self.loadingDirectoryPaths = loadingDirectoryPaths
        self.selectedPath = selectedPath
        self.errorMessage = errorMessage
    }

    public func children(for directoryPath: String?) -> [WorkspaceProjectTreeNode] {
        guard let directoryPath else {
            return rootNodes
        }
        return childrenByDirectoryPath[directoryPath] ?? []
    }

    public func isExpanded(_ directoryPath: String) -> Bool {
        expandedDirectoryPaths.contains(directoryPath)
    }

    public func isLoading(_ directoryPath: String) -> Bool {
        loadingDirectoryPaths.contains(directoryPath)
    }
}
