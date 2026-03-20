import Foundation
import OSLog

private let workspaceLaunchLogger = Logger(
    subsystem: "DevHavenNative",
    category: "WorkspaceLaunch"
)

public enum WorkspaceLaunchSurfaceStatus: String, Equatable, Sendable {
    case success
    case failed
    case reused
}

enum WorkspaceLaunchDiagnosticEvent: Equatable, Sendable {
    case entryRequested(
        workspaceId: String,
        projectPath: String,
        openSessionCount: Int,
        tabCount: Int,
        paneCount: Int
    )
    case shellMounted(
        activeProjectPath: String?,
        openSessionCount: Int
    )
    case hostMounted(
        workspaceId: String,
        projectPath: String,
        isActive: Bool,
        tabCount: Int,
        paneCount: Int
    )
    case surfaceCreationStarted(
        workspaceId: String,
        projectPath: String,
        tabId: String,
        paneId: String,
        surfaceId: String
    )
    case surfaceCreationFinished(
        workspaceId: String,
        projectPath: String,
        tabId: String,
        paneId: String,
        surfaceId: String,
        durationMs: Int,
        status: WorkspaceLaunchSurfaceStatus,
        errorDescription: String?
    )
    case surfaceReused(
        workspaceId: String,
        projectPath: String,
        tabId: String,
        paneId: String,
        surfaceId: String
    )
}

@MainActor
public final class WorkspaceLaunchDiagnostics {
    public static let shared = WorkspaceLaunchDiagnostics()

    private let now: () -> TimeInterval
    private let logSink: (String) -> Void
    private let eventSink: (WorkspaceLaunchDiagnosticEvent) -> Void
    private var entryStartTimeByWorkspaceId = [String: TimeInterval]()
    private var surfaceStartTimeBySurfaceId = [String: TimeInterval]()

    init(
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        logSink: @escaping (String) -> Void = { message in
            workspaceLaunchLogger.notice("\(message, privacy: .public)")
        },
        eventSink: @escaping (WorkspaceLaunchDiagnosticEvent) -> Void = { _ in }
    ) {
        self.now = now
        self.logSink = logSink
        self.eventSink = eventSink
    }

    public func recordEntryRequested(workspace: WorkspaceSessionState, openSessionCount: Int) {
        entryStartTimeByWorkspaceId[workspace.workspaceId] = now()
        let event = WorkspaceLaunchDiagnosticEvent.entryRequested(
            workspaceId: workspace.workspaceId,
            projectPath: workspace.projectPath,
            openSessionCount: openSessionCount,
            tabCount: workspace.tabs.count,
            paneCount: workspace.totalPaneCount
        )
        emit(event, message: """
        [workspace-launch] entry workspace=\(workspace.workspaceId) \
        project=\(workspace.projectPath) \
        openSessions=\(openSessionCount) \
        tabs=\(workspace.tabs.count) \
        panes=\(workspace.totalPaneCount)
        """)
    }

    public func recordShellMounted(activeProjectPath: String?, openSessionCount: Int) {
        let event = WorkspaceLaunchDiagnosticEvent.shellMounted(
            activeProjectPath: activeProjectPath,
            openSessionCount: openSessionCount
        )
        emit(event, message: """
        [workspace-launch] shell-mounted activeProject=\(activeProjectPath ?? "nil") \
        openSessions=\(openSessionCount)
        """)
    }

    public func recordHostMounted(workspace: WorkspaceSessionState, isActive: Bool) {
        let event = WorkspaceLaunchDiagnosticEvent.hostMounted(
            workspaceId: workspace.workspaceId,
            projectPath: workspace.projectPath,
            isActive: isActive,
            tabCount: workspace.tabs.count,
            paneCount: workspace.totalPaneCount
        )
        let elapsed = elapsedMs(sinceWorkspaceEntry: workspace.workspaceId)
        let elapsedSuffix = elapsed.map { " entryElapsedMs=\($0)" } ?? ""
        emit(event, message: """
        [workspace-launch] host-mounted workspace=\(workspace.workspaceId) \
        project=\(workspace.projectPath) \
        active=\(isActive) \
        tabs=\(workspace.tabs.count) \
        panes=\(workspace.totalPaneCount)\(elapsedSuffix)
        """)
    }

    public func recordSurfaceCreationStarted(request: WorkspaceTerminalLaunchRequest) {
        surfaceStartTimeBySurfaceId[request.surfaceId] = now()
        let event = WorkspaceLaunchDiagnosticEvent.surfaceCreationStarted(
            workspaceId: request.workspaceId,
            projectPath: request.projectPath,
            tabId: request.tabId,
            paneId: request.paneId,
            surfaceId: request.surfaceId
        )
        let elapsed = elapsedMs(sinceWorkspaceEntry: request.workspaceId)
        let elapsedSuffix = elapsed.map { " entryElapsedMs=\($0)" } ?? ""
        emit(event, message: """
        [workspace-launch] surface-start workspace=\(request.workspaceId) \
        tab=\(request.tabId) \
        pane=\(request.paneId) \
        surface=\(request.surfaceId) \
        project=\(request.projectPath)\(elapsedSuffix)
        """)
    }

    public func recordSurfaceCreationFinished(
        request: WorkspaceTerminalLaunchRequest,
        status: WorkspaceLaunchSurfaceStatus,
        errorDescription: String?
    ) {
        let durationMs = elapsedMs(sinceSurfaceStart: request.surfaceId) ?? 0
        let event = WorkspaceLaunchDiagnosticEvent.surfaceCreationFinished(
            workspaceId: request.workspaceId,
            projectPath: request.projectPath,
            tabId: request.tabId,
            paneId: request.paneId,
            surfaceId: request.surfaceId,
            durationMs: durationMs,
            status: status,
            errorDescription: errorDescription
        )
        let entryElapsed = elapsedMs(sinceWorkspaceEntry: request.workspaceId)
        let entryElapsedSuffix = entryElapsed.map { " entryElapsedMs=\($0)" } ?? ""
        let errorSuffix = errorDescription.map { " error=\($0)" } ?? ""
        emit(event, message: """
        [workspace-launch] surface-finish workspace=\(request.workspaceId) \
        tab=\(request.tabId) \
        pane=\(request.paneId) \
        surface=\(request.surfaceId) \
        project=\(request.projectPath) \
        status=\(status.rawValue) \
        durationMs=\(durationMs)\(entryElapsedSuffix)\(errorSuffix)
        """)
    }

    public func recordSurfaceReused(request: WorkspaceTerminalLaunchRequest) {
        let event = WorkspaceLaunchDiagnosticEvent.surfaceReused(
            workspaceId: request.workspaceId,
            projectPath: request.projectPath,
            tabId: request.tabId,
            paneId: request.paneId,
            surfaceId: request.surfaceId
        )
        let elapsed = elapsedMs(sinceWorkspaceEntry: request.workspaceId)
        let elapsedSuffix = elapsed.map { " entryElapsedMs=\($0)" } ?? ""
        emit(event, message: """
        [workspace-launch] surface-reused workspace=\(request.workspaceId) \
        tab=\(request.tabId) \
        pane=\(request.paneId) \
        surface=\(request.surfaceId) \
        project=\(request.projectPath)\(elapsedSuffix)
        """)
    }

    private func emit(_ event: WorkspaceLaunchDiagnosticEvent, message: String) {
        eventSink(event)
        logSink(message)
    }

    private func elapsedMs(sinceWorkspaceEntry workspaceId: String) -> Int? {
        guard let start = entryStartTimeByWorkspaceId[workspaceId] else {
            return nil
        }
        return max(0, Int(((now() - start) * 1000).rounded()))
    }

    private func elapsedMs(sinceSurfaceStart surfaceId: String) -> Int? {
        guard let start = surfaceStartTimeBySurfaceId.removeValue(forKey: surfaceId) else {
            return nil
        }
        return max(0, Int(((now() - start) * 1000).rounded()))
    }
}

private extension WorkspaceSessionState {
    var totalPaneCount: Int {
        tabs.reduce(into: 0) { partialResult, tab in
            partialResult += tab.leaves.count
        }
    }
}
