import Foundation
import OSLog

private let projectImportLogger = Logger(
    subsystem: "DevHavenNative",
    category: "ProjectImport"
)

public enum ProjectImportAction: String, Equatable, Sendable {
    case addDirectory = "add-directory"
    case addProjects = "add-projects"
}

enum ProjectImportDiagnosticEvent: Equatable, Sendable {
    case importerCallback(action: String, urlCount: Int)
    case securityScope(action: String, requestedCount: Int, grantedCount: Int)
    case importAttempt(action: String, pathCount: Int, paths: [String])
    case validation(path: String, accepted: Bool, reason: String?)
    case directoryPersisted(path: String, totalCount: Int)
    case directProjectsPersisted(requestedCount: Int, acceptedCount: Int, rejectedCount: Int, totalCount: Int)
    case selectionApplied(action: String, filter: String)
    case failure(action: String, errorDescription: String)
}

@MainActor
public final class ProjectImportDiagnostics {
    public static let shared = ProjectImportDiagnostics()

    private let logSink: (String) -> Void
    private let eventSink: (ProjectImportDiagnosticEvent) -> Void

    init(
        logSink: @escaping (String) -> Void = { message in
            projectImportLogger.notice("\(message, privacy: .public)")
        },
        eventSink: @escaping (ProjectImportDiagnosticEvent) -> Void = { _ in }
    ) {
        self.logSink = logSink
        self.eventSink = eventSink
    }

    public func recordImporterCallback(action: ProjectImportAction?, urlCount: Int) {
        let actionValue = action?.rawValue ?? "unknown"
        emit(
            .importerCallback(action: actionValue, urlCount: urlCount),
            message: "[project-import] importer-callback action=\(actionValue) urlCount=\(urlCount)"
        )
    }

    public func recordSecurityScope(action: ProjectImportAction?, requestedCount: Int, grantedCount: Int) {
        let actionValue = action?.rawValue ?? "unknown"
        emit(
            .securityScope(action: actionValue, requestedCount: requestedCount, grantedCount: grantedCount),
            message: "[project-import] security-scope action=\(actionValue) requested=\(requestedCount) granted=\(grantedCount)"
        )
    }

    public func recordImportAttempt(action: ProjectImportAction, paths: [String]) {
        emit(
            .importAttempt(action: action.rawValue, pathCount: paths.count, paths: paths),
            message: "[project-import] import-attempt action=\(action.rawValue) pathCount=\(paths.count) paths=\(paths.joined(separator: ","))"
        )
    }

    public func recordValidationAccepted(path: String) {
        emit(
            .validation(path: path, accepted: true, reason: nil),
            message: "[project-import] validate path=\(path) result=accepted"
        )
    }

    public func recordValidationRejected(path: String, reason: String) {
        emit(
            .validation(path: path, accepted: false, reason: reason),
            message: "[project-import] validate path=\(path) result=rejected reason=\(reason)"
        )
    }

    public func recordDirectoryPersisted(path: String, totalCount: Int) {
        emit(
            .directoryPersisted(path: path, totalCount: totalCount),
            message: "[project-import] persist-directory path=\(path) totalDirectories=\(totalCount)"
        )
    }

    public func recordDirectProjectsPersisted(
        requestedCount: Int,
        acceptedCount: Int,
        rejectedCount: Int,
        totalCount: Int
    ) {
        emit(
            .directProjectsPersisted(
                requestedCount: requestedCount,
                acceptedCount: acceptedCount,
                rejectedCount: rejectedCount,
                totalCount: totalCount
            ),
            message: """
            [project-import] persist-direct-projects requested=\(requestedCount) \
            accepted=\(acceptedCount) \
            rejected=\(rejectedCount) \
            totalDirectProjects=\(totalCount)
            """
        )
    }

    public func recordSelectionApplied(action: ProjectImportAction, filter: String) {
        emit(
            .selectionApplied(action: action.rawValue, filter: filter),
            message: "[project-import] selection-applied action=\(action.rawValue) filter=\(filter)"
        )
    }

    public func recordFailure(action: ProjectImportAction?, errorDescription: String) {
        let actionValue = action?.rawValue ?? "unknown"
        emit(
            .failure(action: actionValue, errorDescription: errorDescription),
            message: "[project-import] failure action=\(actionValue) error=\(errorDescription)"
        )
    }

    private func emit(_ event: ProjectImportDiagnosticEvent, message: String) {
        eventSink(event)
        logSink(message)
    }
}
