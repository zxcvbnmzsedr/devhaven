import Foundation

public enum LegacyCompatStoreError: LocalizedError {
    case invalidJSONObject(URL)
    case invalidJSONArray(URL)

    public var errorDescription: String? {
        switch self {
        case let .invalidJSONObject(url):
            return "JSON 根对象不是字典：\(url.path)"
        case let .invalidJSONArray(url):
            return "JSON 根对象不是数组：\(url.path)"
        }
    }
}

public final class LegacyCompatStore {
    private let fileManager: FileManager
    private let homeDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser, fileManager: FileManager = .default) {
        self.homeDirectoryURL = homeDirectoryURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    var backgroundWorkHomeDirectoryURL: URL {
        homeDirectoryURL
    }

    public var agentStatusSessionsDirectoryURL: URL {
        appDataDirectoryURL
            .appending(path: "agent-status", directoryHint: .isDirectory)
            .appending(path: "sessions", directoryHint: .isDirectory)
    }

    public var runLogsDirectoryURL: URL {
        appDataDirectoryURL
            .appending(path: "run-logs", directoryHint: .isDirectory)
    }

    public var workspaceRootsDirectoryURL: URL {
        appDataDirectoryURL
            .appending(path: "workspaces", directoryHint: .isDirectory)
    }

    public func loadSnapshot() throws -> NativeAppSnapshot {
        let appStateDocument = try loadAppStateDocument()
        let projects = try loadProjects()
        return NativeAppSnapshot(appState: try appStateDocument.decodeAppState(using: decoder), projects: projects)
    }

    public func updateRecycleBin(_ paths: [String]) throws {
        var document = try loadAppStateDocument()
        document.root["recycleBin"] = normalizePathList(paths)
        try saveAppStateDocument(document)
    }

    public func updateDirectories(_ paths: [String]) throws {
        var document = try loadAppStateDocument()
        document.root["directories"] = normalizePathList(paths)
        try saveAppStateDocument(document)
    }

    public func updateDirectProjectPaths(_ paths: [String]) throws {
        var document = try loadAppStateDocument()
        document.root["directProjectPaths"] = normalizePathList(paths)
        try saveAppStateDocument(document)
    }

    public func updateSettings(_ settings: AppSettings) throws {
        var document = try loadAppStateDocument()
        let encodedSettings = try makeJSONObject(from: settings)
        let existingSettings = document.root["settings"] as? [String: Any] ?? [:]
        document.root["settings"] = deepMerge(existing: existingSettings, updates: encodedSettings)
        try saveAppStateDocument(document)
    }

    public func updateFavoriteProjectPaths(_ paths: [String]) throws {
        var document = try loadAppStateDocument()
        document.root["favoriteProjectPaths"] = normalizePathList(paths)
        try saveAppStateDocument(document)
    }

    public func updateWorkspaceAlignmentGroups(_ groups: [WorkspaceAlignmentGroupDefinition]) throws {
        var document = try loadAppStateDocument()
        document.root["workspaceAlignmentGroups"] = try makeJSONArray(from: groups)
        document.root["version"] = 5
        try saveAppStateDocument(document)
    }

    public func loadProjectDocument(at projectPath: String) throws -> ProjectDocumentSnapshot {
        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        let notes = try readOptionalFile(at: projectURL.appending(path: "PROJECT_NOTES.md"))
        let todoMarkdown = try readOptionalFile(at: projectURL.appending(path: "PROJECT_TODO.md"))
        let readme = try readOptionalFile(at: projectURL.appending(path: "README.md"))
        return ProjectDocumentSnapshot(
            notes: notes,
            todoItems: TodoMarkdownCodec.parse(todoMarkdown ?? ""),
            readmeFallback: readme.map { MarkdownDocument(path: "README.md", content: $0) }
        )
    }

    public func writeNotes(_ notes: String?, for projectPath: String) throws {
        let fileURL = URL(fileURLWithPath: projectPath, isDirectory: true).appending(path: "PROJECT_NOTES.md")
        try writeOptionalFile(notes, to: fileURL)
    }

    public func writeTodoItems(_ items: [TodoItem], for projectPath: String) throws {
        let markdown = TodoMarkdownCodec.serialize(items)
        let fileURL = URL(fileURLWithPath: projectPath, isDirectory: true).appending(path: "PROJECT_TODO.md")
        try writeOptionalFile(markdown.isEmpty ? nil : markdown + "\n", to: fileURL)
    }

    public func updateProjectsGitDaily(_ results: [GitDailyRefreshResult]) throws {
        try updateProjectsGitMetadata(results)
    }

    public func updateProjectsGitMetadata(_ results: [GitDailyRefreshResult]) throws {
        guard !results.isEmpty else {
            return
        }
        var document = try loadProjectsDocument()
        let resultsByPath = Dictionary(uniqueKeysWithValues: results.map { ($0.path, $0) })
        var didMutate = false

        for index in document.root.indices {
            guard var project = document.root[index] as? [String: Any],
                  let path = project["path"] as? String,
                  let result = resultsByPath[path],
                  result.error == nil
            else {
                continue
            }
            project["git_daily"] = result.gitDaily.map { $0 as Any } ?? NSNull()
            if let gitCommits = result.gitCommits {
                project["git_commits"] = gitCommits
                project["git_last_commit"] = result.gitLastCommit ?? 0
                project["git_last_commit_message"] = result.gitLastCommitMessage.map { $0 as Any } ?? NSNull()
            }
            document.root[index] = project
            didMutate = true
        }

        if didMutate {
            try saveProjectsDocument(document)
        }
    }

    public func updateProjectsNotesSummary(_ summariesByPath: [String: String?]) throws {
        guard !summariesByPath.isEmpty else {
            return
        }

        var document = try loadProjectsDocument()
        let normalizedSummaries = Dictionary(uniqueKeysWithValues: summariesByPath.map {
            (normalizeLegacyStorePathForCompare($0.key), $0.value)
        })
        var didMutate = false

        for index in document.root.indices {
            guard var project = document.root[index] as? [String: Any],
                  let path = project["path"] as? String
            else {
                continue
            }
            let normalizedPath = normalizeLegacyStorePathForCompare(path)
            guard normalizedSummaries.keys.contains(normalizedPath) else {
                continue
            }

            switch normalizedSummaries[normalizedPath] ?? nil {
            case let summary?:
                project["notes_summary"] = summary
            case nil:
                project["notes_summary"] = NSNull()
            }
            document.root[index] = project
            didMutate = true
        }

        if didMutate {
            try saveProjectsDocument(document)
        }
    }

    public func updateProjects(_ projects: [Project]) throws {
        let data = try encoder.encode(projects)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [Any] else {
            throw LegacyCompatStoreError.invalidJSONArray(projectsFileURL)
        }
        try saveProjectsDocument(ProjectsDocument(root: root))
    }

    private func loadProjects() throws -> [Project] {
        let fileURL = projectsFileURL
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([Project].self, from: data)
    }

    private func loadProjectsDocument() throws -> ProjectsDocument {
        let fileURL = projectsFileURL
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return ProjectsDocument(root: [])
        }
        let data = try Data(contentsOf: fileURL)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [Any] else {
            throw LegacyCompatStoreError.invalidJSONArray(fileURL)
        }
        return ProjectsDocument(root: root)
    }

    private func loadAppStateDocument() throws -> AppStateDocument {
        let fileURL = appStateFileURL
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return AppStateDocument(root: try makeJSONObject(from: AppStateFile()))
        }
        let data = try Data(contentsOf: fileURL)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw LegacyCompatStoreError.invalidJSONObject(fileURL)
        }
        return AppStateDocument(root: root)
    }

    private func saveAppStateDocument(_ document: AppStateDocument) throws {
        let directoryURL = appDataDirectoryURL
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: document.root, options: [.prettyPrinted, .sortedKeys])
        var normalized = data
        normalized.append(0x0A)
        try normalized.write(to: appStateFileURL, options: .atomic)
    }

    private func saveProjectsDocument(_ document: ProjectsDocument) throws {
        try fileManager.createDirectory(at: appDataDirectoryURL, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: document.root, options: [.prettyPrinted, .sortedKeys])
        var normalized = data
        normalized.append(0x0A)
        try normalized.write(to: projectsFileURL, options: .atomic)
    }

    private func readOptionalFile(at url: URL) throws -> String? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        return content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : content
    }

    private func writeOptionalFile(_ content: String?, to url: URL) throws {
        if let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        } else if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func makeJSONObject<T: Encodable>(from value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw LegacyCompatStoreError.invalidJSONObject(appStateFileURL)
        }
        return dictionary
    }

    private func makeJSONArray<T: Encodable>(from value: T) throws -> [Any] {
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let array = object as? [Any] else {
            throw LegacyCompatStoreError.invalidJSONArray(appStateFileURL)
        }
        return array
    }

    private var appDataDirectoryURL: URL {
        homeDirectoryURL.appending(path: ".devhaven", directoryHint: .isDirectory)
    }

    private var appStateFileURL: URL {
        appDataDirectoryURL.appending(path: "app_state.json")
    }

    private var projectsFileURL: URL {
        appDataDirectoryURL.appending(path: "projects.json")
    }
}

private func normalizeLegacyStorePathForCompare(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return ""
    }
    return URL(fileURLWithPath: trimmed).standardizedFileURL.path
}

private struct AppStateDocument {
    var root: [String: Any]

    func decodeAppState(using decoder: JSONDecoder) throws -> AppStateFile {
        let data = try JSONSerialization.data(withJSONObject: root, options: [])
        return try decoder.decode(AppStateFile.self, from: data)
    }
}

private struct ProjectsDocument {
    var root: [Any]
}

private func normalizePathList(_ paths: [String]) -> [String] {
    var seen = Set<String>()
    return paths
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .filter { seen.insert($0).inserted }
}

private func deepMerge(existing: [String: Any], updates: [String: Any]) -> [String: Any] {
    var merged = existing
    for (key, updateValue) in updates {
        if let existingObject = merged[key] as? [String: Any], let updateObject = updateValue as? [String: Any] {
            merged[key] = deepMerge(existing: existingObject, updates: updateObject)
        } else {
            merged[key] = updateValue
        }
    }
    return merged
}
