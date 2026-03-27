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
        previous: CodexAgentDisplaySnapshot? = nil,
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
        let lastActivityAt = previous?.recentTextWindow == recentTextWindow
            ? (previous?.lastActivityAt ?? now)
            : now
        return CodexAgentDisplaySnapshot(
            recentTextWindow: recentTextWindow,
            lastActivityAt: lastActivityAt
        )
    }
}
