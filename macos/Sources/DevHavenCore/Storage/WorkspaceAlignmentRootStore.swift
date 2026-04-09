import Foundation

public struct WorkspaceAlignmentRootManifest: Codable, Equatable, Sendable {
    public struct Member: Codable, Equatable, Sendable {
        public var alias: String
        public var projectName: String
        public var projectPath: String
        public var openPath: String
        public var branch: String
        public var status: String

        public init(
            alias: String,
            projectName: String,
            projectPath: String,
            openPath: String,
            branch: String,
            status: String
        ) {
            self.alias = alias
            self.projectName = projectName
            self.projectPath = projectPath
            self.openPath = openPath
            self.branch = branch
            self.status = status
        }
    }

    public var id: String
    public var name: String
    public var workspaceRootPath: String
    public var generatedAt: Date
    public var members: [Member]

    public init(
        id: String,
        name: String,
        workspaceRootPath: String,
        generatedAt: Date = Date(),
        members: [Member]
    ) {
        self.id = id
        self.name = name
        self.workspaceRootPath = workspaceRootPath
        self.generatedAt = generatedAt
        self.members = members
    }
}

public final class WorkspaceAlignmentRootStore {
    private let baseDirectoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    public init(
        baseDirectoryURL: URL,
        fileManager: FileManager = .default
    ) {
        self.baseDirectoryURL = baseDirectoryURL
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func rootURL(for definition: WorkspaceAlignmentGroupDefinition) -> URL {
        let trimmedDirectoryName = definition.rootDirectoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let directoryName = (trimmedDirectoryName.isEmpty ? nil : trimmedDirectoryName)
            ?? makeWorkspaceAlignmentRootDirectoryName(name: definition.name, id: definition.id)
        return baseDirectoryURL.appending(path: directoryName, directoryHint: .isDirectory)
    }

    @discardableResult
    public func syncRoot(for group: WorkspaceAlignmentGroupProjection) throws -> URL {
        let rootURL = rootURL(for: group.definition)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let originalProjectPathsByNormalizedPath = Dictionary(
            uniqueKeysWithValues: group.definition.effectiveMembers.map { member in
                (normalizeWorkspaceAlignmentProjectPath(member.projectPath), member.projectPath)
            }
        )

        let members = group.members.map { member in
            WorkspaceAlignmentRootManifest.Member(
                alias: member.alias,
                projectName: member.projectName,
                projectPath: originalProjectPathsByNormalizedPath[normalizeWorkspaceAlignmentProjectPath(member.projectPath)] ?? member.projectPath,
                openPath: member.openTarget.path,
                branch: member.branchLabel,
                status: member.status.displayText
            )
        }

        let manifest = WorkspaceAlignmentRootManifest(
            id: group.definition.id,
            name: group.definition.name,
            workspaceRootPath: rootURL.path,
            members: members
        )

        try writeManifest(manifest, to: rootURL)
        try writeReadme(for: manifest, to: rootURL)
        try syncMemberLinks(members, to: rootURL)
        return rootURL
    }

    public func removeRoot(for definition: WorkspaceAlignmentGroupDefinition) throws {
        let rootURL = rootURL(for: definition)
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return
        }
        try fileManager.removeItem(at: rootURL)
    }

    private func writeManifest(_ manifest: WorkspaceAlignmentRootManifest, to rootURL: URL) throws {
        let fileURL = rootURL.appending(path: "WORKSPACE.json", directoryHint: .notDirectory)
        let data = try encoder.encode(manifest)
        var normalized = data
        normalized.append(0x0A)
        try normalized.write(to: fileURL, options: .atomic)
    }

    private func writeReadme(for manifest: WorkspaceAlignmentRootManifest, to rootURL: URL) throws {
        let fileURL = rootURL.appending(path: "WORKSPACE.md", directoryHint: .notDirectory)
        let lines: [String] = [
            "# \(manifest.name)",
            "",
            "这是 DevHaven 自动生成的协同工作区根目录。",
            "",
            "## Members",
            manifest.members.isEmpty
                ? "- 暂无成员"
                : manifest.members.map { member in
                    "- `\(member.alias)` · \(member.projectName) · \(member.branch) · \(member.status)\n  - open: `\(member.openPath)`"
                }.joined(separator: "\n"),
            "",
            manifest.members.isEmpty
                ? ""
                : "提示：可直接 `cd \(manifest.members.first?.alias ?? "")` 进入某个成员目录。"
        ]
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func syncMemberLinks(
        _ members: [WorkspaceAlignmentRootManifest.Member],
        to rootURL: URL
    ) throws {
        let desiredAliases = Set(members.map(\.alias))
        let reservedNames = Set(["WORKSPACE.json", "WORKSPACE.md"])
        let existingURLs = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )

        for url in existingURLs {
            let name = url.lastPathComponent
            guard !reservedNames.contains(name) else {
                continue
            }
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true, !desiredAliases.contains(name) {
                try fileManager.removeItem(at: url)
            }
        }

        for member in members {
            let linkURL = rootURL.appending(path: member.alias, directoryHint: .notDirectory)
            if fileManager.fileExists(atPath: linkURL.path) || isDanglingSymlink(at: linkURL) {
                try fileManager.removeItem(at: linkURL)
            }
            try fileManager.createSymbolicLink(atPath: linkURL.path, withDestinationPath: member.openPath)
        }
    }

    private func isDanglingSymlink(at url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            return values.isSymbolicLink == true
        } catch {
            return false
        }
    }
}

public func makeWorkspaceAlignmentRootDirectoryName(name: String, id: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let slug = trimmed
        .replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
    let normalizedSlug = slug.isEmpty ? "workspace" : slug.lowercased()
    let shortID = id.replacingOccurrences(of: "-", with: "")
    return "\(normalizedSlug)--\(String(shortID.prefix(6)))"
}

private func normalizeWorkspaceAlignmentProjectPath(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return ""
    }
    return URL(fileURLWithPath: trimmed).standardizedFileURL.path
}
