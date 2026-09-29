import AppKit
import Darwin
import SwiftUI

struct CmuxEmbeddedProject: Encodable, Equatable {
    let path: String
    let name: String
}

private struct CmuxEmbeddedProjectsSnapshot: Encodable, Equatable {
    let projects: [CmuxEmbeddedProject]
    let activePath: String?
}

/// C ABI exposed by the cmux embedded framework.
///
/// Keeping this boundary C based is intentional: importing the Swift module
/// would make DevHaven's SwiftPM target resolve cmux's entire private package
/// graph just to host one view.
@MainActor
private enum CmuxEmbeddedHostBridge {
    private typealias CreateFunction = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?
    private typealias DestroyFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias SuspendFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias CloseCurrentPanelFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias PerformCommandFunction = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Bool
    private typealias UpdateProjectsFunction = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void
    private static var activeHostPointer: UnsafeMutableRawPointer?
    private static var lastProjectsSnapshot: CmuxEmbeddedProjectsSnapshot?
    private static var lastProjectsHostPointer: UnsafeMutableRawPointer?

    private static let handle: UnsafeMutableRawPointer? = "@rpath/CmuxEmbedded.framework/CmuxEmbedded".withCString {
        dlopen($0, RTLD_NOW)
    }

    static func create(_ workingDirectory: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
        guard let function: CreateFunction = symbol("cmux_embedded_host_view_create", as: CreateFunction.self) else {
            return nil
        }
        return function(workingDirectory)
    }

    static func destroy(_ hostPointer: UnsafeMutableRawPointer?) {
        guard let function: DestroyFunction = symbol("cmux_embedded_host_view_destroy", as: DestroyFunction.self) else {
            return
        }
        function(hostPointer)
        if lastProjectsHostPointer == hostPointer {
            lastProjectsHostPointer = nil
            lastProjectsSnapshot = nil
        }
    }

    static func suspend(_ hostPointer: UnsafeMutableRawPointer) {
        guard let function: SuspendFunction = symbol("cmux_embedded_host_view_suspend", as: SuspendFunction.self) else {
            return
        }
        function(hostPointer)
    }

    static func activate(_ hostPointer: UnsafeMutableRawPointer) {
        activeHostPointer = hostPointer
    }

    static func closeCurrentPanel() {
        guard let activeHostPointer,
              let function: CloseCurrentPanelFunction = symbol(
                "cmux_embedded_host_view_close_current_panel",
                as: CloseCurrentPanelFunction.self
              ) else { return }
        function(activeHostPointer)
    }

    static func perform(_ command: CmuxEmbeddedWorkspaceCommand) -> Bool {
        guard let activeHostPointer,
              let function: PerformCommandFunction = symbol(
                "cmux_embedded_host_view_perform_command",
                as: PerformCommandFunction.self
              ) else { return false }
        return function(activeHostPointer, command.rawValue)
    }

    static func deactivate(_ hostPointer: UnsafeMutableRawPointer) {
        if activeHostPointer == hostPointer {
            activeHostPointer = nil
        }
    }

    static func updateProjects(_ projects: [CmuxEmbeddedProject], activePath: String?, hostPointer: UnsafeMutableRawPointer) {
        let snapshot = CmuxEmbeddedProjectsSnapshot(projects: projects, activePath: activePath)
        guard snapshot != lastProjectsSnapshot || hostPointer != lastProjectsHostPointer else { return }
        guard
              let function: UpdateProjectsFunction = symbol(
                "cmux_embedded_projects_update",
                as: UpdateProjectsFunction.self
              ),
              let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else { return }
        json.withCString { function(hostPointer, $0) }
        lastProjectsSnapshot = snapshot
        lastProjectsHostPointer = hostPointer
    }

    private static func symbol<T>(_ name: String, as: T.Type) -> T? {
        guard let handle else { return nil }
        return name.withCString { symbolName in
            guard let address = dlsym(handle, symbolName) else { return nil }
            return unsafeBitCast(address, to: T.self)
        }
    }
}

/// Owns cmux sessions independently of the currently displayed SwiftUI page.
/// Returning home detaches the view; closing its DevHaven session releases it.
@MainActor
final class CmuxEmbeddedHostStore {
    private struct Entry {
        let pointer: UnsafeMutableRawPointer
        var lease: UUID?
        var shouldDestroy = false
    }

    private var entry: Entry?

    func mount(workingDirectory: String?) -> (pointer: UnsafeMutableRawPointer, lease: UUID)? {
        let lease = UUID()
        if var entry {
            entry.lease = lease
            entry.shouldDestroy = false
            self.entry = entry
            return (entry.pointer, lease)
        }

        let pointer: UnsafeMutableRawPointer?
        if let workingDirectory {
            pointer = workingDirectory.withCString { CmuxEmbeddedHostBridge.create($0) }
        } else {
            pointer = CmuxEmbeddedHostBridge.create(nil)
        }
        guard let pointer else { return nil }
        entry = Entry(pointer: pointer, lease: lease)
        return (pointer, lease)
    }

    func unmount(workingDirectory: String?, lease: UUID) {
        guard var entry, entry.lease == lease else { return }
        CmuxEmbeddedHostBridge.suspend(entry.pointer)
        CmuxEmbeddedHostBridge.deactivate(entry.pointer)
        entry.lease = nil
        if entry.shouldDestroy {
            self.entry = nil
            CmuxEmbeddedHostBridge.destroy(entry.pointer)
        } else {
            self.entry = entry
        }
    }

    func retainSessions(at projectPaths: Set<String>) {
        guard projectPaths.isEmpty, var entry else { return }
        if entry.lease != nil {
            entry.shouldDestroy = true
            self.entry = entry
        } else {
            self.entry = nil
            CmuxEmbeddedHostBridge.destroy(entry.pointer)
        }
    }

    func destroyAll() {
        guard let entry else { return }
        self.entry = nil
        CmuxEmbeddedHostBridge.deactivate(entry.pointer)
        CmuxEmbeddedHostBridge.destroy(entry.pointer)
    }
}

struct CmuxEmbeddedHostView: NSViewRepresentable {
    let workingDirectory: String?
    let projects: [CmuxEmbeddedProject]
    let hostStore: CmuxEmbeddedHostStore

    func makeNSView(context: Context) -> NSView {
        guard let mounted = hostStore.mount(workingDirectory: workingDirectory) else {
            return CmuxEmbeddedUnavailableView()
        }

        let hostView = Unmanaged<NSView>.fromOpaque(mounted.pointer).takeUnretainedValue()
        context.coordinator.workingDirectory = workingDirectory
        context.coordinator.lease = mounted.lease
        context.coordinator.hostPointer = mounted.pointer
        context.coordinator.hostStore = hostStore
        CmuxEmbeddedHostBridge.activate(mounted.pointer)
        CmuxEmbeddedHostBridge.updateProjects(projects, activePath: workingDirectory, hostPointer: mounted.pointer)
        return hostView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let pointer = context.coordinator.hostPointer else { return }
        CmuxEmbeddedHostBridge.updateProjects(projects, activePath: workingDirectory, hostPointer: pointer)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        guard let lease = coordinator.lease else { return }
        coordinator.lease = nil
        coordinator.hostStore?.unmount(workingDirectory: coordinator.workingDirectory, lease: lease)
    }

    @MainActor
    final class Coordinator {
        var workingDirectory: String?
        var lease: UUID?
        var hostPointer: UnsafeMutableRawPointer?
        var hostStore: CmuxEmbeddedHostStore?
    }
}

@MainActor
enum CmuxEmbeddedWorkspaceActions {
    @discardableResult
    static func perform(_ command: CmuxEmbeddedWorkspaceCommand) -> Bool {
        CmuxEmbeddedHostBridge.perform(command)
    }

    static func closeCurrentPanel() {
        CmuxEmbeddedHostBridge.closeCurrentPanel()
    }
}

private final class CmuxEmbeddedUnavailableView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let message = NSTextField(wrappingLabelWithString: "无法加载 cmux 内嵌界面，请检查 CmuxEmbedded.framework 是否已随 DevHaven 构建并打包。")
        message.alignment = .center
        message.translatesAutoresizingMaskIntoConstraints = false
        addSubview(message)
        NSLayoutConstraint.activate([
            message.centerXAnchor.constraint(equalTo: centerXAnchor),
            message.centerYAnchor.constraint(equalTo: centerYAnchor),
            message.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            message.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CmuxEmbeddedUnavailableView does not support NSCoder initialization")
    }
}
