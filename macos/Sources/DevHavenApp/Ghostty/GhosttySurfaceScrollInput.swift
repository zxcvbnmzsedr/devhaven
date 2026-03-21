import AppKit
import GhosttyKit

struct GhosttySurfaceScrollInput {
    let deltaX: CGFloat
    let deltaY: CGFloat
    let mods: ghostty_input_scroll_mods_t

    static func make(
        deltaX: CGFloat,
        deltaY: CGFloat,
        hasPreciseScrollingDeltas: Bool,
        momentumPhase: NSEvent.Phase
    ) -> Self {
        var adjustedDeltaX = deltaX
        var adjustedDeltaY = deltaY
        if hasPreciseScrollingDeltas {
            adjustedDeltaX *= 2
            adjustedDeltaY *= 2
        }

        var rawMods: Int32 = 0
        if hasPreciseScrollingDeltas {
            rawMods |= 0b0000_0001
        }
        rawMods |= (momentumValue(for: momentumPhase) << 1)

        return Self(
            deltaX: adjustedDeltaX,
            deltaY: adjustedDeltaY,
            mods: ghostty_input_scroll_mods_t(rawMods)
        )
    }

    private static func momentumValue(for phase: NSEvent.Phase) -> Int32 {
        switch phase {
        case .began:
            return 1
        case .stationary:
            return 2
        case .changed:
            return 3
        case .ended:
            return 4
        case .cancelled:
            return 5
        case .mayBegin:
            return 6
        default:
            return 0
        }
    }
}
