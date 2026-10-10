import Foundation

/// 分组协同目录只组织项目路径，不复制仓库，也不切换成员分支。
public final class CmuxGroupWorkspaceRootStore {
    public struct Member: Codable, Equatable, Sendable {
        public let name: String
        public let path: String
        public let alias: String

        public init(name: String, path: String) {
            self.name = name
            self.path = URL(fileURLWithPath: path).standardizedFileURL.path
            // 保持同名项目和成员增删后的目录别名稳定。
            let digest = self.path.utf8.reduce(UInt64(14695981039346656037)) {
                ($0 ^ UInt64($1)) &* 1099511628211
            }
            let slug = URL(fileURLWithPath: path).lastPathComponent
                .replacingOccurrences(of: #"[^A-Za-z0-9_-]+"#, with: "-", options: .regularExpression)
                .prefix(40)
            self.alias = "\(slug.isEmpty ? "project" : String(slug))--\(String(digest, radix: 16))"
        }
    }

    public struct Manifest: Codable, Equatable, Sendable {
        public let version: Int
        public let id: UUID
        public let name: String
        public let members: [Member]
    }

    private let baseURL: URL
    private let fileManager: FileManager

    public init(baseURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.baseURL = baseURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".devhaven/workspaces", isDirectory: true)
    }

    public func rootURL(for id: UUID) -> URL {
        baseURL.appendingPathComponent("cmux-group--\(id.uuidString.lowercased())", isDirectory: true)
    }

    @discardableResult
    public func sync(id: UUID, name: String, members: [Member]) throws -> URL {
        let root = rootURL(for: id)
        var seen = Set<String>()
        let members = members.filter { seen.insert($0.path).inserted }
        guard Set(members.map(\.alias)).count == members.count else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        // 先检查成员目录，失败时保留上一份可用清单。
        for member in members {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: member.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: member.path])
            }
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let manifestURL = root.appendingPathComponent("WORKSPACE.json")
        let previous = (try? Data(contentsOf: manifestURL)).flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }
        let desiredAliases = Set(members.map(\.alias))
        for old in previous?.members ?? [] where !desiredAliases.contains(old.alias) {
            let link = root.appendingPathComponent(old.alias)
            // 只清理本模块生成且仍指向原成员的链接，不删除用户文件。
            if (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) == old.path {
                try fileManager.removeItem(at: link)
            }
        }
        for member in members {
            let link = root.appendingPathComponent(member.alias)
            if let target = try? fileManager.destinationOfSymbolicLink(atPath: link.path) {
                guard target == member.path else { throw CocoaError(.fileWriteFileExists) }
            } else {
                try fileManager.createSymbolicLink(atPath: link.path, withDestinationPath: member.path)
            }
        }
        let manifest = Manifest(version: 1, id: id, name: name, members: members)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        let readme = """
        # \(name)

        这是 DevHaven 的分组协同目录。组内项目通过符号链接访问，源码保留在各自原目录。
        此目录不是 Git 仓库。执行 Git、构建和修改操作时，请进入对应成员的真实目录。
        成员清单以 WORKSPACE.json 为准。成员各自的 AGENTS.md 约束仍然适用。

        \(members.map { "- \($0.name)\n  - 目录别名：`\($0.alias)`\n  - 真实路径：`\($0.path)`" }.joined(separator: "\n"))
        """
        try readme.write(to: root.appendingPathComponent("WORKSPACE.md"), atomically: true, encoding: .utf8)
        try """
        # 分组协同工作区

        先读取 WORKSPACE.md 和 WORKSPACE.json，确认当前组内的全部项目。
        根据用户的任务跨项目分析；修改前先读取目标项目自身的 AGENTS.md。
        此目录不属于任何成员的 Git 仓库。Git、构建及测试命令必须在成员真实路径执行。
        用户没有明确要求时，不执行提交、推送或部署。
        """.write(to: root.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        return root
    }

    /// 显式授权真实目录；符号链接本身不能替代 Codex 的目录范围配置。
    public func codexCommand(id: UUID, members: [Member], executable: String = "codex") -> String {
        var args = [executable, "--cd", rootURL(for: id).path]
        var seen = Set<String>()
        for member in members where seen.insert(member.path).inserted {
            args += ["--add-dir", member.path]
        }
        return args.map(Self.shellQuote).joined(separator: " ")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
