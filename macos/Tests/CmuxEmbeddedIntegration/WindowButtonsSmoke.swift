import AppKit
import SwiftUI

/// Exercises the packaged embedded framework's local event monitors and native
/// traffic lights. Only this disposable window/shell receives generated events.
@MainActor
final class WindowButtonsSmoke: NSObject, NSApplicationDelegate, NSWindowDelegate {
    final class RecordingWindow: NSWindow {
        var dragCount = 0
        var zoomCount = 0
        override func performDrag(with event: NSEvent) { dragCount += 1 }
        override func zoom(_ sender: Any?) { zoomCount += 1 }
    }

    let store = CmuxEmbeddedHostStore()
    var window: RecordingWindow!
    var buttonCount = 0
    var closeCount = 0
    var allowClose = false
    var eventNumber = 0
    var originalCloseTarget: AnyObject?
    var originalCloseAction: Selector?

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = RecordingWindow(contentRect: NSRect(x: 200, y: 200, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "DevHaven window buttons regression"
        window.contentView = NSHostingView(rootView: CmuxEmbeddedHostView(
            workingDirectory: "/tmp", projects: [.init(path: "/tmp", name: "Window buttons")], hostStore: store).frame(width: 1100, height: 700))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.run() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { self.finish("timed out") }
    }

    func check(_ condition: Bool, _ message: String) {
        guard condition else { finish(message) }
        print("PASS: \(message)"); fflush(stdout)
    }

    func finish(_ failure: String? = nil) -> Never {
        print(failure.map { "FAIL: \($0)" } ?? "PASS: window buttons regression complete")
        fflush(stdout)
        store.destroyAll()
        exit(failure == nil ? 0 : 1)
    }

    @objc func recordButton(_ sender: Any?) { buttonCount += 1 }
    func windowShouldClose(_ sender: NSWindow) -> Bool { closeCount += 1; return allowClose }

    func click(at point: NSPoint, count: Int = 1, then next: @escaping @MainActor @Sendable () -> Void) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        eventNumber += 1
        let timestamp = ProcessInfo.processInfo.systemUptime
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: timestamp + (type == .leftMouseUp ? 0.05 : 0),
                windowNumber: window.windowNumber, context: nil, eventNumber: eventNumber,
                clickCount: count, pressure: type == .leftMouseUp ? 0 : 1)!
            NSApp.postEvent(event, atStart: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: next)
    }

    func center(_ button: NSButton) -> NSPoint {
        button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
    }

    func run() {
        window.delegate = self
        let close = window.standardWindowButton(.closeButton)!
        originalCloseTarget = close.target as AnyObject?
        originalCloseAction = close.action
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            let button = window.standardWindowButton(type)!
            button.target = self
            button.action = #selector(recordButton(_:))
        }
        verifyButton(0)
    }

    func verifyButton(_ index: Int) {
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        guard index < types.count else { verifyClose(); return }
        let button = window.standardWindowButton(types[index])!
        check(!button.isHiddenOrHasHiddenAncestor && button.isEnabled, "native button \(index) is available")
        let before = buttonCount
        click(at: center(button)) {
            self.check(self.buttonCount == before + 1, "native button \(index) receives single click")
            self.check(self.window.dragCount == 0 && self.window.zoomCount == 0, "button \(index) does not start titlebar drag/zoom")
            self.click(at: self.center(button), count: 2) {
                self.check(self.buttonCount == before + 2, "native button \(index) receives second click")
                self.check(self.window.dragCount == 0 && self.window.zoomCount == 0, "button \(index) bypasses titlebar double-click action")
                self.verifyButton(index + 1)
            }
        }
    }

    func verifyClose() {
        let close = window.standardWindowButton(.closeButton)!
        close.target = originalCloseTarget
        close.action = originalCloseAction
        click(at: center(close)) {
            self.check(self.closeCount == 1 && self.window.isVisible, "close reaches delegate and respects cancellation")
            self.verifyDrag()
        }
    }

    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    func verifyDrag() {
        let handles = descendants(window.contentView!).filter {
            $0.identifier?.rawValue == "cmux.titlebarDragHandle" && !$0.isHiddenOrHasHiddenAncestor
        }
        guard let handle = handles.max(by: { $0.bounds.width < $1.bounds.width }) else { finish("missing titlebar drag handle") }
        // Middle of the project title, well away from traffic lights and toolbar.
        let point = handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil)
        click(at: point) {
            self.check(self.window.dragCount == 1, "empty titlebar still starts window drag")
            self.allowClose = true
            self.click(at: self.center(self.window.standardWindowButton(.closeButton)!)) {
                self.check(self.closeCount == 2 && !self.window.isVisible, "confirmed native close closes the window")
                self.finish()
            }
        }
    }
}

@main
struct WindowButtonsSmokeMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = WindowButtonsSmoke()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
