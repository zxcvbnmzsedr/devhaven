import AppKit
import GhosttyKit

enum GhosttySurfaceMenuShortcutRoutingPolicy {
    static func shouldAttemptMenuBeforeBindings(for event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)
    }

    static func shouldAttemptMenuAfterBinding(_ flags: ghostty_binding_flags_e) -> Bool {
        let raw = flags.rawValue
        let isAll = (raw & GHOSTTY_BINDING_FLAGS_ALL.rawValue) != 0
        let isPerformable = (raw & GHOSTTY_BINDING_FLAGS_PERFORMABLE.rawValue) != 0
        let isConsumed = (raw & GHOSTTY_BINDING_FLAGS_CONSUMED.rawValue) != 0
        return !isAll && !isPerformable && isConsumed
    }
}
