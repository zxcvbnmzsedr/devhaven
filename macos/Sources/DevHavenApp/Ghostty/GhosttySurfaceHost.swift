import AppKit
import SwiftUI
import GhosttyKit
import DevHavenCore

struct GhosttySurfaceAppearance: Equatable {
    var backgroundRed: Double
    var backgroundGreen: Double
    var backgroundBlue: Double
    var backgroundOpacity: Double

    init(
        backgroundRed: Double = 0.08,
        backgroundGreen: Double = 0.09,
        backgroundBlue: Double = 0.11,
        backgroundOpacity: Double = 1
    ) {
        self.backgroundRed = backgroundRed
        self.backgroundGreen = backgroundGreen
        self.backgroundBlue = backgroundBlue
        self.backgroundOpacity = backgroundOpacity
    }

    init(config: ghostty_config_t?) {
        guard let config else {
            self.init()
            return
        }

        var color = ghostty_config_color_s()
        let backgroundKey = "background"
        let hasBackground = ghostty_config_get(
            config,
            &color,
            backgroundKey,
            UInt(backgroundKey.lengthOfBytes(using: .utf8))
        )

        var opacity: Double = 1
        let opacityKey = "background-opacity"
        _ = ghostty_config_get(
            config,
            &opacity,
            opacityKey,
            UInt(opacityKey.lengthOfBytes(using: .utf8))
        )

        self.init(
            backgroundRed: hasBackground ? Double(color.r) / 255 : 0.08,
            backgroundGreen: hasBackground ? Double(color.g) / 255 : 0.09,
            backgroundBlue: hasBackground ? Double(color.b) / 255 : 0.11,
            backgroundOpacity: opacity
        )
    }

    init(backgroundColorChange change: ghostty_action_color_change_s, fallback: GhosttySurfaceAppearance) {
        guard change.kind == GHOSTTY_ACTION_COLOR_KIND_BACKGROUND else {
            self = fallback
            return
        }

        self.init(
            backgroundRed: Double(change.r) / 255,
            backgroundGreen: Double(change.g) / 255,
            backgroundBlue: Double(change.b) / 255,
            backgroundOpacity: fallback.backgroundOpacity
        )
    }

    static let fallback = GhosttySurfaceAppearance()

    var backgroundColor: Color {
        Color(
            red: backgroundRed,
            green: backgroundGreen,
            blue: backgroundBlue,
            opacity: max(0.01, min(backgroundOpacity, 1))
        )
    }

    var chromeBackground: Color {
        Color(
            red: backgroundRed,
            green: backgroundGreen,
            blue: backgroundBlue
        )
        .opacity(max(0.86, min(backgroundOpacity, 1)))
    }

    var overlayBackground: Color {
        chromeBackground.opacity(0.92)
    }

    var borderColor: Color {
        isLightBackground ? Color.black.opacity(0.18) : Color.white.opacity(0.16)
    }

    var primaryTextColor: Color {
        isLightBackground ? Color.black.opacity(0.88) : Color.white.opacity(0.94)
    }

    var secondaryTextColor: Color {
        isLightBackground ? Color.black.opacity(0.62) : Color.white.opacity(0.66)
    }

    var chipBackground: Color {
        isLightBackground ? Color.white.opacity(0.58) : Color.white.opacity(0.08)
    }

    var successChipBackground: Color {
        Color.green.opacity(isLightBackground ? 0.18 : 0.26)
    }

    var warningChipBackground: Color {
        Color.orange.opacity(isLightBackground ? 0.18 : 0.28)
    }

    private var isLightBackground: Bool {
        let luminance = (0.2126 * backgroundRed) + (0.7152 * backgroundGreen) + (0.0722 * backgroundBlue)
        return luminance >= 0.64
    }
}

enum GhosttySurfaceProcessState: Equatable {
    case starting
    case running
    case exited
    case failed
}

enum GhosttySurfaceHostError: LocalizedError {
    case runtimeUnavailable(String)
    case appCreationFailed
    case configCreationFailed
    case surfaceCreationFailed

    var errorDescription: String? {
        switch self {
        case let .runtimeUnavailable(message):
            return message
        case .appCreationFailed:
            return "Ghostty 应用级运行时创建失败。"
        case .configCreationFailed:
            return "Ghostty config 创建失败。"
        case .surfaceCreationFailed:
            return "Ghostty 终端实例创建失败。"
        }
    }
}

enum GhosttyRuntimeEnvironmentBuilder {
    static func build(
        baseEnvironment: [String: String],
        store: LegacyCompatStore = LegacyCompatStore(),
        agentResourcesURL: URL? = DevHavenAppResourceLocator.resolveAgentResourcesURL(),
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = baseEnvironment
        let signalDirectory = store.agentStatusSessionsDirectoryURL
        environment["DEVHAVEN_AGENT_SIGNAL_DIR"] = signalDirectory.path

        guard let agentResourcesURL else {
            return environment
        }

        environment["DEVHAVEN_AGENT_RESOURCES_DIR"] = agentResourcesURL.path
        let binDirectory = agentResourcesURL.appending(path: "bin", directoryHint: .isDirectory).path
        environment["DEVHAVEN_AGENT_BIN_DIR"] = binDirectory
        let existingPath = environment["PATH"] ?? processEnvironment["PATH"] ?? ""
        if existingPath.isEmpty {
            environment["PATH"] = binDirectory
        } else if !existingPath.split(separator: ":").contains(Substring(binDirectory)) {
            environment["PATH"] = "\(binDirectory):\(existingPath)"
        } else {
            environment["PATH"] = existingPath
        }

        return environment
    }
}

struct GhosttySurfaceHost: View {
    let isFocused: Bool
    let chromePolicy: WorkspaceChromePolicy

    @ObservedObject var model: GhosttySurfaceHostModel

    init(
        model: GhosttySurfaceHostModel,
        isFocused: Bool = false,
        chromePolicy: WorkspaceChromePolicy = .workspaceMinimal
    ) {
        self.model = model
        self.isFocused = isFocused
        self.chromePolicy = chromePolicy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if chromePolicy.showsSurfaceStatusBar {
                HStack(spacing: 12) {
                    statusChip(
                        title: model.terminalStatusText,
                        background: model.processState == .running
                            ? model.appearance.successChipBackground
                            : model.appearance.warningChipBackground
                    )
                    if let title = model.surfaceTitle, !title.isEmpty {
                        statusChip(title: title, background: model.appearance.chipBackground)
                    }
                    if let pwd = model.surfaceWorkingDirectory, !pwd.isEmpty {
                        statusChip(title: pwd, background: model.appearance.chipBackground, monospaced: true)
                    }
                    Spacer(minLength: 0)
                }
            }

            if let initializationError = model.initializationError {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ghostty 内嵌终端初始化失败")
                        .font(.headline)
                        .foregroundStyle(model.appearance.primaryTextColor)
                    Text(initializationError)
                        .font(.caption)
                        .foregroundStyle(model.appearance.secondaryTextColor)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
                .background(model.appearance.overlayBackground)
                .clipShape(.rect(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(model.appearance.borderColor, lineWidth: 1)
                )
            } else if model.processState == .exited {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ghostty 终端已退出")
                        .font(.headline)
                        .foregroundStyle(model.appearance.primaryTextColor)
                    Text("Ctrl+D 或终端退出后，当前窗格只会释放当前终端实例，本次不再销毁应用级运行时；工作区仍可继续操作。")
                        .font(.caption)
                        .foregroundStyle(model.appearance.secondaryTextColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
                .background(model.appearance.overlayBackground)
                .clipShape(.rect(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(model.appearance.borderColor, lineWidth: 1)
                )
            } else {
                ZStack(alignment: .topLeading) {
                    GhosttyTerminalView(model: model, isFocused: isFocused)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(model.appearance.backgroundColor)
                        .clipShape(.rect(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(model.appearance.borderColor, lineWidth: 1)
                        )

                    if WorkspaceTerminalStartupPresentationPolicy.shouldShowOverlay(
                        hasInitializationError: model.initializationError != nil,
                        processState: model.processState,
                        hasSurfaceView: model.hasPreparedSurfaceView
                    ) {
                        startupOverlay
                            .padding(14)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .allowsHitTesting(false)
                    }

                    if let surfaceView = model.currentSurfaceView,
                       surfaceView.bridge.state.searchNeedle != nil {
                        GhosttySurfaceSearchOverlay(surfaceView: surfaceView)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
            }
        }
    }

    private var startupOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("正在启动 shell...")
                .font(.callout.weight(.semibold))
                .foregroundStyle(model.appearance.primaryTextColor)
            Text("终端已创建，正在等待登录 shell 初始化完成。")
                .font(.caption)
                .foregroundStyle(model.appearance.secondaryTextColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(model.appearance.overlayBackground)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(model.appearance.borderColor, lineWidth: 1)
        )
    }

    private func statusChip(title: String, background: Color, monospaced: Bool = false) -> some View {
        Text(title)
            .font(monospaced ? .caption.monospaced() : .caption)
            .foregroundStyle(model.appearance.primaryTextColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background)
            .clipShape(.rect(cornerRadius: 9))
    }
}

@MainActor
final class GhosttySurfaceHostModel: ObservableObject {
    static let codexDisplaySnapshotWindowLimit = CodexAgentDisplaySnapshot.windowLimit

    struct SnapshotContext: Equatable, Sendable {
        var workingDirectory: String?
        var title: String?
        var visibleText: String?
        var agentSummary: String?
    }

    let request: WorkspaceTerminalLaunchRequest
    let terminalRuntime: GhosttyRuntime?

    @Published var initializationError: String?
    @Published var surfaceTitle: String?
    @Published var surfaceWorkingDirectory: String?
    @Published var rendererHealthy = true
    @Published var appearance: GhosttySurfaceAppearance = .fallback
    @Published var processState: GhosttySurfaceProcessState = .starting
    @Published var taskStatus: WorkspaceTaskStatus = .idle
    @Published var bellCount = 0
    @Published private(set) var hasPreparedSurfaceView = false

    private let appRuntime: GhosttyAppRuntime
    private let onFocusChange: ((Bool) -> Void)?
    private let onSurfaceExit: (() -> Void)?
    private let onTabTitleChange: ((String) -> Void)?
    var onNotificationEvent: ((String, String) -> Void)?
    var onTaskStatusChange: ((WorkspaceTaskStatus) -> Void)?
    var onBell: (() -> Void)?
    private let onNewTab: (() -> Bool)?
    private let onCloseTab: ((ghostty_action_close_tab_mode_e) -> Bool)?
    private let onGotoTab: ((ghostty_action_goto_tab_e) -> Bool)?
    private let onMoveTab: ((ghostty_action_move_tab_s) -> Bool)?
    private let onSplitAction: ((GhosttySplitAction) -> Bool)?
    private let workspaceLaunchDiagnostics: WorkspaceLaunchDiagnostics
    private var ownedSurfaceView: GhosttyTerminalSurfaceView?
    private var lastPreferredFocus = false
    private var lastSurfaceIsVisible = false
    private var lastSurfaceIsFocused = false
    private var pendingWindowResponderRestoreTask: Task<Void, Never>?
    private var pendingCodexDisplaySnapshotRefreshTask: Task<Void, Never>?
    private var codexDisplayTrackingEnabled = false
    private var cachedCodexDisplaySnapshot: CodexAgentDisplaySnapshot?
    private var onCodexDisplaySnapshotChange: ((CodexAgentDisplaySnapshot?) -> Void)?

    var currentSurfaceView: GhosttyTerminalSurfaceView? {
        ownedSurfaceView
    }

    func codexDisplaySnapshot() -> CodexAgentDisplaySnapshot? {
        cachedCodexDisplaySnapshot
    }

    func setCodexDisplaySnapshotObserver(
        _ observer: ((CodexAgentDisplaySnapshot?) -> Void)?
    ) {
        onCodexDisplaySnapshotChange = observer
        observer?(cachedCodexDisplaySnapshot)
    }

    func currentVisibleText() -> String? {
        guard let text = ownedSurfaceView?.debugVisibleText()
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            return request.restoreContext?.snapshotText
        }
        return text
    }

    func snapshotContext() -> SnapshotContext {
        SnapshotContext(
            workingDirectory: surfaceWorkingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? request.restoreContext?.workingDirectory,
            title: surfaceTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? request.restoreContext?.title,
            visibleText: currentVisibleText(),
            agentSummary: request.restoreContext?.agentSummary
        )
    }

    init(
        request: WorkspaceTerminalLaunchRequest,
        onFocusChange: ((Bool) -> Void)? = nil,
        onSurfaceExit: (() -> Void)? = nil,
        onTabTitleChange: ((String) -> Void)? = nil,
        onNotificationEvent: ((String, String) -> Void)? = nil,
        onTaskStatusChange: ((WorkspaceTaskStatus) -> Void)? = nil,
        onBell: (() -> Void)? = nil,
        onNewTab: (() -> Bool)? = nil,
        onCloseTab: ((ghostty_action_close_tab_mode_e) -> Bool)? = nil,
        onGotoTab: ((ghostty_action_goto_tab_e) -> Bool)? = nil,
        onMoveTab: ((ghostty_action_move_tab_s) -> Bool)? = nil,
        onSplitAction: ((GhosttySplitAction) -> Bool)? = nil,
        appRuntime: GhosttyAppRuntime = .shared,
        workspaceLaunchDiagnostics: WorkspaceLaunchDiagnostics = .shared
    ) {
        self.request = request
        self.appRuntime = appRuntime
        self.onFocusChange = onFocusChange
        self.onSurfaceExit = onSurfaceExit
        self.onTabTitleChange = onTabTitleChange
        self.onNotificationEvent = onNotificationEvent
        self.onTaskStatusChange = onTaskStatusChange
        self.onBell = onBell
        self.onNewTab = onNewTab
        self.onCloseTab = onCloseTab
        self.onGotoTab = onGotoTab
        self.onMoveTab = onMoveTab
        self.onSplitAction = onSplitAction
        self.workspaceLaunchDiagnostics = workspaceLaunchDiagnostics
        self.terminalRuntime = appRuntime.runtime
        self.surfaceWorkingDirectory = request.workingDirectory
        self.appearance = terminalRuntime?.appearance ?? .fallback
        self.initializationError = appRuntime.initializationError ?? terminalRuntime?.initializationError
        self.processState = initializationError == nil ? .running : .failed
        self.surfaceTitle = request.restoreContext?.title
    }

    func setCodexDisplayTrackingEnabled(_ enabled: Bool) {
        guard codexDisplayTrackingEnabled != enabled else {
            if enabled, cachedCodexDisplaySnapshot == nil {
                scheduleCodexDisplaySnapshotRefresh(immediate: true)
            }
            return
        }
        codexDisplayTrackingEnabled = enabled
        if enabled {
            scheduleCodexDisplaySnapshotRefresh(immediate: true)
        } else {
            clearCodexDisplaySnapshot()
        }
    }

    func updateCodexDisplaySnapshot(
        withVisibleText visibleText: String?,
        now: Date = Date()
    ) {
        guard codexDisplayTrackingEnabled else {
            return
        }
        let nextSnapshot = CodexAgentDisplaySnapshot.capture(
            from: visibleText,
            previous: cachedCodexDisplaySnapshot,
            now: now,
            windowLimit: Self.codexDisplaySnapshotWindowLimit
        )
        guard cachedCodexDisplaySnapshot != nextSnapshot else {
            return
        }
        cachedCodexDisplaySnapshot = nextSnapshot
        onCodexDisplaySnapshotChange?(nextSnapshot)
    }

    func acquireSurfaceView(preferredFocus: Bool = false) -> GhosttyTerminalSurfaceView {
        _ = preferredFocus
        if let ownedSurfaceView {
            GhosttySurfaceLifecycleDiagnostics.shared.recordSurfaceAcquire(
                request: request,
                reused: true,
                hasWindow: ownedSurfaceView.hasAttachedWindow,
                firstResponderOwned: ownedSurfaceView.ownsWindowFirstResponder
            )
            ownedSurfaceView.prepareForContainerReuse()
            hasPreparedSurfaceView = true
            workspaceLaunchDiagnostics.recordSurfaceReused(request: request)
            return ownedSurfaceView
        }

        guard let terminalRuntime else {
            preconditionFailure("Ghostty runtime 尚未就绪")
        }

        let bridge = GhosttySurfaceBridge()
        bridge.onTitleChange = { [weak self] title in
            guard let self else {
                return
            }
            guard self.surfaceTitle != title else {
                return
            }
            self.surfaceTitle = title
            self.onTabTitleChange?(title)
        }
        bridge.onWorkingDirectoryChange = { [weak self] path in
            guard let self else {
                return
            }
            guard self.surfaceWorkingDirectory != path else {
                return
            }
            self.surfaceWorkingDirectory = path
        }
        bridge.onRendererHealthChange = { [weak self] healthy in
            guard let self else {
                return
            }
            guard self.rendererHealthy != healthy else {
                return
            }
            self.rendererHealthy = healthy
        }
        bridge.onAppearanceChange = { [weak self] appearance in
            guard let self else {
                return
            }
            guard self.appearance != appearance else {
                return
            }
            self.appearance = appearance
        }
        bridge.onDesktopNotification = { [weak self] title, body in
            self?.onNotificationEvent?(title, body)
        }
        bridge.onTaskStatusChange = { [weak self] status in
            guard let self else {
                return
            }
            let resolvedStatus = self.mapTaskStatus(status)
            guard self.taskStatus != resolvedStatus else {
                return
            }
            self.taskStatus = resolvedStatus
            self.onTaskStatusChange?(resolvedStatus)
        }
        bridge.onBell = { [weak self] in
            guard let self else {
                return
            }
            self.bellCount += 1
            self.onBell?()
        }
        bridge.onContentInvalidated = { [weak self] in
            self?.scheduleCodexDisplaySnapshotRefresh()
        }
        bridge.onCloseRequest = { [weak self] processAlive in
            self?.handleProcessExit(processAlive: processAlive)
        }
        bridge.onNewTab = onNewTab
        bridge.onCloseTab = onCloseTab
        bridge.onGotoTab = onGotoTab
        bridge.onMoveTab = onMoveTab
        bridge.onSplitAction = onSplitAction

        workspaceLaunchDiagnostics.recordSurfaceCreationStarted(request: request)
        let extraEnvironment = resolvedRuntimeEnvironment()
        let view = GhosttyTerminalSurfaceView(
            runtime: terminalRuntime,
            request: request,
            bridge: bridge,
            extraEnvironment: extraEnvironment
        )
        view.onFocusChange = { [weak self] focused in
            self?.onFocusChange?(focused)
        }
        ownedSurfaceView = view
        hasPreparedSurfaceView = view.initializationError == nil
        if let error = view.initializationError {
            workspaceLaunchDiagnostics.recordSurfaceCreationFinished(
                request: request,
                status: .failed,
                errorDescription: error.localizedDescription
            )
            initializationError = error.localizedDescription
            processState = .failed
        } else {
            GhosttySurfaceLifecycleDiagnostics.shared.recordSurfaceAcquire(
                request: request,
                reused: false,
                hasWindow: view.hasAttachedWindow,
                firstResponderOwned: view.ownsWindowFirstResponder
            )
            workspaceLaunchDiagnostics.recordSurfaceCreationFinished(
                request: request,
                status: .success,
                errorDescription: nil
            )
        }
        return view
    }

    private func resolvedRuntimeEnvironment() -> [String: String] {
        GhosttyRuntimeEnvironmentBuilder.build(baseEnvironment: request.environment)
    }

    func surfaceViewDidAttach(preferredFocus: Bool) {
        guard let ownedSurfaceView else {
            return
        }
        GhosttySurfaceLifecycleDiagnostics.shared.recordSurfaceAttached(
            request: request,
            preferredFocus: preferredFocus,
            hasWindow: ownedSurfaceView.hasAttachedWindow,
            windowIsKey: ownedSurfaceView.windowIsKeyWindowForDiagnostics,
            firstResponderOwned: ownedSurfaceView.ownsWindowFirstResponder
        )
        applyCachedSurfaceActivity(to: ownedSurfaceView)
        requestFocusIfNeeded(for: ownedSurfaceView, preferredFocus: preferredFocus)
    }

    func applyLatestModelState(preferredFocus: Bool = false) {
        ownedSurfaceView?.applyLatestModelState()
        syncPreferredFocusTransition(preferredFocus: preferredFocus)
    }

    func syncPreferredFocusTransition(preferredFocus: Bool) {
        guard let ownedSurfaceView else {
            lastPreferredFocus = preferredFocus
            return
        }
        requestFocusIfNeeded(for: ownedSurfaceView, preferredFocus: preferredFocus)
    }

    func syncSurfaceActivity(isVisible: Bool, isFocused: Bool) {
        lastSurfaceIsVisible = isVisible
        lastSurfaceIsFocused = isFocused
        if !isFocused {
            cancelPendingWindowResponderRestore()
        }
        guard let ownedSurfaceView else {
            return
        }
        applyCachedSurfaceActivity(to: ownedSurfaceView)
    }

    func restoreWindowResponderIfNeeded() {
        guard shouldScheduleWindowResponderRestore() else {
            return
        }
        pendingWindowResponderRestoreTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else {
                return
            }
            self.pendingWindowResponderRestoreTask = nil
            self.performWindowResponderRestoreIfNeeded()
        }
    }

    func releaseSurface() {
        cancelPendingWindowResponderRestore()
        ownedSurfaceView?.tearDown()
        ownedSurfaceView = nil
        hasPreparedSurfaceView = false
        lastPreferredFocus = false
        lastSurfaceIsVisible = false
        lastSurfaceIsFocused = false
        clearCodexDisplaySnapshot()
    }

    private func handleProcessExit(processAlive: Bool) {
        guard !processAlive else {
            return
        }

        cancelPendingWindowResponderRestore()
        ownedSurfaceView?.tearDown()
        ownedSurfaceView = nil
        hasPreparedSurfaceView = false
        lastPreferredFocus = false
        lastSurfaceIsVisible = false
        lastSurfaceIsFocused = false
        clearCodexDisplaySnapshot()
        rendererHealthy = true
        processState = .exited
        onSurfaceExit?()
    }

    private func requestFocusIfNeeded(
        for view: GhosttyTerminalSurfaceView,
        preferredFocus: Bool
    ) {
        let currentEventType = NSApp.currentEvent?.type
        let shouldRequest = GhosttySurfaceFocusRequestPolicy.shouldRequestFocus(
            preferredFocus: preferredFocus,
            wasPreferredFocus: lastPreferredFocus,
            isSurfaceFocused: view.isCurrentlyFocused,
            currentEventType: currentEventType
        )
        GhosttySurfaceLifecycleDiagnostics.shared.recordFocusRequestDecision(
            request: request,
            preferredFocus: preferredFocus,
            wasPreferredFocus: lastPreferredFocus,
            isSurfaceFocused: view.isCurrentlyFocused,
            currentEventType: currentEventType.map { String(describing: $0) },
            shouldRequest: shouldRequest
        )
        guard shouldRequest else {
            lastPreferredFocus = preferredFocus
            return
        }
        lastPreferredFocus = preferredFocus
        view.requestFocus()
    }

    private func applyCachedSurfaceActivity(to view: GhosttyTerminalSurfaceView) {
        view.setOcclusion(lastSurfaceIsVisible)
        view.focusDidChange(lastSurfaceIsFocused)
    }

    private func cancelPendingWindowResponderRestore() {
        pendingWindowResponderRestoreTask?.cancel()
        pendingWindowResponderRestoreTask = nil
    }

    private func scheduleCodexDisplaySnapshotRefresh(immediate: Bool = false) {
        guard codexDisplayTrackingEnabled else {
            return
        }
        let delay: TimeInterval = immediate ? 0 : 0.25
        pendingCodexDisplaySnapshotRefreshTask?.cancel()
        pendingCodexDisplaySnapshotRefreshTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            if delay > 0 {
                try? await ContinuousClock().sleep(for: .seconds(delay))
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled else {
                return
            }
            self.pendingCodexDisplaySnapshotRefreshTask = nil
            self.updateCodexDisplaySnapshot(
                withVisibleText: self.ownedSurfaceView?.debugVisibleText(),
                now: Date()
            )
        }
    }

    private func cancelPendingCodexDisplaySnapshotRefresh() {
        pendingCodexDisplaySnapshotRefreshTask?.cancel()
        pendingCodexDisplaySnapshotRefreshTask = nil
    }

    private func clearCodexDisplaySnapshot() {
        cancelPendingCodexDisplaySnapshotRefresh()
        guard cachedCodexDisplaySnapshot != nil else {
            return
        }
        cachedCodexDisplaySnapshot = nil
        onCodexDisplaySnapshotChange?(nil)
    }

    private func shouldScheduleWindowResponderRestore() -> Bool {
        guard lastSurfaceIsFocused, let ownedSurfaceView else {
            GhosttySurfaceLifecycleDiagnostics.shared.recordRestoreWindowResponder(
                request: request,
                hasWindow: currentSurfaceView?.hasAttachedWindow ?? false,
                firstResponderOwned: currentSurfaceView?.ownsWindowFirstResponder ?? false,
                performed: false,
                reason: "surface-not-focused"
            )
            return false
        }
        guard let window = ownedSurfaceView.window else {
            GhosttySurfaceLifecycleDiagnostics.shared.recordRestoreWindowResponder(
                request: request,
                hasWindow: false,
                firstResponderOwned: false,
                performed: false,
                reason: "window-missing"
            )
            return false
        }
        guard window.firstResponder !== ownedSurfaceView else {
            GhosttySurfaceLifecycleDiagnostics.shared.recordRestoreWindowResponder(
                request: request,
                hasWindow: true,
                firstResponderOwned: true,
                performed: false,
                reason: "already-owned"
            )
            return false
        }
        guard pendingWindowResponderRestoreTask == nil else {
            GhosttySurfaceLifecycleDiagnostics.shared.recordRestoreWindowResponder(
                request: request,
                hasWindow: true,
                firstResponderOwned: false,
                performed: false,
                reason: "restore-pending"
            )
            return false
        }
        return true
    }

    private func performWindowResponderRestoreIfNeeded() {
        guard lastSurfaceIsFocused, let ownedSurfaceView else {
            GhosttySurfaceLifecycleDiagnostics.shared.recordRestoreWindowResponder(
                request: request,
                hasWindow: currentSurfaceView?.hasAttachedWindow ?? false,
                firstResponderOwned: currentSurfaceView?.ownsWindowFirstResponder ?? false,
                performed: false,
                reason: "surface-not-focused"
            )
            return
        }
        guard let window = ownedSurfaceView.window else {
            GhosttySurfaceLifecycleDiagnostics.shared.recordRestoreWindowResponder(
                request: request,
                hasWindow: false,
                firstResponderOwned: false,
                performed: false,
                reason: "window-missing"
            )
            return
        }
        guard window.firstResponder !== ownedSurfaceView else {
            GhosttySurfaceLifecycleDiagnostics.shared.recordRestoreWindowResponder(
                request: request,
                hasWindow: true,
                firstResponderOwned: true,
                performed: false,
                reason: "already-owned"
            )
            return
        }
        window.makeFirstResponder(ownedSurfaceView)
        GhosttySurfaceLifecycleDiagnostics.shared.recordRestoreWindowResponder(
            request: request,
            hasWindow: true,
            firstResponderOwned: ownedSurfaceView.ownsWindowFirstResponder,
            performed: true,
            reason: "restored"
        )
    }

    private func mapTaskStatus(_ status: GhosttySurfaceTaskStatus) -> WorkspaceTaskStatus {
        switch status {
        case .idle:
            return .idle
        case .running:
            return .running
        }
    }

    func startSearch() {
        currentSurfaceView?.performBindingAction("start_search")
    }

    func searchSelection() {
        currentSurfaceView?.performBindingAction("search_selection")
    }

    func navigateSearchNext() {
        currentSurfaceView?.performBindingAction("navigate_search:next")
    }

    func navigateSearchPrevious() {
        currentSurfaceView?.performBindingAction("navigate_search:previous")
    }

    func endSearch() {
        currentSurfaceView?.performBindingAction("end_search")
        currentSurfaceView?.requestFocus()
    }

    var terminalStatusText: String {
        switch processState {
        case .starting:
            return "Ghostty 启动中"
        case .running:
            if taskStatus == .running {
                return "命令执行中"
            }
            return rendererHealthy ? "Ghostty 渲染器正常" : "Ghostty 渲染器异常"
        case .exited:
            return "终端已退出"
        case .failed:
            return "Ghostty 初始化失败"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
