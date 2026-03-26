import Foundation

struct CodexAgentDisplaySnapshot: Equatable, Sendable {
    static let windowLimit = 2048

    let recentTextWindow: String
    let lastActivityAt: Date

    init(recentTextWindow: String, lastActivityAt: Date) {
        self.recentTextWindow = recentTextWindow
        self.lastActivityAt = lastActivityAt
    }

    static func capture(
        from visibleText: String?,
        now: Date = Date(),
        windowLimit: Int = Self.windowLimit
    ) -> CodexAgentDisplaySnapshot? {
        guard let visibleText else {
            return nil
        }
        let trimmedText = visibleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }
        let recentTextWindow = String(trimmedText.suffix(windowLimit))
        return CodexAgentDisplaySnapshot(
            recentTextWindow: recentTextWindow,
            lastActivityAt: now
        )
    }
}
