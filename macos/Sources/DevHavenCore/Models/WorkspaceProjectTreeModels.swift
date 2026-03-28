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

public struct WorkspaceProjectTreeDisplayNode: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var path: String
    public var parentPath: String?
    public var name: String
    public var kind: WorkspaceProjectTreeNodeKind
    public var compactedDirectoryPaths: [String]
    public var javaSourceRootPath: String?
    public var children: [WorkspaceProjectTreeDisplayNode]

    public init(
        path: String,
        parentPath: String?,
        name: String,
        kind: WorkspaceProjectTreeNodeKind,
        compactedDirectoryPaths: [String] = [],
        javaSourceRootPath: String? = nil,
        children: [WorkspaceProjectTreeDisplayNode] = []
    ) {
        self.path = path
        self.parentPath = parentPath
        self.name = name
        self.kind = kind
        self.compactedDirectoryPaths = compactedDirectoryPaths
        self.javaSourceRootPath = javaSourceRootPath
        self.children = children
    }

    public var isDirectory: Bool {
        kind.isDirectoryLike
    }

    public var isCompactedDirectory: Bool {
        compactedDirectoryPaths.count > 1
    }

    public func matchesSelection(_ path: String?) -> Bool {
        guard let path else {
            return false
        }
        let normalizedPath = normalizeWorkspaceProjectTreePath(path)
        if normalizeWorkspaceProjectTreePath(self.path) == normalizedPath {
            return true
        }
        return compactedDirectoryPaths.contains { normalizeWorkspaceProjectTreePath($0) == normalizedPath }
    }
}

public extension WorkspaceProjectTreeState {
    var displayRootNodes: [WorkspaceProjectTreeDisplayNode] {
        WorkspaceProjectTreeDisplayBuilder(state: self).buildRootNodes()
    }

    func canonicalDisplayPath(for path: String?) -> String? {
        guard let path else {
            return nil
        }
        let normalizedPath = normalizeWorkspaceProjectTreePath(path)
        return displayPathAliasMap()[normalizedPath] ?? normalizedPath
    }

    func canonicalizedForDisplay() -> WorkspaceProjectTreeState {
        var copy = self
        let aliasMap = displayPathAliasMap()
        copy.expandedDirectoryPaths = Set(
            expandedDirectoryPaths.map { aliasMap[normalizeWorkspaceProjectTreePath($0)] ?? normalizeWorkspaceProjectTreePath($0) }
        )
        copy.loadingDirectoryPaths = Set(
            loadingDirectoryPaths.map { aliasMap[normalizeWorkspaceProjectTreePath($0)] ?? normalizeWorkspaceProjectTreePath($0) }
        )
        if let selectedPath {
            copy.selectedPath = aliasMap[normalizeWorkspaceProjectTreePath(selectedPath)] ?? normalizeWorkspaceProjectTreePath(selectedPath)
        }
        return copy
    }

    func displayNode(for path: String) -> WorkspaceProjectTreeDisplayNode? {
        let normalizedPath = normalizeWorkspaceProjectTreePath(path)
        return findDisplayNode(in: displayRootNodes) { node in
            normalizeWorkspaceProjectTreePath(node.path) == normalizedPath
        }
    }
}

enum WorkspaceProjectTreeJavaPackageSupport {
    private static let recognizedSourceRootSuffixes: [[String]] = [
        ["src", "main", "java"],
        ["src", "test", "java"],
    ]

    static func javaSourceRoot(for path: String, projectRootPath: String) -> String? {
        let normalizedPath = normalizeWorkspaceProjectTreePath(path)
        let normalizedProjectPath = normalizeWorkspaceProjectTreePath(projectRootPath)
        guard normalizedPath == normalizedProjectPath || normalizedPath.hasPrefix(normalizedProjectPath + "/") else {
            return nil
        }

        var currentPath = normalizedPath
        while currentPath == normalizedProjectPath || currentPath.hasPrefix(normalizedProjectPath + "/") {
            if isRecognizedSourceRootPath(currentPath, projectRootPath: normalizedProjectPath) {
                return currentPath
            }
            guard currentPath != normalizedProjectPath else {
                break
            }
            currentPath = URL(fileURLWithPath: currentPath).deletingLastPathComponent().path
        }
        return nil
    }

    static func isPackageDirectoryPath(_ path: String, within sourceRootPath: String) -> Bool {
        guard let relativeComponents = relativePathComponents(
            from: sourceRootPath,
            to: path
        ), !relativeComponents.isEmpty else {
            return false
        }
        return relativeComponents.allSatisfy(isJavaPackageIdentifier)
    }

    static func compactedChildDirectory(
        children: [WorkspaceProjectTreeNode],
        sourceRootPath: String
    ) -> WorkspaceProjectTreeNode? {
        guard !children.isEmpty,
              children.count == 1,
              children.allSatisfy(\.isDirectory),
              let child = children.first,
              isPackageDirectoryPath(child.path, within: sourceRootPath)
        else {
            return nil
        }
        return child
    }

    private static func relativePathComponents(from basePath: String, to path: String) -> [String]? {
        let normalizedBasePath = normalizeWorkspaceProjectTreePath(basePath)
        let normalizedPath = normalizeWorkspaceProjectTreePath(path)
        if normalizedPath == normalizedBasePath {
            return []
        }
        guard normalizedPath.hasPrefix(normalizedBasePath + "/") else {
            return nil
        }
        let relativePath = String(normalizedPath.dropFirst(normalizedBasePath.count + 1))
        return relativePath.split(separator: "/").map(String.init)
    }

    private static func isRecognizedSourceRootPath(_ path: String, projectRootPath: String) -> Bool {
        guard let relativeComponents = relativePathComponents(from: projectRootPath, to: path) else {
            return false
        }
        return recognizedSourceRootSuffixes.contains { suffix in
            relativeComponents.suffix(suffix.count).elementsEqual(suffix)
        }
    }

    private static func isJavaPackageIdentifier(_ name: String) -> Bool {
        guard let firstScalar = name.unicodeScalars.first else {
            return false
        }
        let headCharacterSet = CharacterSet.letters.union(CharacterSet(charactersIn: "_$"))
        let bodyCharacterSet = headCharacterSet.union(.decimalDigits)
        guard headCharacterSet.contains(firstScalar) else {
            return false
        }
        return name.unicodeScalars.dropFirst().allSatisfy(bodyCharacterSet.contains)
    }
}

private struct WorkspaceProjectTreeDisplayBuilder {
    let state: WorkspaceProjectTreeState

    func buildRootNodes() -> [WorkspaceProjectTreeDisplayNode] {
        buildDisplayNodes(from: state.rootNodes, parentDisplayPath: nil)
    }

    private func buildDisplayNodes(
        from nodes: [WorkspaceProjectTreeNode],
        parentDisplayPath: String?
    ) -> [WorkspaceProjectTreeDisplayNode] {
        nodes.map { buildDisplayNode(from: $0, parentDisplayPath: parentDisplayPath) }
    }

    private func buildDisplayNode(
        from node: WorkspaceProjectTreeNode,
        parentDisplayPath: String?
    ) -> WorkspaceProjectTreeDisplayNode {
        guard node.isDirectory else {
            return WorkspaceProjectTreeDisplayNode(
                path: node.path,
                parentPath: parentDisplayPath,
                name: node.name,
                kind: node.kind,
                children: []
            )
        }

        let sourceRootPath = WorkspaceProjectTreeJavaPackageSupport.javaSourceRoot(
            for: node.path,
            projectRootPath: state.rootProjectPath
        )
        let chain = compactedDirectoryChain(
            startingAt: node,
            sourceRootPath: sourceRootPath
        )
        let representedNode = chain.last ?? node
        let representedPath = representedNode.path
        let childNodes = state.children(for: representedPath)
        let displayChildren = buildDisplayNodes(
            from: childNodes,
            parentDisplayPath: representedPath
        )

        return WorkspaceProjectTreeDisplayNode(
            path: representedPath,
            parentPath: parentDisplayPath,
            name: chain.map(\.name).joined(separator: "."),
            kind: representedNode.kind,
            compactedDirectoryPaths: chain.map(\.path),
            javaSourceRootPath: sourceRootPath,
            children: displayChildren
        )
    }

    private func compactedDirectoryChain(
        startingAt node: WorkspaceProjectTreeNode,
        sourceRootPath: String?
    ) -> [WorkspaceProjectTreeNode] {
        guard let sourceRootPath,
              normalizeWorkspaceProjectTreePath(node.path) != normalizeWorkspaceProjectTreePath(sourceRootPath),
              WorkspaceProjectTreeJavaPackageSupport.isPackageDirectoryPath(node.path, within: sourceRootPath)
        else {
            return [node]
        }

        var chain = [node]
        var currentNode = node
        while let nextNode = nextCompactedDirectory(after: currentNode, sourceRootPath: sourceRootPath) {
            chain.append(nextNode)
            currentNode = nextNode
        }
        return chain
    }

    private func nextCompactedDirectory(
        after node: WorkspaceProjectTreeNode,
        sourceRootPath: String
    ) -> WorkspaceProjectTreeNode? {
        WorkspaceProjectTreeJavaPackageSupport.compactedChildDirectory(
            children: state.children(for: node.path),
            sourceRootPath: sourceRootPath
        )
    }
}

private extension WorkspaceProjectTreeState {
    func displayPathAliasMap() -> [String: String] {
        var aliasMap: [String: String] = [:]
        registerDisplayAliases(from: displayRootNodes, into: &aliasMap)
        return aliasMap
    }

    func registerDisplayAliases(
        from nodes: [WorkspaceProjectTreeDisplayNode],
        into aliasMap: inout [String: String]
    ) {
        for node in nodes {
            let normalizedRepresentedPath = normalizeWorkspaceProjectTreePath(node.path)
            if node.isDirectory {
                for compactedPath in node.compactedDirectoryPaths {
                    aliasMap[normalizeWorkspaceProjectTreePath(compactedPath)] = normalizedRepresentedPath
                }
            }
            registerDisplayAliases(from: node.children, into: &aliasMap)
        }
    }
}

private func findDisplayNode(
    in nodes: [WorkspaceProjectTreeDisplayNode],
    where predicate: (WorkspaceProjectTreeDisplayNode) -> Bool
) -> WorkspaceProjectTreeDisplayNode? {
    for node in nodes {
        if predicate(node) {
            return node
        }
        if let match = findDisplayNode(in: node.children, where: predicate) {
            return match
        }
    }
    return nil
}

private func normalizeWorkspaceProjectTreePath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
}
