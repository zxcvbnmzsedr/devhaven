import SwiftUI
import AppKit

enum NativeTheme {
    static let window = Color(nsColor: NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.10, alpha: 1))
    static let sidebar = Color(nsColor: NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1))
    static let surface = Color(nsColor: NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1))
    static let elevated = Color(nsColor: NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.15, alpha: 1))
    static let panel = Color(nsColor: NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.13, alpha: 1))
    static let border = Color.white.opacity(0.06)
    static let textPrimary = Color.white.opacity(0.96)
    static let textSecondary = Color.white.opacity(0.55)
    static let accent = Color(nsColor: NSColor(calibratedRed: 0.34, green: 0.33, blue: 1.0, alpha: 1))
    static let success = Color(nsColor: NSColor(calibratedRed: 0.19, green: 0.74, blue: 0.34, alpha: 1))
    static let warning = Color(nsColor: NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.24, alpha: 1))
    static let danger = Color(nsColor: NSColor(calibratedRed: 0.87, green: 0.25, blue: 0.31, alpha: 1))

    static func heatmapColor(level: Int) -> Color {
        switch level {
        case 4:
            return Color(nsColor: NSColor(calibratedRed: 0.19, green: 0.74, blue: 0.34, alpha: 1))
        case 3:
            return Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.57, blue: 0.30, alpha: 1))
        case 2:
            return Color(nsColor: NSColor(calibratedRed: 0.14, green: 0.39, blue: 0.22, alpha: 1))
        case 1:
            return Color(nsColor: NSColor(calibratedRed: 0.11, green: 0.24, blue: 0.16, alpha: 1))
        default:
            return Color.white.opacity(0.06)
        }
    }
}
