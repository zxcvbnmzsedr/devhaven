import AppKit
import SwiftUI

struct WindowActivityState: Equatable {
    let isKeyWindow: Bool
    let isVisible: Bool

    static let inactive = Self(isKeyWindow: false, isVisible: false)

    static func resolvedVisibility(
        isKeyWindow: Bool,
        isWindowVisible: Bool,
        isOccludedVisible: Bool
    ) -> Bool {
        // 新窗口首帧里，AppKit 可能已经把 window 设成 key/visible，
        // 但 `occlusionState` 还没来得及刷新；若此时误判成不可见，
        // Ghostty surface 会先吃到一次 false occlusion，直到后续额外 UI
        // 事件才恢复渲染。
        isWindowVisible && (isKeyWindow || isOccludedVisible)
    }
}

struct WindowFocusObserverView: NSViewRepresentable {
    let onWindowActivityChanged: (WindowActivityState) -> Void

    func makeNSView(context: Context) -> WindowFocusObserverNSView {
        let view = WindowFocusObserverNSView()
        view.onWindowActivityChanged = onWindowActivityChanged
        return view
    }

    func updateNSView(_ nsView: WindowFocusObserverNSView, context: Context) {
        nsView.onWindowActivityChanged = onWindowActivityChanged
    }
}

@MainActor
final class WindowFocusObserverNSView: NSView {
    var onWindowActivityChanged: (WindowActivityState) -> Void = { _ in }

    private var observers: [NSObjectProtocol] = []
    private weak var observedWindow: NSWindow?
    private var lastEmittedActivity: WindowActivityState?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateObservers()
    }

    private var activityState: WindowActivityState {
        guard let window else {
            return .inactive
        }
        return WindowActivityState(
            isKeyWindow: window.isKeyWindow,
            isVisible: WindowActivityState.resolvedVisibility(
                isKeyWindow: window.isKeyWindow,
                isWindowVisible: window.isVisible,
                isOccludedVisible: window.occlusionState.contains(.visible)
            )
        )
    }

    private func updateObservers() {
        if observedWindow === window {
            emitActivityIfNeeded()
            return
        }

        clearObservers()
        observedWindow = window
        guard let window else {
            emitActivityIfNeeded(force: true)
            return
        }

        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.emitActivityIfNeeded()
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.emitActivityIfNeeded()
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.emitActivityIfNeeded()
                }
            }
        )
        emitActivityIfNeeded(force: true)
    }

    private func emitActivityIfNeeded(force: Bool = false) {
        let activity = activityState
        if !force, activity == lastEmittedActivity {
            return
        }
        lastEmittedActivity = activity
        onWindowActivityChanged(activity)
    }

    private func clearObservers() {
        let center = NotificationCenter.default
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    isolated deinit {
        clearObservers()
    }
}
