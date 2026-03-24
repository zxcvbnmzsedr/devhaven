import AppKit
import OSLog
import DevHavenCore

private let ghosttySurfaceLifecycleLogger = Logger(
    subsystem: "DevHavenNative",
    category: "GhosttySurfaceLifecycle"
)

enum GhosttySurfaceLifecycleDiagnosticEvent: Equatable, Sendable {
    case representableMake(
        workspaceId: String,
        tabId: String,
        paneId: String,
        surfaceId: String,
        preferredFocus: Bool,
        prepareForAttachment: Bool
    )
    case representableUpdate(
        workspaceId: String,
        tabId: String,
        paneId: String,
        surfaceId: String,
        preferredFocus: Bool,
        prepareForAttachment: Bool,
        surfaceSwap: Bool
    )
    case surfaceAcquire(
        workspaceId: String,
        tabId: String,
        paneId: String,
        surfaceId: String,
        reused: Bool,
        hasWindow: Bool,
        firstResponderOwned: Bool
    )
    case prepareForContainerReuse(
        workspaceId: String,
        tabId: String,
        paneId: String,
        surfaceId: String,
        hasWindow: Bool,
        firstResponderOwned: Bool,
        isSurfaceFocused: Bool
    )
    case surfaceAttached(
        workspaceId: String,
        tabId: String,
        paneId: String,
        surfaceId: String,
        preferredFocus: Bool,
        hasWindow: Bool,
        windowIsKey: Bool,
        firstResponderOwned: Bool
    )
    case focusRequestDecision(
        workspaceId: String,
        tabId: String,
        paneId: String,
        surfaceId: String,
        preferredFocus: Bool,
        wasPreferredFocus: Bool,
        isSurfaceFocused: Bool,
        currentEventType: String?,
        shouldRequest: Bool
    )
    case resizeDecision(
        workspaceId: String,
        tabId: String,
        paneId: String,
        surfaceId: String,
        lastBackingWidth: Int,
        lastBackingHeight: Int,
        newBackingWidth: Int,
        newBackingHeight: Int,
        cellWidth: Int,
        cellHeight: Int,
        applied: Bool,
        targetWidth: Int?,
        targetHeight: Int?
    )
    case restoreWindowResponder(
        workspaceId: String,
        tabId: String,
        paneId: String,
        surfaceId: String,
        hasWindow: Bool,
        firstResponderOwned: Bool,
        performed: Bool,
        reason: String
    )
}

@MainActor
final class GhosttySurfaceLifecycleDiagnostics {
    static let shared = GhosttySurfaceLifecycleDiagnostics()

    private let logSink: (String) -> Void
    private let eventSink: (GhosttySurfaceLifecycleDiagnosticEvent) -> Void

    init(
        logSink: @escaping (String) -> Void = { message in
            ghosttySurfaceLifecycleLogger.notice("\(message, privacy: .public)")
        },
        eventSink: @escaping (GhosttySurfaceLifecycleDiagnosticEvent) -> Void = { _ in }
    ) {
        self.logSink = logSink
        self.eventSink = eventSink
    }

    func recordRepresentableMake(
        request: WorkspaceTerminalLaunchRequest,
        preferredFocus: Bool,
        prepareForAttachment: Bool
    ) {
        emit(
            .representableMake(
                workspaceId: request.workspaceId,
                tabId: request.tabId,
                paneId: request.paneId,
                surfaceId: request.surfaceId,
                preferredFocus: preferredFocus,
                prepareForAttachment: prepareForAttachment
            ),
            message: """
            [ghostty-surface] representable-make workspace=\(request.workspaceId) \
            tab=\(request.tabId) \
            pane=\(request.paneId) \
            surface=\(request.surfaceId) \
            preferredFocus=\(preferredFocus) \
            prepareForAttachment=\(prepareForAttachment)
            """
        )
    }

    func recordRepresentableUpdate(
        request: WorkspaceTerminalLaunchRequest,
        preferredFocus: Bool,
        prepareForAttachment: Bool,
        surfaceSwap: Bool
    ) {
        emit(
            .representableUpdate(
                workspaceId: request.workspaceId,
                tabId: request.tabId,
                paneId: request.paneId,
                surfaceId: request.surfaceId,
                preferredFocus: preferredFocus,
                prepareForAttachment: prepareForAttachment,
                surfaceSwap: surfaceSwap
            ),
            message: """
            [ghostty-surface] representable-update workspace=\(request.workspaceId) \
            tab=\(request.tabId) \
            pane=\(request.paneId) \
            surface=\(request.surfaceId) \
            preferredFocus=\(preferredFocus) \
            prepareForAttachment=\(prepareForAttachment) \
            surfaceSwap=\(surfaceSwap)
            """
        )
    }

    func recordSurfaceAcquire(
        request: WorkspaceTerminalLaunchRequest,
        reused: Bool,
        hasWindow: Bool,
        firstResponderOwned: Bool
    ) {
        emit(
            .surfaceAcquire(
                workspaceId: request.workspaceId,
                tabId: request.tabId,
                paneId: request.paneId,
                surfaceId: request.surfaceId,
                reused: reused,
                hasWindow: hasWindow,
                firstResponderOwned: firstResponderOwned
            ),
            message: """
            [ghostty-surface] acquire workspace=\(request.workspaceId) \
            tab=\(request.tabId) \
            pane=\(request.paneId) \
            surface=\(request.surfaceId) \
            reused=\(reused) \
            hasWindow=\(hasWindow) \
            firstResponderOwned=\(firstResponderOwned)
            """
        )
    }

    func recordPrepareForContainerReuse(
        request: WorkspaceTerminalLaunchRequest,
        hasWindow: Bool,
        firstResponderOwned: Bool,
        isSurfaceFocused: Bool
    ) {
        emit(
            .prepareForContainerReuse(
                workspaceId: request.workspaceId,
                tabId: request.tabId,
                paneId: request.paneId,
                surfaceId: request.surfaceId,
                hasWindow: hasWindow,
                firstResponderOwned: firstResponderOwned,
                isSurfaceFocused: isSurfaceFocused
            ),
            message: """
            [ghostty-surface] prepare-reuse workspace=\(request.workspaceId) \
            tab=\(request.tabId) \
            pane=\(request.paneId) \
            surface=\(request.surfaceId) \
            hasWindow=\(hasWindow) \
            firstResponderOwned=\(firstResponderOwned) \
            isSurfaceFocused=\(isSurfaceFocused)
            """
        )
    }

    func recordSurfaceAttached(
        request: WorkspaceTerminalLaunchRequest,
        preferredFocus: Bool,
        hasWindow: Bool,
        windowIsKey: Bool,
        firstResponderOwned: Bool
    ) {
        emit(
            .surfaceAttached(
                workspaceId: request.workspaceId,
                tabId: request.tabId,
                paneId: request.paneId,
                surfaceId: request.surfaceId,
                preferredFocus: preferredFocus,
                hasWindow: hasWindow,
                windowIsKey: windowIsKey,
                firstResponderOwned: firstResponderOwned
            ),
            message: """
            [ghostty-surface] attached workspace=\(request.workspaceId) \
            tab=\(request.tabId) \
            pane=\(request.paneId) \
            surface=\(request.surfaceId) \
            preferredFocus=\(preferredFocus) \
            hasWindow=\(hasWindow) \
            windowIsKey=\(windowIsKey) \
            firstResponderOwned=\(firstResponderOwned)
            """
        )
    }

    func recordFocusRequestDecision(
        request: WorkspaceTerminalLaunchRequest,
        preferredFocus: Bool,
        wasPreferredFocus: Bool,
        isSurfaceFocused: Bool,
        currentEventType: String?,
        shouldRequest: Bool
    ) {
        emit(
            .focusRequestDecision(
                workspaceId: request.workspaceId,
                tabId: request.tabId,
                paneId: request.paneId,
                surfaceId: request.surfaceId,
                preferredFocus: preferredFocus,
                wasPreferredFocus: wasPreferredFocus,
                isSurfaceFocused: isSurfaceFocused,
                currentEventType: currentEventType,
                shouldRequest: shouldRequest
            ),
            message: """
            [ghostty-surface] focus-request workspace=\(request.workspaceId) \
            tab=\(request.tabId) \
            pane=\(request.paneId) \
            surface=\(request.surfaceId) \
            preferredFocus=\(preferredFocus) \
            wasPreferredFocus=\(wasPreferredFocus) \
            isSurfaceFocused=\(isSurfaceFocused) \
            event=\(currentEventType ?? "nil") \
            shouldRequest=\(shouldRequest)
            """
        )
    }

    func recordResizeDecision(
        request: WorkspaceTerminalLaunchRequest,
        lastBackingSize: CGSize,
        newBackingSize: CGSize,
        cellSizeInPixels: CGSize,
        applied: Bool,
        targetWidth: UInt32?,
        targetHeight: UInt32?
    ) {
        emit(
            .resizeDecision(
                workspaceId: request.workspaceId,
                tabId: request.tabId,
                paneId: request.paneId,
                surfaceId: request.surfaceId,
                lastBackingWidth: Int(lastBackingSize.width.rounded(.down)),
                lastBackingHeight: Int(lastBackingSize.height.rounded(.down)),
                newBackingWidth: Int(newBackingSize.width.rounded(.down)),
                newBackingHeight: Int(newBackingSize.height.rounded(.down)),
                cellWidth: Int(cellSizeInPixels.width.rounded(.down)),
                cellHeight: Int(cellSizeInPixels.height.rounded(.down)),
                applied: applied,
                targetWidth: targetWidth.map(Int.init),
                targetHeight: targetHeight.map(Int.init)
            ),
            message: """
            [ghostty-surface] resize workspace=\(request.workspaceId) \
            tab=\(request.tabId) \
            pane=\(request.paneId) \
            surface=\(request.surfaceId) \
            lastBackingWidth=\(Int(lastBackingSize.width.rounded(.down))) \
            lastBackingHeight=\(Int(lastBackingSize.height.rounded(.down))) \
            newBackingWidth=\(Int(newBackingSize.width.rounded(.down))) \
            newBackingHeight=\(Int(newBackingSize.height.rounded(.down))) \
            cellWidth=\(Int(cellSizeInPixels.width.rounded(.down))) \
            cellHeight=\(Int(cellSizeInPixels.height.rounded(.down))) \
            applied=\(applied) \
            targetWidth=\(targetWidth.map(String.init) ?? "nil") \
            targetHeight=\(targetHeight.map(String.init) ?? "nil")
            """
        )
    }

    func recordRestoreWindowResponder(
        request: WorkspaceTerminalLaunchRequest,
        hasWindow: Bool,
        firstResponderOwned: Bool,
        performed: Bool,
        reason: String
    ) {
        emit(
            .restoreWindowResponder(
                workspaceId: request.workspaceId,
                tabId: request.tabId,
                paneId: request.paneId,
                surfaceId: request.surfaceId,
                hasWindow: hasWindow,
                firstResponderOwned: firstResponderOwned,
                performed: performed,
                reason: reason
            ),
            message: """
            [ghostty-surface] restore-responder workspace=\(request.workspaceId) \
            tab=\(request.tabId) \
            pane=\(request.paneId) \
            surface=\(request.surfaceId) \
            hasWindow=\(hasWindow) \
            firstResponderOwned=\(firstResponderOwned) \
            performed=\(performed) \
            reason=\(reason)
            """
        )
    }

    private func emit(_ event: GhosttySurfaceLifecycleDiagnosticEvent, message: String) {
        eventSink(event)
        logSink(message)
    }
}
