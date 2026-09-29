import AppKit
import SwiftUI

/// Runs against the packaged framework, using real shell processes and Ghostty
/// key events. No cmux AppDelegate is created, matching the embedding contract.
@MainActor
@main
struct TerminalExitSmoke: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    @State private var store = CmuxEmbeddedHostStore()
    @State private var closedPaths: [String] = []
    @State private var generation = 0
    private let firstPath = "/tmp"
    private let secondPath = "/private/tmp"

    var body: some Scene {
        WindowGroup("DevHaven terminal exit regression") {
            CmuxEmbeddedHostView(
                workingDirectory: firstPath,
                projects: [.init(path: firstPath, name: "Exit regression")],
                hostStore: store
            )
            .id(generation)
            .frame(width: 1100, height: 700)
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DevHaven.CmuxEmbedded.ClosedProject"))) {
                if let path = $0.object as? String { closedPaths.append(path) }
            }
            .onAppear {
                guard generation == 0 else { return }
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { startWhenActive() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 90) { fail("timed out") }
            }
        }
        .commands { CmuxEmbeddedWorkspaceCommands(isWorkspacePresented: true) }
    }

    func field(_ object: Any, _ name: String) -> Any? {
        Mirror(reflecting: object).children.first(where: { $0.label == name })?.value
    }

    func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    var window: NSWindow {
        NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible })!
    }

    var host: NSView {
        descendants(window.contentView!).first {
            String(reflecting: type(of: $0)).contains("CmuxEmbeddedHostView") && field($0, "tabManager") != nil
        }!
    }

    var panelCounts: [Int] {
        guard let manager = field(host, "tabManager"), let byId = field(manager, "workspacesById") else { return [-1] }
        return Mirror(reflecting: byId).children.map { entry in
            guard let workspace = field(entry.value, "value"), let tree = field(workspace, "paneTree"),
                  let panels = field(tree, "_panels") ?? field(tree, "panels") else { return -1 }
            return Mirror(reflecting: panels).children.count
        }.sorted()
    }

    func check(_ condition: Bool, _ message: String) {
        if !condition { fail("\(message); panels=\(panelCounts), closed=\(closedPaths)") }
        print("PASS: \(message)")
        fflush(stdout)
    }

    func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        fflush(stdout)
        store.destroyAll()
        exit(1)
    }

    func later(_ action: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: action)
    }

    func controlD() {
        window.makeKeyAndOrderFront(nil)
        guard let surface = descendants(window.contentView!.superview ?? window.contentView!).last(where: {
            String(reflecting: type(of: $0)).hasSuffix(".GhosttyNSView") &&
                !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 1 && $0.bounds.height > 1
        }) else {
            for view in descendants(window.contentView!.superview ?? window.contentView!) {
                print("view=\(type(of: view)) hidden=\(view.isHiddenOrHasHiddenAncestor) frame=\(view.frame)")
            }
            fail("missing visible terminal")
        }
        check(window.makeFirstResponder(surface), "terminal accepts keyboard focus")
        guard let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "\u{04}", charactersIgnoringModifiers: "d", isARepeat: false, keyCode: 2),
              let up = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [.control],
            timestamp: ProcessInfo.processInfo.systemUptime + 0.001, windowNumber: window.windowNumber,
            context: nil, characters: "\u{04}", charactersIgnoringModifiers: "d", isARepeat: false, keyCode: 2)
        else { fail("key event creation") }
        NSApp.sendEvent(down)
        NSApp.sendEvent(up)
    }

    func updateProjects() {
        typealias Update = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void
        let handle = dlopen("@rpath/CmuxEmbedded.framework/CmuxEmbedded", RTLD_NOW)!
        let update = unsafeBitCast(dlsym(handle, "cmux_embedded_projects_update"), to: Update.self)
        let json = """
        {"projects":[{"path":"\(firstPath)","name":"First"},{"path":"\(secondPath)","name":"Second"}],"activePath":"\(secondPath)"}
        """
        json.withCString { update(Unmanaged.passUnretained(host).toOpaque(), $0) }
    }

    func startWhenActive() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        guard window.isKeyWindow else {
            print("waiting for activation: active=\(NSApp.isActive) canBecomeKey=\(window.canBecomeKey)")
            fflush(stdout)
            later { startWhenActive() }
            return
        }
        run()
    }

    func run() {
        window.makeKeyAndOrderFront(nil)
        print("windows=\(NSApp.windows.map { ($0.title, $0.isKeyWindow, $0.isVisible) }) hostWindow=\(String(describing: host.window?.title))")
        check(panelCounts == [1], "one initial shell")
        check(CmuxEmbeddedWorkspaceActions.perform(.splitRight), "create split")
        later {
            check(panelCounts == [2], "two live shells")
            controlD()
            later {
                check(panelCounts == [1] && closedPaths.isEmpty, "Ctrl+D closes only the exited split")
                updateProjects()
                later {
                    check(panelCounts == [1, 1], "two independent projects")
                    controlD()
                    later {
                        check(panelCounts == [1] && closedPaths == [secondPath], "Ctrl+D closes the addressed project and preserves the other")
                        controlD()
                        later {
                            check(panelCounts.isEmpty && Set(closedPaths) == Set([firstPath, secondPath]), "last shell exit clears the session for a fresh reopen")
                            store.destroyAll()
                            generation += 1
                            later {
                                check(panelCounts == [1], "reopening creates a fresh live terminal")
                                controlD()
                                // The child-exit callback is asynchronous. Suspend the
                                // host now, as returning home does, before it is delivered.
                                typealias Suspend = @convention(c) (UnsafeMutableRawPointer?) -> Void
                                let handle = dlopen("@rpath/CmuxEmbedded.framework/CmuxEmbedded", RTLD_NOW)!
                                let suspend = unsafeBitCast(dlsym(handle, "cmux_embedded_host_view_suspend"), to: Suspend.self)
                                suspend(Unmanaged.passUnretained(host).toOpaque())
                                later {
                                    check(panelCounts.isEmpty && closedPaths.count == 3, "pending shell exit cleans up a suspended host")
                                    store.destroyAll()
                                    print("PASS: terminal exit regression complete")
                                    fflush(stdout)
                                    exit(0)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
