import Foundation
import OSLog

private let workspaceBrowserLogger = Logger(
    subsystem: "DevHavenNative",
    category: "WorkspaceBrowser"
)

@MainActor
enum WorkspaceBrowserDiagnostics {
    static func recordSyncRequest(
        surfaceId: String,
        tabId: String,
        paneId: String,
        stateURL: String,
        currentURL: String,
        willNavigate: Bool
    ) {
        workspaceBrowserLogger.notice(
            """
            [workspace-browser] sync surface=\(surfaceId, privacy: .public) \
            tab=\(tabId, privacy: .public) \
            pane=\(paneId, privacy: .public) \
            stateURL=\(stateURL, privacy: .public) \
            currentURL=\(currentURL, privacy: .public) \
            willNavigate=\(willNavigate)
            """
        )
    }

    static func recordNavigateRequest(
        surfaceId: String,
        tabId: String,
        paneId: String,
        rawInput: String,
        resolvedURL: String?
    ) {
        workspaceBrowserLogger.notice(
            """
            [workspace-browser] navigate-request surface=\(surfaceId, privacy: .public) \
            tab=\(tabId, privacy: .public) \
            pane=\(paneId, privacy: .public) \
            rawInput=\(rawInput, privacy: .public) \
            resolvedURL=\((resolvedURL ?? "nil"), privacy: .public)
            """
        )
    }

    static func recordNavigationEvent(
        surfaceId: String,
        tabId: String,
        paneId: String,
        phase: String,
        urlString: String,
        errorDescription: String? = nil
    ) {
        workspaceBrowserLogger.notice(
            """
            [workspace-browser] navigation-event surface=\(surfaceId, privacy: .public) \
            tab=\(tabId, privacy: .public) \
            pane=\(paneId, privacy: .public) \
            phase=\(phase, privacy: .public) \
            url=\(urlString, privacy: .public) \
            error=\((errorDescription ?? "nil"), privacy: .public)
            """
        )
    }

    static func recordSnapshotPublish(
        surfaceId: String,
        tabId: String,
        paneId: String,
        source: String,
        emitted: Bool,
        snapshot: WorkspaceBrowserRuntimeSnapshot
    ) {
        workspaceBrowserLogger.notice(
            """
            [workspace-browser] snapshot surface=\(surfaceId, privacy: .public) \
            tab=\(tabId, privacy: .public) \
            pane=\(paneId, privacy: .public) \
            source=\(source, privacy: .public) \
            emitted=\(emitted) \
            title=\(snapshot.title, privacy: .public) \
            url=\(snapshot.urlString, privacy: .public) \
            loading=\(snapshot.isLoading) \
            canGoBack=\(snapshot.canGoBack) \
            canGoForward=\(snapshot.canGoForward)
            """
        )
    }

    static func recordProjectionUpdate(
        surfaceId: String,
        tabId: String,
        paneId: String,
        runtime: WorkspaceBrowserRuntimeSnapshot,
        projected: WorkspaceBrowserProjectionUpdate
    ) {
        workspaceBrowserLogger.notice(
            """
            [workspace-browser] projection-update surface=\(surfaceId, privacy: .public) \
            tab=\(tabId, privacy: .public) \
            pane=\(paneId, privacy: .public) \
            runtimeURL=\(runtime.urlString, privacy: .public) \
            runtimeLoading=\(runtime.isLoading) \
            projectedURL=\(projected.urlString, privacy: .public) \
            projectedLoading=\(projected.isLoading) \
            suppressedProjectionWhileLoading=\(projected.suppressedProjectionWhileLoading)
            """
        )
    }
}
