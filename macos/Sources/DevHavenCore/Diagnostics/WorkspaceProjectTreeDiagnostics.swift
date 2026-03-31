import Foundation
import OSLog

private let workspaceProjectTreeLogger = Logger(
    subsystem: "DevHavenNative",
    category: "WorkspaceProjectTree"
)

enum WorkspaceProjectTreeDiagnosticEvent: Equatable, Sendable {
    case projectionBuilt(
        projectPath: String,
        revision: Int,
        durationMs: Int,
        rootCount: Int,
        aliasCount: Int
    )
    case directoryLoadStarted(
        projectPath: String,
        directoryPath: String,
        revision: Int
    )
    case directoryLoadFinished(
        projectPath: String,
        directoryPath: String,
        revision: Int,
        durationMs: Int,
        loadedDirectoryCount: Int,
        directChildCount: Int,
        status: String,
        errorDescription: String?
    )
    case directoryCollapsed(
        projectPath: String,
        directoryPath: String,
        revision: Int,
        expandedCount: Int
    )
    case treeRebuilt(
        projectPath: String,
        revision: Int,
        durationMs: Int,
        rootCount: Int,
        expandedCount: Int
    )
}

@MainActor
public final class WorkspaceProjectTreeDiagnostics {
    public static let shared = WorkspaceProjectTreeDiagnostics()

    private let logSink: (String) -> Void
    private let eventSink: (WorkspaceProjectTreeDiagnosticEvent) -> Void

    init(
        logSink: @escaping (String) -> Void = { message in
            workspaceProjectTreeLogger.notice("\(message, privacy: .public)")
        },
        eventSink: @escaping (WorkspaceProjectTreeDiagnosticEvent) -> Void = { _ in }
    ) {
        self.logSink = logSink
        self.eventSink = eventSink
    }

    public func recordProjectionBuilt(
        projectPath: String,
        revision: Int,
        durationMs: Int,
        rootCount: Int,
        aliasCount: Int
    ) {
        emit(
            .projectionBuilt(
                projectPath: projectPath,
                revision: revision,
                durationMs: durationMs,
                rootCount: rootCount,
                aliasCount: aliasCount
            ),
            message: """
            [project-tree] projection-built project=\(projectPath) \
            revision=\(revision) \
            durationMs=\(durationMs) \
            roots=\(rootCount) \
            aliases=\(aliasCount)
            """
        )
    }

    public func recordDirectoryLoadStarted(
        projectPath: String,
        directoryPath: String,
        revision: Int
    ) {
        emit(
            .directoryLoadStarted(
                projectPath: projectPath,
                directoryPath: directoryPath,
                revision: revision
            ),
            message: """
            [project-tree] expand-start project=\(projectPath) \
            directory=\(directoryPath) \
            revision=\(revision)
            """
        )
    }

    public func recordDirectoryLoadFinished(
        projectPath: String,
        directoryPath: String,
        revision: Int,
        durationMs: Int,
        loadedDirectoryCount: Int,
        directChildCount: Int,
        status: String,
        errorDescription: String?
    ) {
        let errorSuffix = errorDescription.map { " error=\($0)" } ?? ""
        emit(
            .directoryLoadFinished(
                projectPath: projectPath,
                directoryPath: directoryPath,
                revision: revision,
                durationMs: durationMs,
                loadedDirectoryCount: loadedDirectoryCount,
                directChildCount: directChildCount,
                status: status,
                errorDescription: errorDescription
            ),
            message: """
            [project-tree] expand-finish project=\(projectPath) \
            directory=\(directoryPath) \
            revision=\(revision) \
            durationMs=\(durationMs) \
            loadedDirectories=\(loadedDirectoryCount) \
            directChildren=\(directChildCount) \
            status=\(status)\(errorSuffix)
            """
        )
    }

    public func recordDirectoryCollapsed(
        projectPath: String,
        directoryPath: String,
        revision: Int,
        expandedCount: Int
    ) {
        emit(
            .directoryCollapsed(
                projectPath: projectPath,
                directoryPath: directoryPath,
                revision: revision,
                expandedCount: expandedCount
            ),
            message: """
            [project-tree] collapse project=\(projectPath) \
            directory=\(directoryPath) \
            revision=\(revision) \
            expandedCount=\(expandedCount)
            """
        )
    }

    public func recordTreeRebuilt(
        projectPath: String,
        revision: Int,
        durationMs: Int,
        rootCount: Int,
        expandedCount: Int
    ) {
        emit(
            .treeRebuilt(
                projectPath: projectPath,
                revision: revision,
                durationMs: durationMs,
                rootCount: rootCount,
                expandedCount: expandedCount
            ),
            message: """
            [project-tree] rebuild project=\(projectPath) \
            revision=\(revision) \
            durationMs=\(durationMs) \
            roots=\(rootCount) \
            expandedCount=\(expandedCount)
            """
        )
    }

    private func emit(_ event: WorkspaceProjectTreeDiagnosticEvent, message: String) {
        eventSink(event)
        logSink(message)
    }
}
