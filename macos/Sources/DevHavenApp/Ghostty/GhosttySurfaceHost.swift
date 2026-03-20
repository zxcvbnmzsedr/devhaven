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

struct GhosttySurfaceHost: View {
    let request: WorkspaceTerminalLaunchRequest
    let isFocused: Bool
    let onFocusChange: ((Bool) -> Void)?
    let onSurfaceExit: (() -> Void)?
    let onTabTitleChange: ((String) -> Void)?
    let onNewTab: (() -> Bool)?
    let onCloseTab: ((ghostty_action_close_tab_mode_e) -> Bool)?
    let onGotoTab: ((ghostty_action_goto_tab_e) -> Bool)?
    let onMoveTab: ((ghostty_action_move_tab_s) -> Bool)?
    let onSplitAction: ((GhosttySplitAction) -> Bool)?

    @StateObject private var model: GhosttySurfaceHostModel

    init(
        request: WorkspaceTerminalLaunchRequest,
        isFocused: Bool = false,
        onFocusChange: ((Bool) -> Void)? = nil,
        onSurfaceExit: (() -> Void)? = nil,
        onTabTitleChange: ((String) -> Void)? = nil,
        onNewTab: (() -> Bool)? = nil,
        onCloseTab: ((ghostty_action_close_tab_mode_e) -> Bool)? = nil,
        onGotoTab: ((ghostty_action_goto_tab_e) -> Bool)? = nil,
        onMoveTab: ((ghostty_action_move_tab_s) -> Bool)? = nil,
        onSplitAction: ((GhosttySplitAction) -> Bool)? = nil
    ) {
        self.request = request
        self.isFocused = isFocused
        self.onFocusChange = onFocusChange
        self.onSurfaceExit = onSurfaceExit
        self.onTabTitleChange = onTabTitleChange
        self.onNewTab = onNewTab
        self.onCloseTab = onCloseTab
        self.onGotoTab = onGotoTab
        self.onMoveTab = onMoveTab
        self.onSplitAction = onSplitAction
        _model = StateObject(
            wrappedValue: GhosttySurfaceHostModel(
                request: request,
                onFocusChange: onFocusChange,
                onSurfaceExit: onSurfaceExit,
                onTabTitleChange: onTabTitleChange,
                onNewTab: onNewTab,
                onCloseTab: onCloseTab,
                onGotoTab: onGotoTab,
                onMoveTab: onMoveTab,
                onSplitAction: onSplitAction
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                GhosttyTerminalView(model: model, isFocused: isFocused)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(model.appearance.backgroundColor)
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(model.appearance.borderColor, lineWidth: 1)
                    )
            }
        }
        .onDisappear {
            model.releaseSurface()
        }
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
    let request: WorkspaceTerminalLaunchRequest
    let terminalRuntime: GhosttyRuntime?

    @Published var initializationError: String?
    @Published var surfaceTitle: String?
    @Published var surfaceWorkingDirectory: String?
    @Published var rendererHealthy = true
    @Published var appearance: GhosttySurfaceAppearance = .fallback
    @Published var processState: GhosttySurfaceProcessState = .starting

    private let appRuntime: GhosttyAppRuntime
    private let onFocusChange: ((Bool) -> Void)?
    private let onSurfaceExit: (() -> Void)?
    private let onTabTitleChange: ((String) -> Void)?
    private let onNewTab: (() -> Bool)?
    private let onCloseTab: ((ghostty_action_close_tab_mode_e) -> Bool)?
    private let onGotoTab: ((ghostty_action_goto_tab_e) -> Bool)?
    private let onMoveTab: ((ghostty_action_move_tab_s) -> Bool)?
    private let onSplitAction: ((GhosttySplitAction) -> Bool)?
    private var ownedSurfaceView: GhosttyTerminalSurfaceView?

    init(
        request: WorkspaceTerminalLaunchRequest,
        onFocusChange: ((Bool) -> Void)? = nil,
        onSurfaceExit: (() -> Void)? = nil,
        onTabTitleChange: ((String) -> Void)? = nil,
        onNewTab: (() -> Bool)? = nil,
        onCloseTab: ((ghostty_action_close_tab_mode_e) -> Bool)? = nil,
        onGotoTab: ((ghostty_action_goto_tab_e) -> Bool)? = nil,
        onMoveTab: ((ghostty_action_move_tab_s) -> Bool)? = nil,
        onSplitAction: ((GhosttySplitAction) -> Bool)? = nil,
        appRuntime: GhosttyAppRuntime = .shared
    ) {
        self.request = request
        self.appRuntime = appRuntime
        self.onFocusChange = onFocusChange
        self.onSurfaceExit = onSurfaceExit
        self.onTabTitleChange = onTabTitleChange
        self.onNewTab = onNewTab
        self.onCloseTab = onCloseTab
        self.onGotoTab = onGotoTab
        self.onMoveTab = onMoveTab
        self.onSplitAction = onSplitAction
        self.terminalRuntime = appRuntime.runtime
        self.surfaceWorkingDirectory = request.projectPath
        self.appearance = terminalRuntime?.appearance ?? .fallback
        self.initializationError = appRuntime.initializationError ?? terminalRuntime?.initializationError
        self.processState = initializationError == nil ? .running : .failed
    }

    func acquireSurfaceView(preferredFocus: Bool = false) -> GhosttyTerminalSurfaceView {
        if let ownedSurfaceView {
            if preferredFocus {
                ownedSurfaceView.requestFocus()
            }
            return ownedSurfaceView
        }

        guard let terminalRuntime else {
            preconditionFailure("Ghostty runtime 尚未就绪")
        }

        let bridge = GhosttySurfaceBridge()
        bridge.onTitleChange = { [weak self] title in
            self?.surfaceTitle = title
            self?.onTabTitleChange?(title)
        }
        bridge.onWorkingDirectoryChange = { [weak self] path in
            self?.surfaceWorkingDirectory = path
        }
        bridge.onRendererHealthChange = { [weak self] healthy in
            self?.rendererHealthy = healthy
        }
        bridge.onAppearanceChange = { [weak self] appearance in
            self?.appearance = appearance
        }
        bridge.onCloseRequest = { [weak self] processAlive in
            self?.handleProcessExit(processAlive: processAlive)
        }
        bridge.onNewTab = onNewTab
        bridge.onCloseTab = onCloseTab
        bridge.onGotoTab = onGotoTab
        bridge.onMoveTab = onMoveTab
        bridge.onSplitAction = onSplitAction

        let view = GhosttyTerminalSurfaceView(
            runtime: terminalRuntime,
            request: request,
            bridge: bridge,
            extraEnvironment: request.environment
        )
        view.onFocusChange = { [weak self] focused in
            self?.onFocusChange?(focused)
        }
        ownedSurfaceView = view
        if let error = view.initializationError {
            initializationError = error.localizedDescription
            processState = .failed
        } else if preferredFocus {
            view.requestFocus()
        }
        return view
    }

    func applyLatestModelState(preferredFocus: Bool = false) {
        ownedSurfaceView?.applyLatestModelState()
        if preferredFocus {
            ownedSurfaceView?.requestFocus()
        }
    }

    func releaseSurface() {
        ownedSurfaceView?.tearDown()
        ownedSurfaceView = nil
    }

    private func handleProcessExit(processAlive: Bool) {
        guard !processAlive else {
            return
        }

        ownedSurfaceView?.tearDown()
        ownedSurfaceView = nil
        rendererHealthy = true
        processState = .exited
        onSurfaceExit?()
    }

    var terminalStatusText: String {
        switch processState {
        case .starting:
            return "Ghostty 启动中"
        case .running:
            return rendererHealthy ? "Ghostty 渲染器正常" : "Ghostty 渲染器异常"
        case .exited:
            return "终端已退出"
        case .failed:
            return "Ghostty 初始化失败"
        }
    }
}
