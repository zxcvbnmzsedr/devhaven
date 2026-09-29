import AppKit
import SwiftUI

/// Runs against the packaged framework without cmux's standalone AppDelegate.
/// Sends AppKit events to a real terminal view and reads Ghostty's selection.
@MainActor
@main
struct TerminalSelectionSmoke: App {
    @State private var store = CmuxEmbeddedHostStore()
    @State private var activePath = "/tmp"
    @State private var projects = [CmuxEmbeddedProject(path: "/tmp", name: "Selection first")]
    @State private var generation = 0
    @State private var started = false
    private let marker = "DEVHAVEN_MOUSE_SELECTION_TEST"

    var body: some Scene {
        WindowGroup("DevHaven terminal selection regression") {
            CmuxEmbeddedHostView(workingDirectory: activePath, projects: projects, hostStore: store)
                .id(generation)
                .frame(width: 1100, height: 700)
                .onAppear {
                    guard !started else { return }
                    started = true
                    later { run() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 60) { fail("timed out") }
                }
        }
    }

    func later(_ action: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // Allow the user to work in another app between assertions, then
            // let cmux's own key-window observer restore its selected pane.
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: action)
        }
    }

    func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        fflush(stdout)
        store.destroyAll()
        exit(1)
    }

    func check(_ condition: Bool, _ message: String) {
        guard condition else { fail(message) }
        print("PASS: \(message)")
        fflush(stdout)
    }

    var window: NSWindow { NSApp.windows.first { $0.contentView != nil && $0.isVisible }! }

    func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    var terminals: [NSView] {
        descendants(window.contentView!.superview ?? window.contentView!).filter {
            String(reflecting: type(of: $0)).hasSuffix(".GhosttyNSView") &&
                !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 10 && $0.bounds.height > 10
        }
    }

    var focusedTerminal: NSView {
        guard let view = window.firstResponder as? NSView,
              terminals.contains(where: { $0 === view }) else {
            fail("automatic focus did not reach the active terminal: \(String(describing: window.firstResponder))")
        }
        return view
    }

    func event(_ type: NSEvent.EventType, in view: NSView, x: CGFloat, y: CGFloat) -> NSEvent {
        let local = NSPoint(x: x, y: view.isFlipped ? y : view.bounds.height - y)
        return NSEvent.mouseEvent(with: type, location: view.convert(local, to: nil),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
    }

    func verifySelection(_ label: String, then next: @escaping @MainActor @Sendable () -> Void) {
        let view = focusedTerminal
        // Only the disposable smoke shell receives this command. Erase its screen
        // so selection coordinates do not depend on the user's prompt/startup text.
        view.insertText("printf '\\033[2J\\033[H\(marker)\\n'\n")
        later {
            check(window.firstResponder === view, "\(label): focus remains on the active terminal")
            view.mouseDown(with: event(.leftMouseDown, in: view, x: 1, y: 10))
            view.mouseDragged(with: event(.leftMouseDragged, in: view, x: min(480, view.bounds.width - 2), y: 36))
            view.mouseUp(with: event(.leftMouseUp, in: view, x: min(480, view.bounds.width - 2), y: 36))
            let selected = view.accessibilitySelectedText() ?? ""
            check(selected.contains(marker), "\(label): mouse drag selects the printed marker (selected=\(selected.debugDescription))")
            next()
        }
    }

    func run() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        later {
            verifySelection("single terminal") {
                check(CmuxEmbeddedWorkspaceActions.perform(.splitRight), "split command accepted")
                later {
                    check(terminals.count == 2, "two terminal panes are visible")
                    verifySelection("new split") {
                        let firstPane = terminals.first { $0 !== focusedTerminal }!
                        firstPane.mouseDown(with: event(.leftMouseDown, in: firstPane, x: 20, y: 20))
                        firstPane.mouseUp(with: event(.leftMouseUp, in: firstPane, x: 20, y: 20))
                        later {
                            check(window.firstResponder === firstPane, "pointer click focuses the other split")
                            verifySelection("other split") {
                                projects.append(.init(path: "/private/tmp", name: "Selection second"))
                                activePath = "/private/tmp"
                                later {
                                    check(terminals.count == 1, "background project's panes are hidden")
                                    verifySelection("second project") {
                                        activePath = "/tmp"
                                        later {
                                            verifySelection("return to first project") {
                                                generation += 1
                                                later {
                                                    verifySelection("host remount") {
                                                        store.destroyAll()
                                                        print("PASS: terminal selection regression complete")
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
                }
            }
        }
    }
}
