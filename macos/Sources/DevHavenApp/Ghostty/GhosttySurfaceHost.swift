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
            return "Ghostty app runtime 创建失败。"
        case .configCreationFailed:
            return "Ghostty config 创建失败。"
        case .surfaceCreationFailed:
            return "Ghostty surface 创建失败。"
        }
    }
}

struct GhosttySurfaceHost: View {
    let request: WorkspaceTerminalLaunchRequest

    @StateObject private var model: GhosttySurfaceHostModel

    init(request: WorkspaceTerminalLaunchRequest) {
        self.request = request
        _model = StateObject(wrappedValue: GhosttySurfaceHostModel(request: request))
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
                    Text("Ghostty shell 已退出")
                        .font(.headline)
                        .foregroundStyle(model.appearance.primaryTextColor)
                    Text("Ctrl+D 或 shell exit 后，当前 pane 只释放 surface，本次不再销毁 app 级 runtime；workspace 仍可继续操作。")
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
                GhosttyTerminalView(model: model)
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
    private var ownedSurfaceView: GhosttyTerminalSurfaceView?

    init(
        request: WorkspaceTerminalLaunchRequest,
        appRuntime: GhosttyAppRuntime = .shared
    ) {
        self.request = request
        self.appRuntime = appRuntime
        self.terminalRuntime = appRuntime.runtime
        self.surfaceWorkingDirectory = request.projectPath
        self.appearance = terminalRuntime?.appearance ?? .fallback
        self.initializationError = appRuntime.initializationError ?? terminalRuntime?.initializationError
        self.processState = initializationError == nil ? .running : .failed
    }

    func acquireSurfaceView() -> GhosttyTerminalSurfaceView {
        if let ownedSurfaceView {
            return ownedSurfaceView
        }

        guard let terminalRuntime else {
            preconditionFailure("Ghostty runtime 尚未就绪")
        }

        let bridge = GhosttySurfaceBridge()
        bridge.onTitleChange = { [weak self] title in
            self?.surfaceTitle = title
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

        let view = GhosttyTerminalSurfaceView(
            runtime: terminalRuntime,
            request: request,
            bridge: bridge,
            extraEnvironment: request.environment
        )
        ownedSurfaceView = view
        if let error = view.initializationError {
            initializationError = error.localizedDescription
            processState = .failed
        }
        return view
    }

    func applyLatestModelState() {
        ownedSurfaceView?.applyLatestModelState()
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
    }

    var terminalStatusText: String {
        switch processState {
        case .starting:
            return "Ghostty 启动中"
        case .running:
            return rendererHealthy ? "Ghostty renderer 正常" : "Ghostty renderer 异常"
        case .exited:
            return "Shell 已退出"
        case .failed:
            return "Ghostty 初始化失败"
        }
    }
}
