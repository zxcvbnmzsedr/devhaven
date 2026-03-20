import AppKit

enum GhosttySurfaceMousePosition {
    static func map(localPoint: NSPoint, boundsHeight: CGFloat) -> NSPoint {
        NSPoint(x: localPoint.x, y: boundsHeight - localPoint.y)
    }
}
