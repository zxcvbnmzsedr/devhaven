import Foundation

func loadProjectDocumentFromDisk(_ projectPath: String) throws -> ProjectDocumentSnapshot {
    try LegacyCompatStore().loadProjectDocument(at: projectPath)
}

func nativeAppNormalizePathForCompare(_ path: String) -> String {
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

func elapsedMilliseconds(since startTime: TimeInterval) -> Int {
    max(0, Int(((ProcessInfo.processInfo.systemUptime - startTime) * 1000).rounded()))
}

func nativeAppNormalizePathList(_ paths: [String]) -> [String] {
    var seen = Set<String>()
    return paths
        .map(nativeAppNormalizePathForCompare)
        .filter { !$0.isEmpty }
        .filter { seen.insert($0).inserted }
}

func normalizedOptionalPathForCompare(_ path: String?) -> String? {
    guard let path else {
        return nil
    }
    let normalizedPath = nativeAppNormalizePathForCompare(path)
    return normalizedPath.isEmpty ? nil : normalizedPath
}

func pathLastComponent(_ path: String) -> String {
    let lastComponent = (path as NSString).lastPathComponent
    return lastComponent.isEmpty ? path : lastComponent
}

enum ProjectImportError: LocalizedError {
    case importRejected(String)
    case unsupportedGitWorktree(String)
    case invalidDirectory(String)

    var errorDescription: String? {
        switch self {
        case let .importRejected(message):
            return message
        case let .unsupportedGitWorktree(path):
            return "不支持导入 Git worktree：\(path)"
        case let .invalidDirectory(path):
            return "无法读取目录：\(path)"
        }
    }
}

@MainActor
func validateImportedDirectoryPath(
    _ path: String,
    diagnostics: ProjectImportDiagnostics
) throws -> String {
    let normalizedPath = nativeAppNormalizePathForCompare(path)
    guard !normalizedPath.isEmpty else {
        let error = ProjectImportError.invalidDirectory(path)
        diagnostics.recordValidationRejected(path: path, reason: error.localizedDescription)
        throw error
    }

    let directoryURL = URL(fileURLWithPath: normalizedPath, isDirectory: true)
    let keys: Set<URLResourceKey> = [.isDirectoryKey]
    guard let resourceValues = try? directoryURL.resourceValues(forKeys: keys),
          resourceValues.isDirectory == true
    else {
        let error = ProjectImportError.invalidDirectory(normalizedPath)
        diagnostics.recordValidationRejected(path: normalizedPath, reason: error.localizedDescription)
        throw error
    }
    guard !isGitWorktree(directoryURL) else {
        let error = ProjectImportError.unsupportedGitWorktree(normalizedPath)
        diagnostics.recordValidationRejected(path: normalizedPath, reason: error.localizedDescription)
        throw error
    }
    diagnostics.recordValidationAccepted(path: normalizedPath)
    return normalizedPath
}

func mergeProjectsByPath(existing: [Project], updates: [Project]) -> [Project] {
    let updatesByPath = Dictionary(uniqueKeysWithValues: updates.map { (nativeAppNormalizePathForCompare($0.path), $0) })
    let existingPaths = Set(existing.map { nativeAppNormalizePathForCompare($0.path) })

    var nextProjects = existing.map { project in
        updatesByPath[nativeAppNormalizePathForCompare(project.path)] ?? project
    }
    for project in updates where !existingPaths.contains(nativeAppNormalizePathForCompare(project.path)) {
        nextProjects.append(project)
    }
    return nextProjects
}

public struct ProjectCatalogRefreshRequest: Sendable {
    public let directories: [String]
    public let directProjectPaths: [String]
    public let existingProjects: [Project]
    public let storeHomeDirectoryURL: URL

    public init(directories: [String], directProjectPaths: [String], existingProjects: [Project], storeHomeDirectoryURL: URL) {
        self.directories = directories
        self.directProjectPaths = directProjectPaths
        self.existingProjects = existingProjects
        self.storeHomeDirectoryURL = storeHomeDirectoryURL
    }
}

private let maxProjectDiscoveryDepth = 6

func loadProjectNotesSummary(at projectPath: String) -> String? {
    let notesURL = URL(fileURLWithPath: projectPath, isDirectory: true).appending(path: "PROJECT_NOTES.md")
    guard FileManager.default.fileExists(atPath: notesURL.path),
          let content = try? String(contentsOf: notesURL, encoding: .utf8)
    else {
        return nil
    }
    return projectNotesSummary(from: content)
}

func rebuildProjectCatalogSnapshot(_ request: ProjectCatalogRefreshRequest) async throws -> [Project] {
    let discoveredPaths = discoverProjects(in: request.directories)
    let nextPaths = nativeAppNormalizePathList(discoveredPaths + request.directProjectPaths)
    let rebuiltProjects = buildProjects(paths: nextPaths, existing: request.existingProjects)
    try LegacyCompatStore(homeDirectoryURL: request.storeHomeDirectoryURL).updateProjects(rebuiltProjects)
    return rebuiltProjects
}

func survivingDirectProjectPaths(
    from directProjectPaths: [String],
    rebuiltProjects: [Project]
) -> [String] {
    let rebuiltProjectPaths = Set(rebuiltProjects.map { nativeAppNormalizePathForCompare($0.path) })
    return nativeAppNormalizePathList(
        directProjectPaths.filter { rebuiltProjectPaths.contains(nativeAppNormalizePathForCompare($0)) }
    )
}

private func discoverProjects(in directories: [String]) -> [String] {
    let discovered = directories.flatMap(scanDirectoryWithGit)
    return nativeAppNormalizePathList(discovered).sorted()
}

private func scanDirectoryWithGit(_ path: String) -> [String] {
    let rootURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    guard FileManager.default.fileExists(atPath: rootURL.path) else {
        return []
    }

    var results: [String] = []
    if isGitRepo(rootURL), !isGitWorktree(rootURL) {
        results.append(rootURL.path)
    }

    let childDirectories = childDirectories(of: rootURL, shouldSkip: shouldSkipDirectDirectory)
    for directoryURL in childDirectories where !isGitWorktree(directoryURL) {
        results.append(directoryURL.path)
    }
    results.append(contentsOf: childDirectories.flatMap { collectNestedGitRepos(in: $0, depth: 1) })
    return results
}

private func collectNestedGitRepos(in directoryURL: URL, depth: Int) -> [String] {
    guard depth < maxProjectDiscoveryDepth else {
        return []
    }

    if isGitRepo(directoryURL) {
        return isGitWorktree(directoryURL) ? [] : [directoryURL.path]
    }

    let childDirectories = childDirectories(of: directoryURL, shouldSkip: shouldSkipRecursiveDirectory)
    return childDirectories.flatMap { collectNestedGitRepos(in: $0, depth: depth + 1) }
}

private func childDirectories(of rootURL: URL, shouldSkip: (String) -> Bool) -> [URL] {
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: rootURL,
        includingPropertiesForKeys: Array(keys),
        options: [.skipsSubdirectoryDescendants]
    ) else {
        return []
    }

    return contents.filter { candidate in
        let resourceValues = try? candidate.resourceValues(forKeys: keys)
        let isDirectory = resourceValues?.isDirectory == true
        let isSymbolicLink = resourceValues?.isSymbolicLink == true
        return isDirectory && !isSymbolicLink && !shouldSkip(candidate.lastPathComponent)
    }
}

private func shouldSkipDirectDirectory(_ name: String) -> Bool {
    name.hasPrefix(".")
}

private func shouldSkipRecursiveDirectory(_ name: String) -> Bool {
    guard !name.hasPrefix(".") else {
        return true
    }
    return [".git", "node_modules", "target", "dist", "build"].contains(name)
}

func buildProjects(paths: [String], existing: [Project]) -> [Project] {
    let existingByPath = Dictionary(uniqueKeysWithValues: existing.map { (nativeAppNormalizePathForCompare($0.path), $0) })
    return paths.compactMap { createProject(path: $0, existingByPath: existingByPath) }
}

private func createProject(path: String, existingByPath: [String: Project]) -> Project? {
    let normalizedPath = nativeAppNormalizePathForCompare(path)
    let projectURL = URL(fileURLWithPath: normalizedPath, isDirectory: true)
    guard !isGitWorktree(projectURL) else {
        return nil
    }

    let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
    guard let resourceValues = try? projectURL.resourceValues(forKeys: keys),
          resourceValues.isDirectory == true
    else {
        return nil
    }

    let now = Date()
    let modificationDate = resourceValues.contentModificationDate ?? now
    let size = Int64(resourceValues.fileSize ?? 0)
    let checksum = "\(Int(modificationDate.timeIntervalSince1970))_\(size)"
    let isGitRepository = isGitRepo(projectURL)
    let notesSummary = loadProjectNotesSummary(at: normalizedPath)

    if let existing = existingByPath[normalizedPath] {
        return Project(
            id: existing.id,
            name: projectURL.lastPathComponent.isEmpty ? normalizedPath : projectURL.lastPathComponent,
            path: normalizedPath,
            tags: existing.tags,
            runConfigurations: existing.runConfigurations,
            worktrees: existing.worktrees,
            mtime: swiftDateFromDate(modificationDate),
            size: size,
            checksum: checksum,
            isGitRepository: isGitRepository,
            gitCommits: existing.gitCommits,
            gitLastCommit: existing.gitLastCommit,
            gitLastCommitMessage: existing.gitLastCommitMessage,
            gitDaily: existing.gitDaily,
            notesSummary: notesSummary,
            created: existing.created,
            checked: swiftDateFromDate(now),
            hasPersistedNotesSummary: true
        )
    }

    return Project(
        id: UUID().uuidString.lowercased(),
        name: projectURL.lastPathComponent.isEmpty ? normalizedPath : projectURL.lastPathComponent,
        path: normalizedPath,
        tags: [],
        runConfigurations: [],
        worktrees: [],
        mtime: swiftDateFromDate(modificationDate),
        size: size,
        checksum: checksum,
        isGitRepository: isGitRepository,
        gitCommits: 0,
        gitLastCommit: .zero,
        gitLastCommitMessage: nil,
        gitDaily: nil,
        notesSummary: notesSummary,
        created: swiftDateFromDate(now),
        checked: swiftDateFromDate(now),
        hasPersistedNotesSummary: true
    )
}

private struct ProjectGitInfo {
    let commitCount: Int
    let lastCommit: SwiftDate
    let lastCommitMessage: String?
}

private func loadGitInfo(for path: String) -> ProjectGitInfo {
    let projectURL = URL(fileURLWithPath: path, isDirectory: true)
    guard isGitRepo(projectURL), !isGitWorktree(projectURL) else {
        return ProjectGitInfo(commitCount: 0, lastCommit: .zero, lastCommitMessage: nil)
    }

    let commitCount = Int(runGitCommand(in: path, arguments: ["rev-list", "--count", "HEAD"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
    let logOutput = runGitCommand(in: path, arguments: ["log", "--format=%ct%x1f%s", "-n", "1"])
    let (lastCommitUnix, lastCommitMessage) = parseLastCommitLogOutput(logOutput)
    return ProjectGitInfo(
        commitCount: commitCount,
        lastCommit: lastCommitUnix > 0 ? swiftDateFromDate(Date(timeIntervalSince1970: lastCommitUnix)) : .zero,
        lastCommitMessage: lastCommitMessage
    )
}

private func parseLastCommitLogOutput(_ output: String?) -> (TimeInterval, String?) {
    guard let output else {
        return (0, nil)
    }
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return (0, nil)
    }

    let parts = trimmed.split(separator: "\u{1f}", maxSplits: 1, omittingEmptySubsequences: false)
    let lastCommit = TimeInterval(parts.first ?? "") ?? 0
    let message = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    return (lastCommit, message.isEmpty ? nil : message)
}

private func runGitCommand(in path: String, arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: path, isDirectory: true)

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
    } catch {
        return nil
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        return nil
    }
    return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
}

private func isGitRepo(_ url: URL) -> Bool {
    guard !isGitWorktree(url) else {
        return false
    }
    return FileManager.default.fileExists(atPath: url.appending(path: ".git", directoryHint: .notDirectory).path)
        || FileManager.default.fileExists(atPath: url.appending(path: ".git", directoryHint: .isDirectory).path)
}

func liveWorkspaceRootRepositoryPath(for path: String) -> String? {
    let normalizedPath = nativeAppNormalizePathForCompare(path)
    guard !normalizedPath.isEmpty else {
        return nil
    }
    let repositoryURL = URL(fileURLWithPath: normalizedPath, isDirectory: true)
    guard isGitRepo(repositoryURL), !isGitWorktree(repositoryURL) else {
        return nil
    }
    return normalizedPath
}

private func isGitWorktree(_ url: URL) -> Bool {
    let gitURL = url.appending(path: ".git", directoryHint: .notDirectory)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: gitURL.path, isDirectory: &isDirectory),
          !isDirectory.boolValue,
          let resolvedGitDir = resolveGitDirFromFile(gitURL)
    else {
        return false
    }
    return resolvedGitDir.pathComponents.contains("worktrees")
}

private func resolveGitDirFromFile(_ gitFileURL: URL) -> URL? {
    guard let content = try? String(contentsOf: gitFileURL, encoding: .utf8) else {
        return nil
    }
    guard let firstLine = content.split(whereSeparator: \.isNewline).first?.trimmingCharacters(in: .whitespacesAndNewlines),
          firstLine.hasPrefix("gitdir:")
    else {
        return nil
    }
    let rawPath = String(firstLine.dropFirst("gitdir:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawPath.isEmpty else {
        return nil
    }
    let candidateURL = URL(fileURLWithPath: rawPath)
    if candidateURL.path.hasPrefix("/") {
        return candidateURL
    }
    return gitFileURL.deletingLastPathComponent().appending(path: rawPath).standardizedFileURL
}

func createWorktreeProjectID(path: String) -> String {
    "worktree:\(path)"
}

func resolveWorktreeName(_ path: String) -> String {
    pathLastComponent(path)
}

func buildReadyWorktree(path: String, branch: String, now: SwiftDate) -> ProjectWorktree {
    ProjectWorktree(
        id: createWorktreeProjectID(path: path),
        name: resolveWorktreeName(path),
        path: path,
        branch: branch,
        inheritConfig: true,
        created: now,
        updatedAt: now
    )
}

func buildWorktreeVirtualProject(sourceProject: Project, worktree: ProjectWorktree) -> Project {
    let now = swiftDateFromDate(Date())
    return Project(
        id: createWorktreeProjectID(path: worktree.path),
        name: worktree.name,
        path: worktree.path,
        tags: sourceProject.tags,
        runConfigurations: sourceProject.runConfigurations,
        worktrees: [],
        mtime: sourceProject.mtime,
        size: sourceProject.size,
        checksum: "worktree:\(worktree.path)",
        isGitRepository: sourceProject.isGitRepository,
        gitCommits: sourceProject.gitCommits,
        gitLastCommit: sourceProject.gitLastCommit,
        gitLastCommitMessage: sourceProject.gitLastCommitMessage,
        gitDaily: sourceProject.gitDaily,
        notesSummary: sourceProject.notesSummary,
        created: worktree.created,
        checked: now,
        hasPersistedNotesSummary: sourceProject.hasPersistedNotesSummary
    )
}

func buildSyncedWorktrees(
    existingWorktrees: [ProjectWorktree],
    gitWorktrees: [NativeGitWorktree],
    preservedLiveWorktrees: [ProjectWorktree] = [],
    promotedPendingWorktrees: [ProjectWorktree] = []
) -> [ProjectWorktree] {
    let existingByPath = Dictionary(uniqueKeysWithValues: existingWorktrees.map { (nativeAppNormalizePathForCompare($0.path), $0) })
    let promotedPendingByPath = Dictionary(uniqueKeysWithValues: promotedPendingWorktrees.map {
        (nativeAppNormalizePathForCompare($0.path), $0)
    })
    let now = swiftDateFromDate(Date())
    var mergedWorktrees = gitWorktrees
        .map { item -> ProjectWorktree in
            let normalizedPath = nativeAppNormalizePathForCompare(item.path)
            let existing = existingByPath[normalizedPath] ?? promotedPendingByPath[normalizedPath]
            return ProjectWorktree(
                id: existing?.id ?? createWorktreeProjectID(path: item.path),
                name: existing?.name ?? resolveWorktreeName(item.path),
                path: item.path,
                branch: item.branch,
                baseBranch: existing?.baseBranch,
                inheritConfig: existing?.inheritConfig ?? true,
                created: existing?.created ?? now,
                updatedAt: existing?.updatedAt
            )
        }
    for worktree in preservedLiveWorktrees where !mergedWorktrees.contains(where: {
        nativeAppNormalizePathForCompare($0.path) == nativeAppNormalizePathForCompare(worktree.path)
    }) {
        mergedWorktrees.append(
            ProjectWorktree(
                id: worktree.id,
                name: worktree.name,
                path: worktree.path,
                branch: worktree.branch,
                baseBranch: worktree.baseBranch,
                inheritConfig: worktree.inheritConfig,
                created: worktree.created,
                updatedAt: worktree.updatedAt
            )
        )
    }
    return mergedWorktrees.sorted { $0.path < $1.path }
}

func swiftDateFromDate(_ date: Date) -> SwiftDate {
    date.timeIntervalSinceReferenceDate
}

func hexColor(for color: ColorData) -> String {
    let r = Int(max(0, min(255, round(color.r * 255))))
    let g = Int(max(0, min(255, round(color.g * 255))))
    let b = Int(max(0, min(255, round(color.b * 255))))
    return String(format: "#%02X%02X%02X", r, g, b)
}
