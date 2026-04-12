import SwiftUI
import AppKit
import DevHavenCore

enum NativeTheme {
    struct Palette {
        let window: NSColor
        let sidebar: NSColor
        let surface: NSColor
        let elevated: NSColor
        let panel: NSColor
        let border: NSColor
        let textPrimary: NSColor
        let textSecondary: NSColor
        let accent: NSColor
        let success: NSColor
        let warning: NSColor
        let danger: NSColor
        let heatmapLevels: [NSColor]
    }

    static let window = adaptiveColor(\.window)
    static let sidebar = adaptiveColor(\.sidebar)
    static let surface = adaptiveColor(\.surface)
    static let elevated = adaptiveColor(\.elevated)
    static let panel = adaptiveColor(\.panel)
    static let border = adaptiveColor(\.border)
    static let textPrimary = adaptiveColor(\.textPrimary)
    static let textSecondary = adaptiveColor(\.textSecondary)
    static let accent = adaptiveColor(\.accent)
    static let success = adaptiveColor(\.success)
    static let warning = adaptiveColor(\.warning)
    static let danger = adaptiveColor(\.danger)

    static func heatmapColor(level: Int) -> Color {
        let index = max(0, min(level, 4))
        return Color(nsColor: NSColor(name: nil) { appearance in
            resolvedPalette(for: appearance).heatmapLevels[index]
        })
    }

    static func preferredColorScheme(for mode: AppAppearanceMode) -> ColorScheme? {
        switch mode {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private static func adaptiveColor(_ keyPath: KeyPath<Palette, NSColor>) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            resolvedPalette(for: appearance)[keyPath: keyPath]
        })
    }

    private static func resolvedPalette(for appearance: NSAppearance) -> Palette {
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .aqua:
            return lightPalette
        default:
            return darkPalette
        }
    }

    private static let darkPalette = Palette(
        window: NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.10, alpha: 1),
        sidebar: NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1),
        surface: NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1),
        elevated: NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.15, alpha: 1),
        panel: NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.13, alpha: 1),
        border: NSColor(calibratedWhite: 1.0, alpha: 0.06),
        textPrimary: NSColor(calibratedWhite: 1.0, alpha: 0.96),
        textSecondary: NSColor(calibratedWhite: 1.0, alpha: 0.55),
        accent: NSColor(calibratedRed: 0.34, green: 0.33, blue: 1.0, alpha: 1),
        success: NSColor(calibratedRed: 0.19, green: 0.74, blue: 0.34, alpha: 1),
        warning: NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.24, alpha: 1),
        danger: NSColor(calibratedRed: 0.87, green: 0.25, blue: 0.31, alpha: 1),
        heatmapLevels: [
            NSColor(calibratedWhite: 1.0, alpha: 0.06),
            NSColor(calibratedRed: 0.11, green: 0.24, blue: 0.16, alpha: 1),
            NSColor(calibratedRed: 0.14, green: 0.39, blue: 0.22, alpha: 1),
            NSColor(calibratedRed: 0.18, green: 0.57, blue: 0.30, alpha: 1),
            NSColor(calibratedRed: 0.19, green: 0.74, blue: 0.34, alpha: 1)
        ]
    )

    private static let lightPalette = Palette(
        window: NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.99, alpha: 1),
        sidebar: NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.98, alpha: 1),
        surface: NSColor(calibratedRed: 0.985, green: 0.987, blue: 0.995, alpha: 1),
        elevated: NSColor(calibratedRed: 0.91, green: 0.94, blue: 0.98, alpha: 1),
        panel: NSColor(calibratedRed: 0.95, green: 0.965, blue: 0.99, alpha: 1),
        border: NSColor(calibratedRed: 0.20, green: 0.25, blue: 0.34, alpha: 0.12),
        textPrimary: NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.18, alpha: 0.96),
        textSecondary: NSColor(calibratedRed: 0.28, green: 0.33, blue: 0.43, alpha: 0.78),
        accent: NSColor(calibratedRed: 0.13, green: 0.36, blue: 0.96, alpha: 1),
        success: NSColor(calibratedRed: 0.14, green: 0.63, blue: 0.29, alpha: 1),
        warning: NSColor(calibratedRed: 0.86, green: 0.56, blue: 0.12, alpha: 1),
        danger: NSColor(calibratedRed: 0.82, green: 0.22, blue: 0.27, alpha: 1),
        heatmapLevels: [
            NSColor(calibratedRed: 0.84, green: 0.88, blue: 0.93, alpha: 0.7),
            NSColor(calibratedRed: 0.74, green: 0.86, blue: 0.77, alpha: 1),
            NSColor(calibratedRed: 0.53, green: 0.76, blue: 0.58, alpha: 1),
            NSColor(calibratedRed: 0.32, green: 0.64, blue: 0.41, alpha: 1),
            NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.31, alpha: 1)
        ]
    )
}
