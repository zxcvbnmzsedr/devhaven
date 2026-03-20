import Foundation

public struct NativeGitBranch: Equatable, Sendable, Identifiable {
    public var name: String
    public var isMain: Bool

    public init(name: String, isMain: Bool) {
        self.name = name
        self.isMain = isMain
    }

    public var id: String { name }
}

public struct NativeGitWorktree: Equatable, Sendable, Identifiable {
    public var path: String
    public var branch: String

    public init(path: String, branch: String) {
        self.path = path
        self.branch = branch
    }

    public var id: String { path }
}

public enum NativeWorktreeInitStep: String, Codable, Equatable, Sendable {
    case pending
    case checkingBranch = "checking_branch"
    case creatingWorktree = "creating_worktree"
    case preparingEnvironment = "preparing_environment"
    case syncing
    case ready
    case failed
}

public struct NativeWorktreeProgress: Equatable, Sendable {
    public var worktreePath: String
    public var branch: String
    public var baseBranch: String?
    public var step: NativeWorktreeInitStep
    public var message: String
    public var error: String?

    public init(
        worktreePath: String,
        branch: String,
        baseBranch: String? = nil,
        step: NativeWorktreeInitStep,
        message: String,
        error: String? = nil
    ) {
        self.worktreePath = worktreePath
        self.branch = branch
        self.baseBranch = baseBranch
        self.step = step
        self.message = message
        self.error = error
    }
}

public struct NativeWorktreeCreateRequest: Equatable, Sendable {
    public var sourceProjectPath: String
    public var branch: String
    public var createBranch: Bool
    public var baseBranch: String?
    public var targetPath: String?

    public init(
        sourceProjectPath: String,
        branch: String,
        createBranch: Bool,
        baseBranch: String? = nil,
        targetPath: String? = nil
    ) {
        self.sourceProjectPath = sourceProjectPath
        self.branch = branch
        self.createBranch = createBranch
        self.baseBranch = baseBranch
        self.targetPath = targetPath
    }
}

public struct NativeWorktreeCreateResult: Equatable, Sendable {
    public var worktreePath: String
    public var branch: String
    public var baseBranch: String?
    public var warning: String?

    public init(
        worktreePath: String,
        branch: String,
        baseBranch: String? = nil,
        warning: String? = nil
    ) {
        self.worktreePath = worktreePath
        self.branch = branch
        self.baseBranch = baseBranch
        self.warning = warning
    }
}

public struct NativeWorktreeRemoveRequest: Equatable, Sendable {
    public var sourceProjectPath: String
    public var worktreePath: String
    public var branch: String?
    public var shouldDeleteBranch: Bool

    public init(
        sourceProjectPath: String,
        worktreePath: String,
        branch: String? = nil,
        shouldDeleteBranch: Bool
    ) {
        self.sourceProjectPath = sourceProjectPath
        self.worktreePath = worktreePath
        self.branch = branch
        self.shouldDeleteBranch = shouldDeleteBranch
    }
}

public struct NativeWorktreeRemoveResult: Equatable, Sendable {
    public var warning: String?

    public init(warning: String? = nil) {
        self.warning = warning
    }
}

public struct WorkspaceSidebarWorktreeItem: Equatable, Sendable, Identifiable {
    public var rootProjectPath: String
    public var worktree: ProjectWorktree
    public var isOpen: Bool
    public var isActive: Bool

    public init(rootProjectPath: String, worktree: ProjectWorktree, isOpen: Bool, isActive: Bool) {
        self.rootProjectPath = rootProjectPath
        self.worktree = worktree
        self.isOpen = isOpen
        self.isActive = isActive
    }

    public var id: String { worktree.id }
    public var path: String { worktree.path }
    public var name: String { worktree.name }
    public var branch: String { worktree.branch }
    public var status: String? { worktree.status }
    public var initStep: String? { worktree.initStep }
    public var initError: String? { worktree.initError }
}

public struct WorkspaceSidebarProjectGroup: Equatable, Sendable, Identifiable {
    public var rootProject: Project
    public var worktrees: [WorkspaceSidebarWorktreeItem]
    public var isActive: Bool

    public init(rootProject: Project, worktrees: [WorkspaceSidebarWorktreeItem], isActive: Bool) {
        self.rootProject = rootProject
        self.worktrees = worktrees
        self.isActive = isActive
    }

    public var id: String { rootProject.id }
}

public struct WorktreeInteractionState: Equatable, Sendable {
    public var rootProjectPath: String
    public var branch: String
    public var baseBranch: String?
    public var worktreePath: String
    public var step: NativeWorktreeInitStep
    public var message: String

    public init(
        rootProjectPath: String,
        branch: String,
        baseBranch: String? = nil,
        worktreePath: String,
        step: NativeWorktreeInitStep,
        message: String
    ) {
        self.rootProjectPath = rootProjectPath
        self.branch = branch
        self.baseBranch = baseBranch
        self.worktreePath = worktreePath
        self.step = step
        self.message = message
    }
}

public enum NativeWorktreeError: LocalizedError, Equatable, Sendable {
    case invalidProject(String)
    case invalidBranch(String)
    case invalidBaseBranch(String)
    case invalidPath(String)
    case invalidRepository(String)
    case operationInProgress(String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidProject(message),
             let .invalidBranch(message),
             let .invalidBaseBranch(message),
             let .invalidPath(message),
             let .invalidRepository(message),
             let .operationInProgress(message),
             let .commandFailed(message):
            return message
        }
    }
}

public protocol NativeWorktreeServicing: Sendable {
    func managedWorktreePath(for sourceProjectPath: String, branch: String) throws -> String
    func listBranches(at projectPath: String) throws -> [NativeGitBranch]
    func listWorktrees(at projectPath: String) throws -> [NativeGitWorktree]
    func createWorktree(
        _ request: NativeWorktreeCreateRequest,
        progress: @escaping @Sendable (NativeWorktreeProgress) -> Void
    ) throws -> NativeWorktreeCreateResult
    func removeWorktree(_ request: NativeWorktreeRemoveRequest) throws -> NativeWorktreeRemoveResult
}
