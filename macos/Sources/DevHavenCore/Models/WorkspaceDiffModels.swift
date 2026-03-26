import Foundation

public enum WorkspaceDiffViewerMode: String, Equatable, Sendable {
    case sideBySide
    case unified
}

public enum WorkspaceDiffSource: Equatable, Sendable {
    case gitLogCommitFile(repositoryPath: String, commitHash: String, filePath: String)
    case workingTreeChange(repositoryPath: String, executionPath: String, filePath: String)

    public var identity: String {
        switch self {
        case let .gitLogCommitFile(repositoryPath, commitHash, filePath):
            return "git-log|\(repositoryPath)|\(commitHash)|\(filePath)"
        case let .workingTreeChange(_, executionPath, filePath):
            return "working-tree|\(executionPath)|\(filePath)"
        }
    }
}

public struct WorkspaceDiffOpenRequest: Equatable, Sendable {
    public var projectPath: String
    public var source: WorkspaceDiffSource
    public var preferredTitle: String
    public var preferredViewerMode: WorkspaceDiffViewerMode

    public init(
        projectPath: String,
        source: WorkspaceDiffSource,
        preferredTitle: String,
        preferredViewerMode: WorkspaceDiffViewerMode = .sideBySide
    ) {
        self.projectPath = projectPath
        self.source = source
        self.preferredTitle = preferredTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.preferredViewerMode = preferredViewerMode
    }

    public var identity: String {
        source.identity
    }
}

public struct WorkspaceDiffTabState: Identifiable, Equatable, Sendable {
    public var id: String
    public var identity: String
    public var title: String
    public var source: WorkspaceDiffSource
    public var viewerMode: WorkspaceDiffViewerMode

    public init(
        id: String,
        identity: String,
        title: String,
        source: WorkspaceDiffSource,
        viewerMode: WorkspaceDiffViewerMode
    ) {
        self.id = id
        self.identity = identity
        self.title = title
        self.source = source
        self.viewerMode = viewerMode
    }
}

public enum WorkspacePresentedTabSelection: Equatable, Sendable {
    case terminal(String)
    case diff(String)
}
