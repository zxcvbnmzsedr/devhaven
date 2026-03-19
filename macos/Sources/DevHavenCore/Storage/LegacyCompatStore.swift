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

    public func listSharedScripts(rootOverride: String? = nil) throws -> [SharedScriptEntry] {
        let root = resolveSharedScriptsRoot(rootOverride)
        try ensureBuiltinPresetsOnFirstRun(root: root)
        guard fileManager.fileExists(atPath: root.path) else {
            return []
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NSError(domain: "DevHavenCore.SharedScripts", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "通用脚本目录不是文件夹：\(root.path)"
            ])
        }

        let manifestURL = root.appending(path: manifestFileName)
        let entries = if fileManager.fileExists(atPath: manifestURL.path) {
            try listManifestScripts(root: root, manifestURL: manifestURL)
        } else {
            try scanScriptsFromDirectory(root: root)
        }

        return entries.sorted {
            let leftName = $0.name.lowercased()
            let rightName = $1.name.lowercased()
            if leftName != rightName {
                return leftName < rightName
            }
            return $0.relativePath < $1.relativePath
        }
    }

    public func saveSharedScriptsManifest(_ scripts: [SharedScriptManifestScript], rootOverride: String? = nil) throws {
        let root = resolveSharedScriptsRoot(rootOverride)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        var usedIds = Set<String>()
        var manifestEntries = [SharedScriptsManifestEntry]()

        for (index, script) in scripts.enumerated() {
            let id = script.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                throw NSError(domain: "DevHavenCore.SharedScripts", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "第 \(index + 1) 个脚本缺少 id"
                ])
            }
            guard usedIds.insert(id).inserted else {
                throw NSError(domain: "DevHavenCore.SharedScripts", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "脚本 id 重复：\(id)"
                ])
            }
            guard let normalizedPath = normalizeRelativePath(script.path) else {
                throw NSError(domain: "DevHavenCore.SharedScripts", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "脚本路径不合法（id=\(id)）：\(script.path)"
                ])
            }

            let name = script.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? deriveScriptName(from: normalizedPath)
                : script.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let commandTemplate = script.commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            manifestEntries.append(
                SharedScriptsManifestEntry(
                    id: id,
                    name: name,
                    path: normalizedPath,
                    commandTemplate: commandTemplate.isEmpty ? defaultSharedScriptCommandTemplate : commandTemplate,
                    params: normalizeParamFields(script.params)
                )
            )
        }

        let presetVersion = try readManifestPresetVersion(manifestURL: root.appending(path: manifestFileName))
        try writeManifest(root: root, entries: manifestEntries, presetVersion: presetVersion)
    }

    public func restoreSharedScriptPresets(rootOverride: String? = nil) throws -> SharedScriptPresetRestoreResult {
        try applyBuiltinPresets(root: resolveSharedScriptsRoot(rootOverride))
    }

    public func readSharedScriptFile(relativePath: String, rootOverride: String? = nil) throws -> String {
        let targetURL = try resolveSharedScriptFileURL(relativePath: relativePath, rootOverride: rootOverride)
        return try String(contentsOf: targetURL, encoding: .utf8)
    }

    public func writeSharedScriptFile(relativePath: String, content: String, rootOverride: String? = nil) throws {
        let targetURL = try resolveSharedScriptFileURL(relativePath: relativePath, rootOverride: rootOverride)
        try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: targetURL, atomically: true, encoding: .utf8)
    }

    public func updateProjectsGitDaily(_ results: [GitDailyRefreshResult]) throws {
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
            document.root[index] = project
            didMutate = true
        }

        if didMutate {
            try saveProjectsDocument(document)
        }
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

private let defaultSharedScriptsRoot = "~/.devhaven/scripts"
private let manifestFileName = "manifest.json"
private let defaultSharedScriptCommandTemplate = "bash \"${scriptPath}\""
private let builtinSharedScriptPresetVersion = "2026.03.native.1"

private struct SharedScriptsManifest: Codable {
    var presetVersion: String?
    var scripts: [SharedScriptsManifestEntry]
}

private struct SharedScriptsManifestEntry: Codable {
    var id: String
    var name: String
    var path: String
    var commandTemplate: String
    var params: [ScriptParamField]
}

private struct SharedScriptPreset {
    var manifest: SharedScriptsManifestEntry
    var fileContent: String
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

private extension LegacyCompatStore {
    func resolveSharedScriptsRoot(_ rootOverride: String?) -> URL {
        let configured = rootOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = (configured?.isEmpty == false ? configured! : defaultSharedScriptsRoot)
        return URL(fileURLWithPath: expandHomePath(candidate), isDirectory: true)
    }

    func expandHomePath(_ path: String) -> String {
        if path == "~" {
            return homeDirectoryURL.path
        }
        if path.hasPrefix("~/") {
            return homeDirectoryURL.appending(path: String(path.dropFirst(2))).path()
        }
        let candidate = URL(fileURLWithPath: path)
        if candidate.path.hasPrefix("/") {
            return candidate.path
        }
        return homeDirectoryURL.appending(path: path).path()
    }

    func resolveSharedScriptFileURL(relativePath: String, rootOverride: String?) throws -> URL {
        guard let normalized = normalizeRelativePath(relativePath) else {
            throw NSError(domain: "DevHavenCore.SharedScripts", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "脚本相对路径不合法：\(relativePath)"
            ])
        }
        return resolveSharedScriptsRoot(rootOverride).appending(path: normalized)
    }

    func ensureBuiltinPresetsOnFirstRun(root: URL) throws {
        if !fileManager.fileExists(atPath: root.path) {
            _ = try applyBuiltinPresets(root: root)
            return
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NSError(domain: "DevHavenCore.SharedScripts", code: 6, userInfo: [
                NSLocalizedDescriptionKey: "通用脚本目录不是文件夹：\(root.path)"
            ])
        }

        let manifestURL = root.appending(path: manifestFileName)
        if fileManager.fileExists(atPath: manifestURL.path) {
            return
        }

        if try scanScriptsFromDirectory(root: root).isEmpty {
            _ = try applyBuiltinPresets(root: root)
        }
    }

    func applyBuiltinPresets(root: URL) throws -> SharedScriptPresetRestoreResult {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let manifestURL = root.appending(path: manifestFileName)
        var manifestScripts = if fileManager.fileExists(atPath: manifestURL.path) {
            try listManifestScripts(root: root, manifestURL: manifestURL).map { entry in
                SharedScriptManifestScript(
                    id: entry.id,
                    name: entry.name,
                    path: entry.relativePath,
                    commandTemplate: entry.commandTemplate,
                    params: entry.params
                )
            }
        } else {
            try scanScriptsFromDirectory(root: root).map { entry in
                SharedScriptManifestScript(
                    id: entry.id,
                    name: entry.name,
                    path: entry.relativePath,
                    commandTemplate: entry.commandTemplate,
                    params: entry.params
                )
            }
        }

        var usedIds = Set(manifestScripts.map(\.id))
        var usedPaths = Set(manifestScripts.compactMap { normalizeRelativePath($0.path) })

        var addedScripts = 0
        var skippedScripts = 0
        var createdFiles = 0

        for preset in builtinSharedScriptPresets() {
            let normalizedPath = normalizeRelativePath(preset.manifest.path) ?? preset.manifest.path
            if usedIds.contains(preset.manifest.id) || usedPaths.contains(normalizedPath) {
                skippedScripts += 1
            } else {
                usedIds.insert(preset.manifest.id)
                usedPaths.insert(normalizedPath)
                manifestScripts.append(
                    SharedScriptManifestScript(
                        id: preset.manifest.id,
                        name: preset.manifest.name,
                        path: normalizedPath,
                        commandTemplate: preset.manifest.commandTemplate,
                        params: preset.manifest.params
                    )
                )
                addedScripts += 1
            }

            let targetURL = root.appending(path: preset.manifest.path)
            if try writeFileIfAbsent(at: targetURL, content: preset.fileContent) {
                createdFiles += 1
            }
        }

        let currentPresetVersion = try readManifestPresetVersion(manifestURL: manifestURL)
        if addedScripts > 0 || !fileManager.fileExists(atPath: manifestURL.path) || currentPresetVersion != builtinSharedScriptPresetVersion {
            try writeManifest(
                root: root,
                entries: manifestScripts.map {
                    SharedScriptsManifestEntry(
                        id: $0.id,
                        name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? deriveScriptName(from: $0.path) : $0.name,
                        path: normalizeRelativePath($0.path) ?? $0.path,
                        commandTemplate: $0.commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultSharedScriptCommandTemplate : $0.commandTemplate,
                        params: normalizeParamFields($0.params)
                    )
                },
                presetVersion: builtinSharedScriptPresetVersion
            )
        }

        return SharedScriptPresetRestoreResult(
            presetVersion: builtinSharedScriptPresetVersion,
            addedScripts: addedScripts,
            skippedScripts: skippedScripts,
            createdFiles: createdFiles
        )
    }

    func listManifestScripts(root: URL, manifestURL: URL) throws -> [SharedScriptEntry] {
        let manifest = try readManifest(manifestURL: manifestURL)
        var usedIds = Set<String>()
        var entries = [SharedScriptEntry]()

        for (index, item) in manifest.scripts.enumerated() {
            let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                throw NSError(domain: "DevHavenCore.SharedScripts", code: 7, userInfo: [
                    NSLocalizedDescriptionKey: "通用脚本清单第 \(index + 1) 项缺少 id"
                ])
            }
            guard usedIds.insert(id).inserted else {
                throw NSError(domain: "DevHavenCore.SharedScripts", code: 8, userInfo: [
                    NSLocalizedDescriptionKey: "通用脚本清单存在重复 id：\(id)"
                ])
            }
            guard let normalizedPath = normalizeRelativePath(item.path) else {
                throw NSError(domain: "DevHavenCore.SharedScripts", code: 9, userInfo: [
                    NSLocalizedDescriptionKey: "通用脚本路径不合法（id=\(id)）：\(item.path)"
                ])
            }
            let commandTemplate = item.commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? defaultSharedScriptCommandTemplate
                : item.commandTemplate
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? deriveScriptName(from: normalizedPath)
                : item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            entries.append(
                SharedScriptEntry(
                    id: id,
                    name: name,
                    absolutePath: root.appending(path: normalizedPath).path(),
                    relativePath: normalizedPath,
                    commandTemplate: commandTemplate,
                    params: normalizeParamFields(item.params)
                )
            )
        }

        return entries
    }

    func scanScriptsFromDirectory(root: URL) throws -> [SharedScriptEntry] {
        guard fileManager.fileExists(atPath: root.path) else {
            return []
        }
        var usedIds = Set<String>()
        var entries = [SharedScriptEntry]()
        let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey], options: [.skipsHiddenFiles])

        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if resourceValues.isDirectory == true {
                continue
            }
            guard resourceValues.isRegularFile == true, fileURL.lastPathComponent != manifestFileName, isScriptCandidate(fileURL) else {
                continue
            }
            let relativePath = fileURL.path().replacingOccurrences(of: root.path + "/", with: "")
            let normalizedPath = relativePath.replacingOccurrences(of: "\\", with: "/")
            let id = ensureUniqueID(base: createScannedID(relativePath: normalizedPath), usedIds: &usedIds)
            entries.append(
                SharedScriptEntry(
                    id: id,
                    name: deriveScriptName(from: normalizedPath),
                    absolutePath: fileURL.path(),
                    relativePath: normalizedPath,
                    commandTemplate: defaultSharedScriptCommandTemplate,
                    params: []
                )
            )
        }

        return entries
    }

    func readManifest(manifestURL: URL) throws -> SharedScriptsManifest {
        let data = try Data(contentsOf: manifestURL)
        return try decoder.decode(SharedScriptsManifest.self, from: data)
    }

    func readManifestPresetVersion(manifestURL: URL) throws -> String? {
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return nil
        }
        return try? readManifest(manifestURL: manifestURL).presetVersion
    }

    func writeManifest(root: URL, entries: [SharedScriptsManifestEntry], presetVersion: String?) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = SharedScriptsManifest(presetVersion: presetVersion, scripts: entries)
        let data = try encoder.encode(manifest)
        var normalized = data
        normalized.append(0x0A)
        try normalized.write(to: root.appending(path: manifestFileName), options: .atomic)
    }

    func writeFileIfAbsent(at url: URL, content: String) throws -> Bool {
        guard !fileManager.fileExists(atPath: url.path) else {
            return false
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return true
    }
}

private func normalizeRelativePath(_ path: String) -> String? {
    let components = path
        .split(separator: "/")
        .flatMap { $0.split(separator: "\\") }
        .map(String.init)
        .filter { !$0.isEmpty && $0 != "." }
    guard !components.isEmpty, !components.contains("..") else {
        return nil
    }
    return components.joined(separator: "/")
}

private func normalizeParamFields(_ fields: [ScriptParamField]) -> [ScriptParamField] {
    var usedKeys = Set<String>()
    return fields.compactMap { field in
        let key = field.key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, usedKeys.insert(key).inserted else {
            return nil
        }
        let label = field.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? key : field.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultValue = field.defaultValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = field.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScriptParamField(
            key: key,
            label: label,
            type: field.type,
            required: field.required,
            defaultValue: defaultValue?.isEmpty == true ? nil : defaultValue,
            description: description?.isEmpty == true ? nil : description
        )
    }
}

private func deriveScriptName(from relativePath: String) -> String {
    URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent
}

private func createScannedID(relativePath: String) -> String {
    let transformed = relativePath.map { character -> Character in
        if character.isLetter || character.isNumber {
            return Character(String(character).lowercased())
        }
        return "-"
    }
    let compact = String(transformed).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return compact.isEmpty ? "shared-script" : compact
}

private func ensureUniqueID(base: String, usedIds: inout Set<String>) -> String {
    if usedIds.insert(base).inserted {
        return base
    }
    var index = 2
    while true {
        let candidate = "\(base)-\(index)"
        if usedIds.insert(candidate).inserted {
            return candidate
        }
        index += 1
    }
}

private func isScriptCandidate(_ fileURL: URL) -> Bool {
    let extensions = Set(["sh", "bash", "zsh", "fish", "command", "ps1", "cmd", "bat", "py"])
    if extensions.contains(fileURL.pathExtension.lowercased()) {
        return true
    }

    let permissions = (try? FileManager.default.attributesOfItem(atPath: fileURL.path())[.posixPermissions] as? NSNumber)?.intValue ?? 0
    return permissions & 0o111 != 0
}

private func builtinSharedScriptPresets() -> [SharedScriptPreset] {
    [
        SharedScriptPreset(
            manifest: SharedScriptsManifestEntry(
                id: "jenkins",
                name: "Jenkins 部署",
                path: "jenkins-depoly",
                commandTemplate: """
                export JENKINS_PASSWORD="${password}"
                python3 "${scriptPath}" --jenkins-url "${host}" --username "${username}" --job "${job}"
                """,
                params: [
                    ScriptParamField(key: "host", label: "Jenkins 地址", type: .text, required: true, defaultValue: nil, description: "例如：https://jenkins.example.com"),
                    ScriptParamField(key: "username", label: "用户名", type: .text, required: true, defaultValue: nil, description: nil),
                    ScriptParamField(key: "password", label: "密码", type: .secret, required: true, defaultValue: nil, description: nil),
                    ScriptParamField(key: "job", label: "任务", type: .text, required: true, defaultValue: nil, description: "Jenkins job 名称"),
                ]
            ),
            fileContent: """
            #!/usr/bin/env python3
            import argparse
            import json
            import sys

            parser = argparse.ArgumentParser(description="DevHaven 原生内置 Jenkins 脚本")
            parser.add_argument("--jenkins-url", required=True)
            parser.add_argument("--username", required=True)
            parser.add_argument("--job", required=True)
            args = parser.parse_args()

            print(json.dumps({
                "status": "placeholder",
                "message": "原生预设已创建，请按需替换为你的 Jenkins 自动化脚本。",
                "jenkinsUrl": args.jenkins_url,
                "username": args.username,
                "job": args.job,
            }, ensure_ascii=False))
            sys.exit(0)
            """
        ),
        SharedScriptPreset(
            manifest: SharedScriptsManifestEntry(
                id: "remote-log-viewer",
                name: "远程日志查看",
                path: "remote_log_viewer.sh",
                commandTemplate: """
                server=${server}
                logPath=${logPath}
                user=${user}
                port=${port}
                identityFile=${identityFile}
                lines=${lines}
                follow=${follow}
                strictHostKeyChecking=${strictHostKeyChecking}
                allowPasswordPrompt=${allowPasswordPrompt}

                args=()
                if [ -n "$user" ]; then args+=(--user "$user"); fi
                if [ -n "$port" ]; then args+=(--port "$port"); fi
                if [ -n "$identityFile" ]; then args+=(--identity-file "$identityFile"); fi
                if [ -n "$lines" ]; then args+=(--lines "$lines"); fi
                if [ "$follow" = "1" ]; then args+=(--follow); fi
                if [ -n "$strictHostKeyChecking" ]; then args+=(--strict-host-key-checking "$strictHostKeyChecking"); fi
                if [ "$allowPasswordPrompt" = "1" ]; then args+=(--allow-password-prompt); fi

                exec bash "${scriptPath}" "${args[@]}" "$server" "$logPath"
                """,
                params: [
                    ScriptParamField(key: "server", label: "服务器", type: .text, required: true, defaultValue: nil, description: "例如：10.0.0.12 或 user@10.0.0.12"),
                    ScriptParamField(key: "logPath", label: "日志路径", type: .text, required: true, defaultValue: nil, description: "例如：/var/log/nginx/error.log"),
                    ScriptParamField(key: "user", label: "SSH 用户", type: .text, required: false, defaultValue: nil, description: "当 server 已包含 user@host 时可留空"),
                    ScriptParamField(key: "port", label: "SSH 端口", type: .number, required: false, defaultValue: "22", description: nil),
                    ScriptParamField(key: "identityFile", label: "私钥文件", type: .text, required: false, defaultValue: nil, description: "例如：~/.ssh/id_rsa"),
                    ScriptParamField(key: "lines", label: "输出行数", type: .number, required: false, defaultValue: "200", description: nil),
                    ScriptParamField(key: "follow", label: "持续跟踪", type: .number, required: false, defaultValue: "0", description: "填 1 开启（追加 --follow）"),
                    ScriptParamField(key: "strictHostKeyChecking", label: "StrictHostKeyChecking", type: .text, required: false, defaultValue: "accept-new", description: "可选值：yes/no/accept-new"),
                    ScriptParamField(key: "allowPasswordPrompt", label: "允许密码交互", type: .number, required: false, defaultValue: "0", description: "填 1 开启（关闭 BatchMode）"),
                ]
            ),
            fileContent: """
            #!/usr/bin/env bash
            set -euo pipefail

            usage() {
              cat <<'EOF'
            用法：
              remote_log_viewer.sh [选项] <server> <log_path>

            说明：
              这是 DevHaven 原生内置的远程日志查看预设，可直接作为可编辑起点。
            EOF
            }

            args=()
            while [[ $# -gt 0 ]]; do
              case "$1" in
                --user) args+=("-l" "$2"); shift 2 ;;
                --port) args+=("-p" "$2"); shift 2 ;;
                --identity-file) args+=("-i" "$2"); shift 2 ;;
                --lines) lines="$2"; shift 2 ;;
                --follow) follow=1; shift ;;
                --strict-host-key-checking) strict="$2"; shift 2 ;;
                --allow-password-prompt) allow_password=1; shift ;;
                -h|--help) usage; exit 0 ;;
                *) break ;;
              esac
            done

            server="${1:-}"
            log_path="${2:-}"
            lines="${lines:-200}"
            follow="${follow:-0}"
            strict="${strict:-accept-new}"
            allow_password="${allow_password:-0}"

            if [[ -z "$server" || -z "$log_path" ]]; then
              usage
              exit 1
            fi

            ssh_opts=("-o" "StrictHostKeyChecking=${strict}")
            if [[ "$allow_password" != "1" ]]; then
              ssh_opts+=("-o" "BatchMode=yes")
            fi

            if [[ "$follow" == "1" ]]; then
              exec ssh "${ssh_opts[@]}" "${args[@]}" "$server" "tail -n ${lines} -f '${log_path}'"
            fi

            exec ssh "${ssh_opts[@]}" "${args[@]}" "$server" "tail -n ${lines} '${log_path}'"
            """
        ),
    ]
}
