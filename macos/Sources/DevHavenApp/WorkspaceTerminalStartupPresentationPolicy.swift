import Foundation

struct WorkspaceTerminalStartupPresentationPolicy {
    static func shouldShowOverlay(
        hasInitializationError: Bool,
        processState: GhosttySurfaceProcessState,
        hasSurfaceView: Bool
    ) -> Bool {
        guard !hasInitializationError else {
            return false
        }
        guard processState != .exited, processState != .failed else {
            return false
        }
        return !hasSurfaceView
    }
}
