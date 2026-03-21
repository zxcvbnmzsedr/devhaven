import AppKit
import Foundation
import GhosttyKit
import DevHavenCore

enum GhosttyConfigFileError: LocalizedError {
    case fileCreationFailed(URL)

    var errorDescription: String? {
        switch self {
        case let .fileCreationFailed(url):
            return "Ghostty 配置文件创建失败：\(url.path)"
        }
    }
}

final class GhosttyRuntime {
    final class SurfaceReference {
        let surface: ghostty_surface_t
        var isValid = true

        init(_ surface: ghostty_surface_t) {
            self.surface = surface
        }

        func invalidate() {
            isValid = false
        }
    }

    private(set) var initializationError: String?
    private(set) var appearance: GhosttySurfaceAppearance = .fallback
    private var config: ghostty_config_t?
    private(set) var app: ghostty_app_t?
    private var observers: [NSObjectProtocol] = []
    private var surfaceRefs: [SurfaceReference] = []

    init() {
        guard let config = ghostty_config_new() else {
            initializationError = GhosttySurfaceHostError.configCreationFailed.localizedDescription
            return
        }

        self.config = config
        Self.loadPreferredConfigFiles(config)
        ghostty_config_finalize(config)
        appearance = GhosttySurfaceAppearance(config: config)

        var runtimeConfig = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: true,
            wakeup_cb: { userdata in
                GhosttyRuntime.handleWakeup(userdata)
            },
            action_cb: { app, target, action in
                GhosttyRuntime.handleAction(app, target: target, action: action)
            },
            read_clipboard_cb: { userdata, location, state in
                GhosttyRuntime.handleReadClipboard(userdata, location: location, state: state)
            },
            confirm_read_clipboard_cb: { userdata, content, state, request in
                GhosttyRuntime.handleConfirmReadClipboard(userdata, content, state, request)
            },
            write_clipboard_cb: { userdata, location, content, len, confirmed in
                GhosttyRuntime.handleWriteClipboard(
                    userdata,
                    location: location,
                    content: content,
                    len: len,
                    confirmed
                )
            },
            close_surface_cb: { userdata, processAlive in
                GhosttyRuntime.handleCloseSurface(userdata, processAlive: processAlive)
            }
        )

        guard let app = ghostty_app_new(&runtimeConfig, config) else {
            initializationError = GhosttySurfaceHostError.appCreationFailed.localizedDescription
            return
        }

        self.app = app
        let runtimeBits = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
        installObservers(runtimeBits: runtimeBits)
    }

    static func preferredConfigFileURLs(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let devHavenURLs = devHavenConfigFileURLs(
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL
        )
        if !devHavenURLs.isEmpty {
            return devHavenURLs
        }
        return standaloneGhosttyConfigFileURLs(
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL
        )
    }

    static func editableConfigFileURL(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let configURL = devHavenConfigFileURLs(
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL
        ).first {
            return configURL
        }
        if let configURL = standaloneGhosttyConfigFileURLs(
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL
        ).first {
            return configURL
        }
        return homeDirectoryURL
            .appending(path: ".devhaven", directoryHint: .isDirectory)
            .appending(path: "ghostty", directoryHint: .isDirectory)
            .appending(path: "config", directoryHint: .notDirectory)
    }

    @discardableResult
    static func ensureEditableConfigFile(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> URL {
        let configURL = editableConfigFileURL(
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL
        )
        if fileManager.fileExists(atPath: configURL.path) {
            return configURL
        }

        try fileManager.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard fileManager.createFile(atPath: configURL.path, contents: Data()) else {
            throw GhosttyConfigFileError.fileCreationFailed(configURL)
        }
        return configURL
    }

    private static func devHavenConfigFileURLs(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let configDirectoryURL = homeDirectoryURL
            .appending(path: ".devhaven", directoryHint: .isDirectory)
            .appending(path: "ghostty", directoryHint: .isDirectory)
        let candidates = [
            configDirectoryURL.appending(path: "config", directoryHint: .notDirectory),
            configDirectoryURL.appending(path: "config.ghostty", directoryHint: .notDirectory),
        ]
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }

    private static func standaloneGhosttyConfigFileURLs(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let configDirectoryURL = homeDirectoryURL
            .appending(path: "Library/Application Support/com.mitchellh.ghostty", directoryHint: .isDirectory)
        let candidates = [
            configDirectoryURL.appending(path: "config", directoryHint: .notDirectory),
            configDirectoryURL.appending(path: "config.ghostty", directoryHint: .notDirectory),
        ]
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }

    private static func loadPreferredConfigFiles(
        _ config: ghostty_config_t,
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        // 优先使用 DevHaven 自己的配置；如果用户还没为 DevHaven 单独建配置，
        // 则回退到既有 Ghostty 配置，避免升级后突然丢失主题/键位等用户习惯。
        for configURL in preferredConfigFileURLs(
            fileManager: fileManager,
            homeDirectoryURL: homeDirectoryURL
        ) {
            configURL.path.withCString { pointer in
                ghostty_config_load_file(config, pointer)
            }
        }
        ghostty_config_load_recursive_files(config)
    }

    deinit {
        shutdown()
    }

    func registerSurface(_ surface: ghostty_surface_t) -> SurfaceReference {
        let ref = SurfaceReference(surface)
        surfaceRefs.append(ref)
        surfaceRefs = surfaceRefs.filter(\.isValid)
        return ref
    }

    func unregisterSurface(_ ref: SurfaceReference) {
        ref.invalidate()
        surfaceRefs = surfaceRefs.filter(\.isValid)
    }

    func shutdown() {
        let center = NotificationCenter.default
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()

        if let app {
            ghostty_app_free(app)
            self.app = nil
        }

        if let config {
            ghostty_config_free(config)
            self.config = nil
        }
    }

    @MainActor
    func createSurface(
        for view: GhosttyTerminalSurfaceView,
        bridge: GhosttySurfaceBridge,
        request: WorkspaceTerminalLaunchRequest,
        extraEnvironment: [String: String]
    ) throws -> ghostty_surface_t {
        guard let app else {
            throw GhosttySurfaceHostError.appCreationFailed
        }

        let configuration = GhosttyTerminalSurfaceConfiguration(
            workingDirectory: request.projectPath,
            environmentVariables: extraEnvironment
        )

        let surface = try configuration.withCValue(view: view, bridge: bridge) { cConfig in
            guard let surface = ghostty_surface_new(app, &cConfig) else {
                throw GhosttySurfaceHostError.surfaceCreationFailed
            }
            return surface
        }

        bridge.surfaceView = view
        bridge.surface = surface
        return surface
    }

    private func installObservers(runtimeBits: UInt) {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                GhosttyRuntime.runtime(fromBits: runtimeBits)?.setAppFocus(true)
            }
        )
        observers.append(
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                GhosttyRuntime.runtime(fromBits: runtimeBits)?.setAppFocus(false)
            }
        )
        observers.append(
            center.addObserver(
                forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
                object: nil,
                queue: .main
            ) { _ in
                GhosttyRuntime.runtime(fromBits: runtimeBits)?.handleKeyboardSelectionDidChange()
            }
        )
    }

    private func setAppFocus(_ focused: Bool) {
        guard let app else { return }
        ghostty_app_set_focus(app, focused)
    }

    private func handleKeyboardSelectionDidChange() {
        guard let app else { return }
        ghostty_app_keyboard_changed(app)
    }

    private func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    private static func runtime(from userdata: UnsafeMutableRawPointer?) -> GhosttyRuntime? {
        guard let userdata else {
            return nil
        }
        return Unmanaged<GhosttyRuntime>.fromOpaque(userdata).takeUnretainedValue()
    }

    private static func runtime(fromBits bits: UInt?) -> GhosttyRuntime? {
        guard let bits else {
            return nil
        }
        return runtime(from: UnsafeMutableRawPointer(bitPattern: bits))
    }

    private static func bridge(from userdata: UnsafeMutableRawPointer?) -> GhosttySurfaceBridge? {
        guard let userdata else {
            return nil
        }
        return Unmanaged<GhosttySurfaceBridge>.fromOpaque(userdata).takeUnretainedValue()
    }

    private static func bridge(fromBits bits: UInt?) -> GhosttySurfaceBridge? {
        guard let bits else {
            return nil
        }
        return bridge(from: UnsafeMutableRawPointer(bitPattern: bits))
    }

    private static func bridge(fromSurface surface: ghostty_surface_t?) -> GhosttySurfaceBridge? {
        guard let surface, let userdata = ghostty_surface_userdata(surface) else {
            return nil
        }
        return bridge(from: userdata)
    }

    nonisolated private static func handleWakeup(_ userdata: UnsafeMutableRawPointer?) {
        let runtimeBits = userdata.map { UInt(bitPattern: $0) }
        DispatchQueue.main.async {
            runtime(fromBits: runtimeBits)?.tick()
        }
    }

    nonisolated private static func handleAction(
        _ app: ghostty_app_t?,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        _ = app
        guard target.tag == GHOSTTY_TARGET_SURFACE else {
            return false
        }
        guard let surfaceBridge = bridge(fromSurface: target.target.surface) else {
            return false
        }

        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                surfaceBridge.handleAction(target: target, action: action)
            }
        }

        let bridgeBits = target.target.surface
            .flatMap { ghostty_surface_userdata($0) }
            .map { UInt(bitPattern: $0) }
        DispatchQueue.main.async {
            if let bridge = bridge(fromBits: bridgeBits) {
                MainActor.assumeIsolated {
                    _ = bridge.handleAction(target: target, action: action)
                }
            }
        }
        return false
    }

    nonisolated private static func handleReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) {
        guard let bridge = bridge(from: userdata), let surface = bridge.surface else {
            return
        }
        let string = NSPasteboard.ghostty(location)?.getOpinionatedStringContents() ?? ""
        string.withCString { pointer in
            ghostty_surface_complete_clipboard_request(surface, pointer, state, false)
        }
    }

    nonisolated private static func handleConfirmReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        _ content: UnsafePointer<CChar>?,
        _ state: UnsafeMutableRawPointer?,
        _ request: ghostty_clipboard_request_e
    ) {
        _ = userdata
        _ = content
        _ = state
        _ = request
    }

    nonisolated private static func handleWriteClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        len: Int,
        _ confirmed: Bool
    ) {
        _ = confirmed
        guard len > 0, let content, bridge(from: userdata) != nil else {
            return
        }
        guard let pasteboard = NSPasteboard.ghostty(location) else {
            return
        }
        pasteboard.clearContents()
        for index in 0..<len {
            let item = content[index]
            guard let mime = item.mime, String(cString: mime) == "text/plain",
                  let data = item.data
            else {
                continue
            }
            pasteboard.setString(String(cString: data), forType: .string)
        }
    }

    nonisolated private static func handleCloseSurface(
        _ userdata: UnsafeMutableRawPointer?,
        processAlive: Bool
    ) {
        let bridgeBits = userdata.map { UInt(bitPattern: $0) }
        DispatchQueue.main.async {
            if let bridge = bridge(fromBits: bridgeBits) {
                MainActor.assumeIsolated {
                    bridge.closeSurface(processAlive: processAlive)
                }
            }
        }
    }
}
