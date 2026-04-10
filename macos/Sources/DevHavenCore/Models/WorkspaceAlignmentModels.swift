import Foundation

public enum WorkspaceAlignmentBaseBranchMode: String, Codable, Equatable, Sendable {
    case autoDetect = "auto_detect"
    case specified
}

public struct WorkspaceAlignmentMemberDefinition: Codable, Equatable, Sendable, Identifiable {
    public var projectPath: String
    public var targetBranch: String
    public var baseBranchMode: WorkspaceAlignmentBaseBranchMode
    public var specifiedBaseBranch: String?

    public init(
        projectPath: String,
        targetBranch: String,
        baseBranchMode: WorkspaceAlignmentBaseBranchMode = .specified,
        specifiedBaseBranch: String? = nil
    ) {
        self.projectPath = projectPath
        self.targetBranch = targetBranch
        self.baseBranchMode = baseBranchMode
        self.specifiedBaseBranch = specifiedBaseBranch
    }

    public var id: String { projectPath }

    public func sanitized() -> WorkspaceAlignmentMemberDefinition {
        var copy = self
        copy.projectPath = normalizeWorkspaceAlignmentPath(copy.projectPath)
        copy.targetBranch = copy.targetBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let specified = copy.specifiedBaseBranch?.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.specifiedBaseBranch = (specified?.isEmpty == false) ? specified : nil
        return copy
    }
}

public struct WorkspaceAlignmentGroupDefinition: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var targetBranch: String
    public var baseBranchMode: WorkspaceAlignmentBaseBranchMode
    public var specifiedBaseBranch: String?
    public var projectPaths: [String]
    public var members: [WorkspaceAlignmentMemberDefinition]
    public var rootDirectoryName: String?
    public var memberAliases: [String: String]
    public var isSidebarExpanded: Bool
    public var createdAt: SwiftDate
    public var updatedAt: SwiftDate

    public init(
        id: String = UUID().uuidString,
        name: String,
        targetBranch: String,
        baseBranchMode: WorkspaceAlignmentBaseBranchMode = .specified,
        specifiedBaseBranch: String? = nil,
        projectPaths: [String] = [],
        members: [WorkspaceAlignmentMemberDefinition] = [],
        rootDirectoryName: String? = nil,
        memberAliases: [String: String] = [:],
        isSidebarExpanded: Bool = true,
        createdAt: SwiftDate = Date().timeIntervalSince1970,
        updatedAt: SwiftDate = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.name = name
        self.targetBranch = targetBranch
        self.baseBranchMode = baseBranchMode
        self.specifiedBaseBranch = specifiedBaseBranch
        self.projectPaths = projectPaths
        self.members = members
        self.rootDirectoryName = rootDirectoryName
        self.memberAliases = memberAliases
        self.isSidebarExpanded = isSidebarExpanded
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case targetBranch
        case baseBranchMode
        case specifiedBaseBranch
        case projectPaths
        case members
        case rootDirectoryName
        case memberAliases
        case isSidebarExpanded
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.name = try container.decode(String.self, forKey: .name)
        self.targetBranch = try container.decode(String.self, forKey: .targetBranch)
        self.baseBranchMode = try container.decodeIfPresent(WorkspaceAlignmentBaseBranchMode.self, forKey: .baseBranchMode) ?? .specified
        self.specifiedBaseBranch = try container.decodeIfPresent(String.self, forKey: .specifiedBaseBranch)
        self.projectPaths = try container.decodeIfPresent([String].self, forKey: .projectPaths) ?? []
        self.members = try container.decodeIfPresent([WorkspaceAlignmentMemberDefinition].self, forKey: .members) ?? []
        self.rootDirectoryName = try container.decodeIfPresent(String.self, forKey: .rootDirectoryName)
        self.memberAliases = try container.decodeIfPresent([String: String].self, forKey: .memberAliases) ?? [:]
        self.isSidebarExpanded = try container.decodeIfPresent(Bool.self, forKey: .isSidebarExpanded) ?? true
        self.createdAt = try container.decodeIfPresent(SwiftDate.self, forKey: .createdAt) ?? Date().timeIntervalSince1970
        self.updatedAt = try container.decodeIfPresent(SwiftDate.self, forKey: .updatedAt) ?? self.createdAt
    }

    public func sanitized() -> WorkspaceAlignmentGroupDefinition {
        var copy = self
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.targetBranch = copy.targetBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let specified = copy.specifiedBaseBranch?.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.specifiedBaseBranch = (specified?.isEmpty == false) ? specified : nil
        let normalizedMembers: [WorkspaceAlignmentMemberDefinition]
        if copy.members.isEmpty {
            normalizedMembers = normalizeWorkspaceAlignmentPathList(copy.projectPaths).map { path in
                WorkspaceAlignmentMemberDefinition(
                    projectPath: path,
                    targetBranch: copy.targetBranch,
                    baseBranchMode: copy.baseBranchMode,
                    specifiedBaseBranch: copy.specifiedBaseBranch
                )
            }
        } else {
            normalizedMembers = normalizeWorkspaceAlignmentMemberList(copy.members)
        }
        copy.members = normalizedMembers
        copy.projectPaths = normalizedMembers.map(\.projectPath)
        if copy.targetBranch.isEmpty, let firstTargetBranch = normalizedMembers.first?.targetBranch {
            copy.targetBranch = firstTargetBranch
        }
        if normalizedMembers.count == 1, let onlyMember = normalizedMembers.first {
            copy.baseBranchMode = onlyMember.baseBranchMode
            copy.specifiedBaseBranch = onlyMember.specifiedBaseBranch
        }
        let trimmedRootDirectoryName = copy.rootDirectoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedRootDirectoryName = trimmedRootDirectoryName.isEmpty ? nil : trimmedRootDirectoryName
        copy.rootDirectoryName = normalizedRootDirectoryName
        copy.memberAliases = normalizeWorkspaceAlignmentAliasMap(
            copy.memberAliases,
            allowedPaths: Set(copy.projectPaths)
        )
        return copy
    }

    public var effectiveMembers: [WorkspaceAlignmentMemberDefinition] {
        sanitized().members
    }
}

public enum WorkspaceAlignmentMemberStatus: Equatable, Sendable {
    case aligned
    case currentBranch(String)
    case branchMissing
    case worktreeMissing
    case checking
    case applying
    case applyFailed(String?)
    case checkFailed(String?)

    public var displayText: String {
        switch self {
        case .aligned:
            "已对齐"
        case let .currentBranch(branch):
            "当前 \(branch)"
        case .branchMissing:
            "未创建分支"
        case .worktreeMissing:
            "缺少 worktree"
        case .checking:
            "检查中…"
        case .applying:
            "创建中…"
        case .applyFailed:
            "创建失败"
        case .checkFailed:
            "检查失败"
        }
    }

    public func detailText(targetBranch: String) -> String? {
        switch self {
        case .aligned:
            "已对齐到 \(targetBranch)"
        case let .currentBranch(branch):
            "当前分支为 \(branch)，目标分支为 \(targetBranch)"
        case .branchMissing:
            "目标分支 \(targetBranch) 尚不存在"
        case .worktreeMissing:
            "目标分支已存在，但未找到可用 worktree"
        case .checking:
            "正在检查当前 branch / worktree 状态"
        case .applying:
            "正在应用工作区规则"
        case let .applyFailed(message), let .checkFailed(message):
            message?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    fileprivate var summaryBucket: WorkspaceAlignmentSummaryBucket {
        switch self {
        case .aligned:
            .aligned
        case .checking, .applying:
            .processing
        case .currentBranch, .branchMissing, .worktreeMissing:
            .drifted
        case .applyFailed, .checkFailed:
            .failed
        }
    }
}

public enum WorkspaceAlignmentOpenTarget: Equatable, Sendable {
    case project(projectPath: String)
    case worktree(rootProjectPath: String, worktreePath: String)

    public var path: String {
        switch self {
        case let .project(projectPath):
            projectPath
        case let .worktree(_, worktreePath):
            worktreePath
        }
    }
}

public struct WorkspaceAlignmentMemberProjection: Equatable, Sendable, Identifiable {
    public var groupID: String
    public var projectPath: String
    public var alias: String
    public var projectName: String
    public var targetBranch: String
    public var branchLabel: String
    public var status: WorkspaceAlignmentMemberStatus
    public var openTarget: WorkspaceAlignmentOpenTarget
    public var isActive: Bool

    public init(
        groupID: String,
        projectPath: String,
        alias: String? = nil,
        projectName: String,
        targetBranch: String? = nil,
        branchLabel: String? = nil,
        status: WorkspaceAlignmentMemberStatus,
        openTarget: WorkspaceAlignmentOpenTarget? = nil,
        isActive: Bool = false
    ) {
        self.groupID = groupID
        self.projectPath = projectPath
        self.alias = alias ?? URL(fileURLWithPath: projectPath).lastPathComponent
        self.projectName = projectName
        self.targetBranch = targetBranch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.branchLabel = branchLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.status = status
        self.openTarget = openTarget ?? .project(projectPath: projectPath)
        self.isActive = isActive
    }

    public var id: String { "\(groupID)|\(projectPath)" }
}

public struct WorkspaceAlignmentGroupProjection: Equatable, Sendable, Identifiable {
    public var definition: WorkspaceAlignmentGroupDefinition
    public var members: [WorkspaceAlignmentMemberProjection]
    public var isActive: Bool

    public init(
        definition: WorkspaceAlignmentGroupDefinition,
        members: [WorkspaceAlignmentMemberProjection],
        isActive: Bool = false
    ) {
        self.definition = definition
        self.members = members
        self.isActive = isActive
    }

    public var id: String { definition.id }

    public var summaryMetrics: WorkspaceAlignmentSummaryMetrics {
        members.reduce(into: WorkspaceAlignmentSummaryMetrics()) { partialResult, member in
            partialResult.record(member.status.summaryBucket)
        }
    }

    public var branchMetadataText: String {
        if members.isEmpty {
            return "\(definition.targetBranch) · 暂无项目"
        }
        let branchLabels = members
            .map(\.branchLabel)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !branchLabels.isEmpty else {
            return "\(definition.targetBranch) · \(members.count) 项目"
        }
        let counts = Dictionary(grouping: branchLabels, by: { $0 }).mapValues(\.count)
        let ordered = counts.keys.sorted { lhs, rhs in
            if counts[lhs] == counts[rhs] {
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            return (counts[lhs] ?? 0) > (counts[rhs] ?? 0)
        }
        let segments = ordered.prefix(2).map { branch in
            "\(branch) × \(counts[branch] ?? 0)"
        }
        if counts.count > 2 {
            return segments.joined(separator: " · ") + " · \(members.count) 项目"
        }
        return segments.joined(separator: " · ")
    }

    public var summaryText: String {
        guard !members.isEmpty else {
            return "右键或点击加号可添加项目"
        }

        let buckets = summaryMetrics

        if buckets.failed == 0, buckets.processing == 0, buckets.drifted == 0 {
            return "全部已对齐"
        }

        let issueCount = buckets.failed + buckets.processing + buckets.drifted
        if [buckets.failed > 0, buckets.processing > 0, buckets.drifted > 0].filter({ $0 }).count > 2 {
            return "\(issueCount) 异常"
        }

        var segments: [String] = []
        if buckets.aligned > 0, issueCount <= 2 {
            segments.append("\(buckets.aligned) 已对齐")
        }
        if buckets.failed > 0 {
            segments.append("\(buckets.failed) 失败")
        }
        if buckets.processing > 0 {
            segments.append("\(buckets.processing) 处理中")
        }
        if buckets.drifted > 0 {
            segments.append("\(buckets.drifted) 偏离")
        }
        return segments.joined(separator: " · ")
    }
}

public struct WorkspaceAlignmentSummaryMetrics: Equatable, Sendable {
    public var aligned: Int
    public var processing: Int
    public var drifted: Int
    public var failed: Int

    public init(
        aligned: Int = 0,
        processing: Int = 0,
        drifted: Int = 0,
        failed: Int = 0
    ) {
        self.aligned = aligned
        self.processing = processing
        self.drifted = drifted
        self.failed = failed
    }

    public var issueCount: Int {
        failed + processing + drifted
    }

    public var totalCount: Int {
        aligned + processing + drifted + failed
    }

    public var isFullyAligned: Bool {
        totalCount > 0 && issueCount == 0
    }
}

private enum WorkspaceAlignmentSummaryBucket {
    case aligned
    case processing
    case drifted
    case failed
}

private extension WorkspaceAlignmentSummaryMetrics {
    mutating func record(_ bucket: WorkspaceAlignmentSummaryBucket) {
        switch bucket {
        case .aligned:
            aligned += 1
        case .processing:
            processing += 1
        case .drifted:
            drifted += 1
        case .failed:
            failed += 1
        }
    }
}

private func normalizeWorkspaceAlignmentPath(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return ""
    }
    return URL(fileURLWithPath: trimmed).standardizedFileURL.path
}

private func normalizeWorkspaceAlignmentPathList(_ paths: [String]) -> [String] {
    var seen = Set<String>()
    return paths
        .map(normalizeWorkspaceAlignmentPath)
        .filter { !$0.isEmpty }
        .filter { seen.insert($0).inserted }
}

private func normalizeWorkspaceAlignmentMemberList(
    _ members: [WorkspaceAlignmentMemberDefinition]
) -> [WorkspaceAlignmentMemberDefinition] {
    var seen = Set<String>()
    return members
        .map { $0.sanitized() }
        .filter { !$0.projectPath.isEmpty }
        .filter { seen.insert($0.projectPath).inserted }
}

private func normalizeWorkspaceAlignmentAliasMap(
    _ aliases: [String: String],
    allowedPaths: Set<String>
) -> [String: String] {
    var normalized = [String: String]()
    for (rawPath, rawAlias) in aliases {
        let path = normalizeWorkspaceAlignmentPath(rawPath)
        guard allowedPaths.contains(path) else {
            continue
        }
        let alias = rawAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty else {
            continue
        }
        normalized[path] = alias
    }
    return normalized
}
