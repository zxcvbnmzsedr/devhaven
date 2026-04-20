import Foundation

private struct WorkspaceProjectTreeDirectoryLoadResult: Sendable {
    let directoryPath: String
    let childrenByDirectoryPath: [String: [WorkspaceProjectTreeNode]]

    var directChildCount: Int {
        childrenByDirectoryPath[directoryPath]?.count ?? 0
    }

    var loadedDirectoryCount: Int {
        childrenByDirectoryPath.count
    }
}

@MainActor
final class WorkspaceProjectTreeController {
    private let stateStore: WorkspaceProjectTreeStateStore
    private let fileSystemService: WorkspaceFileSystemService
    private let diagnostics: WorkspaceProjectTreeDiagnostics
    private let normalizePath: @MainActor (String) -> String
    private let resolveProjectPath: @MainActor (String?) -> String?
    private let activeProjectTreeProject: @MainActor () -> Project?
    private let syncGitSelection: @MainActor (String, String?) -> Void
    private let reportError: @MainActor (String?) -> Void

    init(
        stateStore: WorkspaceProjectTreeStateStore,
        fileSystemService: WorkspaceFileSystemService,
        diagnostics: WorkspaceProjectTreeDiagnostics,
        normalizePath: @escaping @MainActor (String) -> String,
        resolveProjectPath: @escaping @MainActor (String?) -> String?,
        activeProjectTreeProject: @escaping @MainActor () -> Project?,
        syncGitSelection: @escaping @MainActor (String, String?) -> Void,
        reportError: @escaping @MainActor (String?) -> Void
    ) {
        self.stateStore = stateStore
        self.fileSystemService = fileSystemService
        self.diagnostics = diagnostics
        self.normalizePath = normalizePath
        self.resolveProjectPath = resolveProjectPath
        self.activeProjectTreeProject = activeProjectTreeProject
        self.syncGitSelection = syncGitSelection
        self.reportError = reportError
    }

    func displayProjection(
        for projectPath: String,
        state: WorkspaceProjectTreeState
    ) -> WorkspaceProjectTreeDisplayProjection {
        if let cache = stateStore.projectionCacheByProjectPath[projectPath],
           cache.revision == state.revision {
            return cache.projection
        }

        let startTime = ProcessInfo.processInfo.systemUptime
        let projection = state.displayProjection
        stateStore.projectionCacheByProjectPath[projectPath] = (
            revision: state.revision,
            projection: projection
        )
        diagnostics.recordProjectionBuilt(
            projectPath: projectPath,
            revision: state.revision,
            durationMs: elapsedMillisecondsSince(startTime),
            rootCount: projection.rootNodes.count,
            aliasCount: projection.aliasMap.count
        )
        return projection
    }

    func prepareActiveProjectTreeState() {
        guard let activeProjectTreeProject = activeProjectTreeProject() else {
            return
        }
        let normalizedProjectPath = normalizePath(activeProjectTreeProject.path)
        if stateStore.statesByProjectPath[normalizedProjectPath] == nil,
           !stateStore.refreshingProjectPaths.contains(normalizedProjectPath) {
            refreshProjectTree(for: normalizedProjectPath)
        }
    }

    func refreshProjectTree(for projectPath: String? = nil) {
        guard let resolvedProjectPath = resolveProjectPath(projectPath) else {
            return
        }
        scheduleRefresh(
            for: resolvedProjectPath,
            preserving: stateStore.statesByProjectPath[resolvedProjectPath]
        )
    }

    func refreshProjectTreeNode(_ path: String?, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolveProjectPath(projectPath) else {
            return
        }
        // 首版先走整棵树重建，优先保证 rename/delete/create 后路径映射与展开态一致。
        scheduleRefresh(
            for: resolvedProjectPath,
            preserving: stateStore.statesByProjectPath[resolvedProjectPath],
            preferredSelectionPath: path
        )
    }

    func refreshProjectTree(
        for projectPath: String,
        preserving state: WorkspaceProjectTreeState?,
        preferredSelectionPath: String? = nil
    ) {
        scheduleRefresh(
            for: projectPath,
            preserving: state,
            preferredSelectionPath: preferredSelectionPath
        )
    }

    func selectProjectTreeNode(_ path: String?, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolveProjectPath(projectPath),
              var state = stateStore.statesByProjectPath[resolvedProjectPath]
        else {
            return
        }
        state.selectedPath = state.canonicalDisplayPath(for: path)
        stateStore.statesByProjectPath[resolvedProjectPath] = state
        syncGitSelection(resolvedProjectPath, state.selectedPath)
    }

    func toggleDirectory(_ directoryPath: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolveProjectPath(projectPath),
              var state = stateStore.statesByProjectPath[resolvedProjectPath]
        else {
            return
        }

        let projection = displayProjection(for: resolvedProjectPath, state: state)
        let normalizedDirectoryPath = projection.aliasMap[normalizePath(directoryPath)]
            ?? normalizePath(directoryPath)

        if state.expandedDirectoryPaths.contains(normalizedDirectoryPath) {
            state.expandedDirectoryPaths.remove(normalizedDirectoryPath)
            state.loadingDirectoryPaths.remove(normalizedDirectoryPath)
            stateStore.statesByProjectPath[resolvedProjectPath] = state
            diagnostics.recordDirectoryCollapsed(
                projectPath: resolvedProjectPath,
                directoryPath: normalizedDirectoryPath,
                revision: state.revision,
                expandedCount: state.expandedDirectoryPaths.count
            )
            return
        }

        state.expandedDirectoryPaths.insert(normalizedDirectoryPath)
        if let existingChildren = state.childrenByDirectoryPath[normalizedDirectoryPath] {
            state.errorMessage = nil
            stateStore.statesByProjectPath[resolvedProjectPath] = state.canonicalizedForDisplay()
            reportError(nil)
            preloadVisibleChainsIfNeeded(
                for: normalizedDirectoryPath,
                projectRootPath: resolvedProjectPath,
                children: existingChildren
            )
            return
        }

        state.loadingDirectoryPaths.insert(normalizedDirectoryPath)
        state.errorMessage = nil
        let loadingRevision = state.revision
        stateStore.statesByProjectPath[resolvedProjectPath] = state
        reportError(nil)
        diagnostics.recordDirectoryLoadStarted(
            projectPath: resolvedProjectPath,
            directoryPath: normalizedDirectoryPath,
            revision: loadingRevision
        )

        let projectRootPath = resolvedProjectPath
        let fileSystemService = fileSystemService
        let startTime = ProcessInfo.processInfo.systemUptime
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let result = try Self.loadChildrenSnapshot(
                    service: fileSystemService,
                    directoryPath: normalizedDirectoryPath,
                    projectRootPath: projectRootPath
                )
                await self?.finishDirectoryLoadSuccess(
                    for: resolvedProjectPath,
                    directoryPath: normalizedDirectoryPath,
                    result: result,
                    startTime: startTime
                )
            } catch {
                let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await self?.finishDirectoryLoadFailure(
                    for: resolvedProjectPath,
                    directoryPath: normalizedDirectoryPath,
                    errorDescription: errorDescription,
                    startTime: startTime
                )
            }
        }
    }

    private func finishDirectoryLoadSuccess(
        for projectPath: String,
        directoryPath: String,
        result: WorkspaceProjectTreeDirectoryLoadResult,
        startTime: TimeInterval
    ) {
        guard var latestState = stateStore.statesByProjectPath[projectPath] else {
            return
        }

        latestState.loadingDirectoryPaths.remove(directoryPath)
        for (path, children) in result.childrenByDirectoryPath {
            latestState.childrenByDirectoryPath[path] = children
        }
        latestState.errorMessage = nil
        latestState.advanceStructureRevision()
        let finalizedState = latestState.canonicalizedForDisplay()
        stateStore.statesByProjectPath[projectPath] = finalizedState
        reportError(nil)
        diagnostics.recordDirectoryLoadFinished(
            projectPath: projectPath,
            directoryPath: directoryPath,
            revision: finalizedState.revision,
            durationMs: elapsedMillisecondsSince(startTime),
            loadedDirectoryCount: result.loadedDirectoryCount,
            directChildCount: result.directChildCount,
            status: "success",
            errorDescription: nil
        )
    }

    private func finishDirectoryLoadFailure(
        for projectPath: String,
        directoryPath: String,
        errorDescription: String,
        startTime: TimeInterval
    ) {
        guard var latestState = stateStore.statesByProjectPath[projectPath] else {
            return
        }

        latestState.loadingDirectoryPaths.remove(directoryPath)
        latestState.errorMessage = errorDescription
        stateStore.statesByProjectPath[projectPath] = latestState
        reportError(latestState.errorMessage)
        diagnostics.recordDirectoryLoadFinished(
            projectPath: projectPath,
            directoryPath: directoryPath,
            revision: latestState.revision,
            durationMs: elapsedMillisecondsSince(startTime),
            loadedDirectoryCount: 0,
            directChildCount: 0,
            status: "failed",
            errorDescription: latestState.errorMessage
        )
    }

    private func preloadVisibleChainsIfNeeded(
        for directoryPath: String,
        projectRootPath: String,
        children: [WorkspaceProjectTreeNode]
    ) {
        let fileSystemService = fileSystemService
        let startRevision = stateStore.statesByProjectPath[projectRootPath]?.revision ?? 0
        let startTime = ProcessInfo.processInfo.systemUptime
        Task.detached(priority: .utility) { [weak self] in
            guard let self else {
                return
            }
            guard let result = try? Self.preloadVisibleChainsSnapshot(
                service: fileSystemService,
                children: children,
                projectRootPath: projectRootPath
            ), !result.isEmpty else {
                return
            }

            await MainActor.run {
                guard var latestState = self.stateStore.statesByProjectPath[projectRootPath] else {
                    return
                }
                var didMerge = false
                for (path, loadedChildren) in result where latestState.childrenByDirectoryPath[path] != loadedChildren {
                    latestState.childrenByDirectoryPath[path] = loadedChildren
                    didMerge = true
                }
                guard didMerge else {
                    return
                }
                latestState.advanceStructureRevision()
                let finalizedState = latestState.canonicalizedForDisplay()
                self.stateStore.statesByProjectPath[projectRootPath] = finalizedState
                self.diagnostics.recordDirectoryLoadFinished(
                    projectPath: projectRootPath,
                    directoryPath: directoryPath,
                    revision: max(startRevision, finalizedState.revision),
                    durationMs: elapsedMillisecondsSince(startTime),
                    loadedDirectoryCount: result.count,
                    directChildCount: children.count,
                    status: "success",
                    errorDescription: nil
                )
            }
        }
    }

    private func scheduleRefresh(
        for projectPath: String,
        preserving state: WorkspaceProjectTreeState?,
        preferredSelectionPath: String? = nil
    ) {
        let normalizedProjectPath = normalizePath(projectPath)
        let nextGeneration = (stateStore.refreshGenerationByProjectPath[normalizedProjectPath] ?? 0) &+ 1
        stateStore.refreshGenerationByProjectPath[normalizedProjectPath] = nextGeneration
        stateStore.refreshingProjectPaths.insert(normalizedProjectPath)
        stateStore.refreshTasksByProjectPath[normalizedProjectPath]?.cancel()

        let fileSystemService = fileSystemService
        let startTime = ProcessInfo.processInfo.systemUptime
        stateStore.refreshTasksByProjectPath[normalizedProjectPath] = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let rebuiltState = try Self.buildStateSnapshot(
                    service: fileSystemService,
                    projectPath: normalizedProjectPath,
                    preserving: state
                )
                await self?.finishRefresh(
                    for: normalizedProjectPath,
                    generation: nextGeneration,
                    rebuiltState: rebuiltState,
                    preferredSelectionPath: preferredSelectionPath,
                    startTime: startTime
                )
            } catch is CancellationError {
                await self?.finishRefreshCancellation(
                    for: normalizedProjectPath,
                    generation: nextGeneration
                )
            } catch {
                let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await self?.finishRefreshFailure(
                    for: normalizedProjectPath,
                    generation: nextGeneration,
                    preserving: state,
                    errorDescription: errorDescription
                )
            }
        }
    }

    private func finishRefresh(
        for projectPath: String,
        generation: Int,
        rebuiltState: WorkspaceProjectTreeState,
        preferredSelectionPath: String?,
        startTime: TimeInterval
    ) {
        guard stateStore.refreshGenerationByProjectPath[projectPath] == generation else {
            return
        }

        var finalState = rebuiltState
        if let latestState = stateStore.statesByProjectPath[projectPath] {
            finalState.expandedDirectoryPaths = latestState.expandedDirectoryPaths
                .filter { normalizePath($0) != normalizePath(projectPath) }
                .filter { fileSystemService.directoryExists(at: $0) }
            finalState.loadingDirectoryPaths = latestState.loadingDirectoryPaths
            for (path, children) in latestState.childrenByDirectoryPath {
                guard normalizePath(path) != normalizePath(projectPath) else {
                    continue
                }
                finalState.childrenByDirectoryPath[path] = children
            }
            if preferredSelectionPath == nil,
               let latestSelectedPath = latestState.selectedPath,
               FileManager.default.fileExists(atPath: latestSelectedPath) {
                finalState.selectedPath = latestSelectedPath
            }
        }
        if let preferredSelectionPath {
            finalState.selectedPath = finalState.canonicalDisplayPath(for: preferredSelectionPath)
            if finalState.selectedPath == nil,
               FileManager.default.fileExists(atPath: preferredSelectionPath) {
                finalState.selectedPath = normalizePath(preferredSelectionPath)
            }
        }
        finalState = finalState.canonicalizedForDisplay()
        finalState.errorMessage = nil
        stateStore.statesByProjectPath[projectPath] = finalState
        syncGitSelection(projectPath, finalState.selectedPath)
        stateStore.refreshingProjectPaths.remove(projectPath)
        stateStore.refreshTasksByProjectPath[projectPath] = nil
        reportError(nil)
        diagnostics.recordTreeRebuilt(
            projectPath: projectPath,
            revision: finalState.revision,
            durationMs: elapsedMillisecondsSince(startTime),
            rootCount: finalState.rootNodes.count,
            expandedCount: finalState.expandedDirectoryPaths.count
        )
    }

    private func finishRefreshFailure(
        for projectPath: String,
        generation: Int,
        preserving state: WorkspaceProjectTreeState?,
        errorDescription: String
    ) {
        guard stateStore.refreshGenerationByProjectPath[projectPath] == generation else {
            return
        }

        var fallbackState = stateStore.statesByProjectPath[projectPath]
            ?? state
            ?? WorkspaceProjectTreeState(rootProjectPath: projectPath)
        fallbackState.errorMessage = errorDescription
        stateStore.statesByProjectPath[projectPath] = fallbackState
        stateStore.refreshingProjectPaths.remove(projectPath)
        stateStore.refreshTasksByProjectPath[projectPath] = nil
        reportError(fallbackState.errorMessage)
    }

    private func finishRefreshCancellation(
        for projectPath: String,
        generation: Int
    ) {
        guard stateStore.refreshGenerationByProjectPath[projectPath] == generation else {
            return
        }

        stateStore.refreshingProjectPaths.remove(projectPath)
        stateStore.refreshTasksByProjectPath[projectPath] = nil
    }

    nonisolated private static func loadChildrenSnapshot(
        service: WorkspaceFileSystemService,
        directoryPath: String,
        projectRootPath: String
    ) throws -> WorkspaceProjectTreeDirectoryLoadResult {
        let normalizedDirectoryPath = normalizePathForCompare(directoryPath)
        let normalizedProjectRootPath = normalizePathForCompare(projectRootPath)
        let children = try service.listDirectory(at: normalizedDirectoryPath)
        var loadedChildrenByDirectoryPath: [String: [WorkspaceProjectTreeNode]] = [
            normalizedDirectoryPath: children
        ]

        for child in children where child.isDirectory {
            try preloadDisplayChain(
                service: service,
                startingAt: child,
                projectRootPath: normalizedProjectRootPath,
                into: &loadedChildrenByDirectoryPath
            )
        }

        return WorkspaceProjectTreeDirectoryLoadResult(
            directoryPath: normalizedDirectoryPath,
            childrenByDirectoryPath: loadedChildrenByDirectoryPath
        )
    }

    nonisolated private static func buildStateSnapshot(
        service: WorkspaceFileSystemService,
        projectPath: String,
        preserving existingState: WorkspaceProjectTreeState?
    ) throws -> WorkspaceProjectTreeState {
        let normalizedProjectPath = normalizePathForCompare(projectPath)
        var nextState = existingState ?? WorkspaceProjectTreeState(rootProjectPath: normalizedProjectPath)
        nextState.advanceStructureRevision()

        let rootNodes = try service.listDirectory(at: normalizedProjectPath)
        nextState.rootProjectPath = normalizedProjectPath
        nextState.rootNodes = rootNodes
        nextState.childrenByDirectoryPath[normalizedProjectPath] = rootNodes

        let rootProjectionChildren = try preloadVisibleChainsSnapshot(
            service: service,
            children: rootNodes,
            projectRootPath: normalizedProjectPath
        )
        for (path, children) in rootProjectionChildren {
            nextState.childrenByDirectoryPath[path] = children
        }
        nextState.errorMessage = nil

        let expandedPaths = (existingState?.expandedDirectoryPaths ?? [])
            .filter { normalizePathForCompare($0) != normalizedProjectPath }
            .filter { service.directoryExists(at: $0) }

        nextState.expandedDirectoryPaths = Set(expandedPaths)
        nextState.loadingDirectoryPaths = []
        for directoryPath in expandedPaths {
            let result = try loadChildrenSnapshot(
                service: service,
                directoryPath: directoryPath,
                projectRootPath: normalizedProjectPath
            )
            for (path, children) in result.childrenByDirectoryPath {
                nextState.childrenByDirectoryPath[path] = children
            }
        }

        if let selectedPath = existingState?.selectedPath,
           FileManager.default.fileExists(atPath: selectedPath) {
            nextState.selectedPath = selectedPath
        } else {
            nextState.selectedPath = nil
        }

        return nextState.canonicalizedForDisplay()
    }

    nonisolated private static func preloadVisibleChainsSnapshot(
        service: WorkspaceFileSystemService,
        children: [WorkspaceProjectTreeNode],
        projectRootPath: String
    ) throws -> [String: [WorkspaceProjectTreeNode]] {
        let normalizedProjectRootPath = normalizePathForCompare(projectRootPath)
        var loadedChildrenByDirectoryPath: [String: [WorkspaceProjectTreeNode]] = [:]
        for child in children where child.isDirectory {
            try preloadDisplayChain(
                service: service,
                startingAt: child,
                projectRootPath: normalizedProjectRootPath,
                into: &loadedChildrenByDirectoryPath
            )
        }
        return loadedChildrenByDirectoryPath
    }

    nonisolated private static func preloadDisplayChain(
        service: WorkspaceFileSystemService,
        startingAt node: WorkspaceProjectTreeNode,
        projectRootPath: String,
        into loadedChildrenByDirectoryPath: inout [String: [WorkspaceProjectTreeNode]]
    ) throws {
        guard let sourceRootPath = WorkspaceProjectTreeJavaPackageSupport.javaSourceRoot(
            for: node.path,
            projectRootPath: projectRootPath
        ),
        normalizePathForCompare(node.path) != normalizePathForCompare(sourceRootPath),
        WorkspaceProjectTreeJavaPackageSupport.isPackageDirectoryPath(node.path, within: sourceRootPath)
        else {
            return
        }

        var currentNode = node
        while true {
            let currentPath = normalizePathForCompare(currentNode.path)
            let children = try service.listDirectory(at: currentPath)
            loadedChildrenByDirectoryPath[currentPath] = children
            guard let nextNode = WorkspaceProjectTreeJavaPackageSupport.compactedChildDirectory(
                children: children,
                sourceRootPath: sourceRootPath
            ) else {
                return
            }
            currentNode = nextNode
        }
    }
}

private func elapsedMillisecondsSince(_ startTime: TimeInterval) -> Int {
    max(0, Int(((ProcessInfo.processInfo.systemUptime - startTime) * 1000).rounded()))
}

private func normalizePathForCompare(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return ""
    }
    var normalized = canonicalPathForFileSystemCompare(trimmed)
        .replacingOccurrences(of: "\\", with: "/")
    while normalized.count > 1 && normalized.hasSuffix("/") {
        normalized.removeLast()
    }
    return normalized
}

private func canonicalPathForFileSystemCompare(_ path: String) -> String {
    let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
    let fileManager = FileManager.default
    var ancestorPath = standardizedPath
    var trailingComponents = [String]()

    while ancestorPath != "/", !fileManager.fileExists(atPath: ancestorPath) {
        let lastComponent = (ancestorPath as NSString).lastPathComponent
        guard !lastComponent.isEmpty else {
            break
        }
        trailingComponents.insert(lastComponent, at: 0)
        ancestorPath = (ancestorPath as NSString).deletingLastPathComponent
        if ancestorPath.isEmpty {
            ancestorPath = "/"
            break
        }
    }

    let canonicalAncestorPath = realpathString(ancestorPath) ?? ancestorPath
    guard !trailingComponents.isEmpty else {
        return canonicalAncestorPath
    }

    return trailingComponents.reduce(canonicalAncestorPath as NSString) { partial, component in
        partial.appendingPathComponent(component) as NSString
    } as String
}

private func realpathString(_ path: String) -> String? {
    guard !path.isEmpty else {
        return nil
    }
    return path.withCString { pointer in
        guard let resolvedPointer = realpath(pointer, nil) else {
            return nil
        }
        defer { free(resolvedPointer) }
        return String(cString: resolvedPointer)
    }
}
