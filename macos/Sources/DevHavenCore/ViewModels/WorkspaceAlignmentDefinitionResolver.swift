import Foundation

@MainActor
final class WorkspaceAlignmentDefinitionResolver {
    private let normalizePath: @MainActor (String) -> String
    private let normalizePathList: @MainActor ([String]) -> [String]
    private let pathLastComponent: @MainActor (String) -> String
    private let projectsByNormalizedPath: @MainActor () -> [String: Project]
    private let existingDefinitions: @MainActor () -> [WorkspaceAlignmentGroupDefinition]

    init(
        normalizePath: @escaping @MainActor (String) -> String,
        normalizePathList: @escaping @MainActor ([String]) -> [String],
        pathLastComponent: @escaping @MainActor (String) -> String,
        projectsByNormalizedPath: @escaping @MainActor () -> [String: Project],
        existingDefinitions: @escaping @MainActor () -> [WorkspaceAlignmentGroupDefinition]
    ) {
        self.normalizePath = normalizePath
        self.normalizePathList = normalizePathList
        self.pathLastComponent = pathLastComponent
        self.projectsByNormalizedPath = projectsByNormalizedPath
        self.existingDefinitions = existingDefinitions
    }

    func validate(
        _ definition: WorkspaceAlignmentGroupDefinition,
        replacing groupID: String?
    ) throws {
        guard !definition.name.isEmpty else {
            throw NativeWorktreeError.invalidProject("工作区名称不能为空")
        }
        let duplicateName = existingDefinitions().contains {
            $0.id != groupID && $0.name.caseInsensitiveCompare(definition.name) == .orderedSame
        }
        if duplicateName {
            throw NativeWorktreeError.invalidProject("已存在同名工作区")
        }
        let members = definition.effectiveMembers
        let normalizedMemberPaths = members.map { normalizePath($0.projectPath) }
        if Set(normalizedMemberPaths).count != normalizedMemberPaths.count {
            throw NativeWorktreeError.invalidProject("工作区内存在重复项目")
        }
        for member in members {
            if member.targetBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw NativeWorktreeError.invalidBranch("请为 \(projectName(for: member.projectPath)) 填写目标 branch")
            }
            if member.specifiedBaseBranch?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                throw NativeWorktreeError.invalidBaseBranch("请为 \(projectName(for: member.projectPath)) 选择基线分支")
            }
        }
    }

    func aliases(
        for projectPaths: [String],
        existing: [String: String],
        projectsByNormalizedPath explicitProjectsByNormalizedPath: [String: Project]? = nil
    ) -> [String: String] {
        let normalizedPaths = normalizePathList(projectPaths)
        let projectsByNormalizedPath = explicitProjectsByNormalizedPath ?? self.projectsByNormalizedPath()
        var aliases = [String: String]()
        var usedAliases = Set<String>()

        for path in normalizedPaths {
            let preferredAlias = existing[path]
            let projectName = projectsByNormalizedPath[path]?.name ?? pathLastComponent(path)
            let alias = uniqueAlias(
                preferredAlias ?? projectName,
                usedAliases: &usedAliases
            )
            aliases[path] = alias
        }

        return aliases
    }

    func aliases(
        for definition: WorkspaceAlignmentGroupDefinition,
        projectsByNormalizedPath explicitProjectsByNormalizedPath: [String: Project]? = nil
    ) -> [String: String] {
        aliases(
            for: definition.effectiveMembers.map(\.projectPath),
            existing: definition.memberAliases,
            projectsByNormalizedPath: explicitProjectsByNormalizedPath
        )
    }

    func memberDefinition(
        for projectPath: String,
        in definition: WorkspaceAlignmentGroupDefinition
    ) -> WorkspaceAlignmentMemberDefinition? {
        definition.effectiveMembers.first(where: {
            normalizePath($0.projectPath) == normalizePath(projectPath)
        })
    }

    func normalizedMembers(
        _ members: [WorkspaceAlignmentMemberDefinition]
    ) -> [WorkspaceAlignmentMemberDefinition] {
        var seen = Set<String>()
        return members
            .map { $0.sanitized() }
            .filter { !$0.projectPath.isEmpty }
            .filter { seen.insert(normalizePath($0.projectPath)).inserted }
    }

    private func projectName(for path: String) -> String {
        projectsByNormalizedPath()[normalizePath(path)]?.name ?? pathLastComponent(path)
    }

    private func uniqueAlias(
        _ preferredAlias: String,
        usedAliases: inout Set<String>
    ) -> String {
        let sanitizedBase = sanitizeAlias(preferredAlias)
        var candidate = sanitizedBase
        var suffix = 2
        while usedAliases.contains(candidate.lowercased()) {
            candidate = "\(sanitizedBase)-\(suffix)"
            suffix += 1
        }
        usedAliases.insert(candidate.lowercased())
        return candidate
    }

    private func sanitizeAlias(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let replaced = trimmed
            .replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        return replaced.isEmpty ? "member" : replaced
    }
}
