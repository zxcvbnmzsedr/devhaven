import Foundation

final class GhosttySurfaceCallbackContext: @unchecked Sendable {
    private let lock = NSLock()
    private var bridge: GhosttySurfaceBridge?

    init(bridge: GhosttySurfaceBridge) {
        self.bridge = bridge
    }

    func activeBridge() -> GhosttySurfaceBridge? {
        lock.lock()
        defer { lock.unlock() }
        return bridge
    }

    func invalidate() {
        lock.lock()
        bridge = nil
        lock.unlock()
    }
}
