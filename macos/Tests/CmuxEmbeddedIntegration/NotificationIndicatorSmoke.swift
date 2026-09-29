import AppKit
import SwiftUI

/// Runs against the packaged framework without cmux's standalone AppDelegate.
/// Sends a real shell BEL and AppKit input, then inspects the persistent ring layer.
@MainActor
@main
struct NotificationIndicatorSmoke: App {
    @State private var store = CmuxEmbeddedHostStore()
    @State private var activePath = "/tmp"
    @State private var projects = [CmuxEmbeddedProject(path: "/tmp", name: "Notification regression")]
    @State private var started = false

    var body: some Scene {
        WindowGroup("DevHaven notification indicator regression") {
            CmuxEmbeddedHostView(workingDirectory: activePath, projects: projects, hostStore: store)
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

    func notificationRing(in terminal: NSView) -> CAShapeLayer {
        var parent = terminal.superview
        while let view = parent {
            if String(reflecting: type(of: view)).hasSuffix(".GhosttySurfaceScrollView") {
                // The persistent ring uses a 3pt glow; the independent 0.9s
                // focus flash uses 6pt. Do not mistake a flash for unread state.
                let rings = view.subviews.flatMap { $0.layer?.sublayers ?? [] }
                    .compactMap { $0 as? CAShapeLayer }
                    .filter { $0.shadowRadius == 3 && $0.lineWidth == 2.5 }
                check(rings.count == 1, "persistent notification ring located")
                return rings[0]
            }
            parent = view.superview
        }
        fail("terminal host not found")
    }

    func click(_ view: NSView) {
        view.mouseDown(with: event(.leftMouseDown, in: view, x: 20, y: 20))
        view.mouseUp(with: event(.leftMouseUp, in: view, x: 20, y: 20))
    }

    func run() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        later {
            let first = focusedTerminal
            check(CmuxEmbeddedWorkspaceActions.perform(.splitRight), "split command accepted")
            later {
                check(terminals.count == 2, "two terminal panes are visible")
                let second = focusedTerminal
                check(first !== second, "new pane owns input")
                // This is a disposable shell. Writing to the first surface does
                // not move keyboard focus from the second surface. Delay BEL
                // until injected input has drained so its accepted-input callback
                // cannot race with the notification being asserted below.
                first.insertText("sleep 0.5; printf '\\a'\n")
                later {
                    let ring = notificationRing(in: first)
                    check(ring.opacity == 1, "background BEL creates a persistent unread ring")
                    check(window.firstResponder === second, "background BEL does not steal focus")
                    second.insertText(" ")
                    later {
                        check(ring.opacity == 1, "input in another pane preserves the unread ring")
                        click(first)
                        later {
                            check(window.firstResponder === first, "click focuses the unread pane")
                            check(ring.opacity == 0, "click clears the persistent unread ring")
                            first.insertText("sleep 0.5; printf '\\a'\n")
                            later {
                                check(ring.opacity == 0, "BEL in the focused terminal does not mark it unread")
                                // Repeat the background path, clearing via input.
                                click(second)
                                first.insertText("sleep 0.5; printf '\\a'\n")
                                later {
                                    check(ring.opacity == 1, "second background BEL marks the pane unread")
                                    first.insertText(" ")
                                    later {
                                        check(ring.opacity == 0, "explicit terminal input clears unread state")
                                        store.destroyAll()
                                        print("PASS: notification indicator regression complete")
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
