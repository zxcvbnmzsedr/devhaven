import Foundation

public enum WorkspaceAlignmentBaseBranchMode: String, Codable, Equatable, Sendable {
    case autoDetect = "auto_detect"
    case specified
}

public struct WorkspaceAlignmentGroupDefinition: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var targetBranch: String
    public var baseBranchMode: WorkspaceAlignmentBaseBranchMode
    public var specifiedBaseBranch: String?
    public var projectPaths: [String]
    public var createdAt: SwiftDate
    public var updatedAt: SwiftDate

    public init(
        id: String = UUID().uuidString,
        name: String,
        targetBranch: String,
        baseBranchMode: WorkspaceAlignmentBaseBranchMode = .autoDetect,
        specifiedBaseBranch: String? = nil,
        projectPaths: [String] = [],
        createdAt: SwiftDate = Date().timeIntervalSince1970,
        updatedAt: SwiftDate = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.name = name
        self.targetBranch = targetBranch
        self.baseBranchMode = baseBranchMode
        self.specifiedBaseBranch = specifiedBaseBranch
        self.projectPaths = projectPaths
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func sanitized() -> WorkspaceAlignmentGroupDefinition {
        var copy = self
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.targetBranch = copy.targetBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let specified = copy.specifiedBaseBranch?.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.specifiedBaseBranch = (specified?.isEmpty == false) ? specified : nil
        copy.projectPaths = normalizeWorkspaceAlignmentPathList(copy.projectPaths)
        return copy
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
    public var projectName: String
    public var status: WorkspaceAlignmentMemberStatus
    public var openTarget: WorkspaceAlignmentOpenTarget

    public init(
        groupID: String,
        projectPath: String,
        projectName: String,
        status: WorkspaceAlignmentMemberStatus,
        openTarget: WorkspaceAlignmentOpenTarget? = nil
    ) {
        self.groupID = groupID
        self.projectPath = projectPath
        self.projectName = projectName
        self.status = status
        self.openTarget = openTarget ?? .project(projectPath: projectPath)
    }

    public var id: String { "\(groupID)|\(projectPath)" }
}

public struct WorkspaceAlignmentGroupProjection: Equatable, Sendable, Identifiable {
    public var definition: WorkspaceAlignmentGroupDefinition
    public var members: [WorkspaceAlignmentMemberProjection]

    public init(
        definition: WorkspaceAlignmentGroupDefinition,
        members: [WorkspaceAlignmentMemberProjection]
    ) {
        self.definition = definition
        self.members = members
    }

    public var id: String { definition.id }

    public var branchMetadataText: String {
        if members.isEmpty {
            return "\(definition.targetBranch) · 暂无项目"
        }
        return "\(definition.targetBranch) · \(members.count) 项目"
    }

    public var summaryText: String {
        guard !members.isEmpty else {
            return "右键或点击加号可添加项目"
        }

        let buckets = members.reduce(into: WorkspaceAlignmentSummaryCounts()) { partialResult, member in
            partialResult.record(member.status.summaryBucket)
        }

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

private enum WorkspaceAlignmentSummaryBucket {
    case aligned
    case processing
    case drifted
    case failed
}

private struct WorkspaceAlignmentSummaryCounts {
    var aligned = 0
    var processing = 0
    var drifted = 0
    var failed = 0

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
