import AppKit

enum GhosttySurfaceFocusRequestPolicy {
    static func shouldRequestFocus(
        preferredFocus: Bool,
        wasPreferredFocus: Bool,
        isSurfaceFocused: Bool,
        currentEventType: NSEvent.EventType?
    ) -> Bool {
        guard preferredFocus else {
            return false
        }
        guard !wasPreferredFocus else {
            return false
        }
        guard !isSurfaceFocused else {
            return false
        }
        guard !isLivePointerDrag(eventType: currentEventType) else {
            return false
        }
        return true
    }

    private static func isLivePointerDrag(eventType: NSEvent.EventType?) -> Bool {
        switch eventType {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return true
        default:
            return false
        }
    }
}
