import Foundation

public enum WorkspaceTerminalPaneTitlePolicy {
    public static func defaultTitle(
        for workingDirectory: String?,
        fallback: String
    ) -> String {
        resolveRuntimeTitle(currentTitle: fallback, runtimeTitle: workingDirectory)
    }

    public static func displayTitle(
        runtimeTitle: String?,
        workingDirectory: String?,
        fallback: String
    ) -> String {
        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedFallback = trimmedFallback.isEmpty ? fallback : trimmedFallback

        if let trimmedTitle = runtimeTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedTitle.isEmpty {
            return resolveRuntimeTitle(currentTitle: resolvedFallback, runtimeTitle: trimmedTitle)
        }

        if let workingDirectoryDisplay = displayPath(for: workingDirectory) {
            return workingDirectoryDisplay
        }

        return resolvedFallback
    }

    public static func resolveRuntimeTitle(
        currentTitle: String,
        runtimeTitle: String?
    ) -> String {
        guard let trimmed = runtimeTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return currentTitle
        }
        if let displayPath = normalizedPathDisplay(for: trimmed) {
            return displayPath
        }
        return trimmed
    }

    public static func displayPath(for rawPath: String?) -> String? {
        guard let trimmed = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        if trimmed == "~" || trimmed.hasPrefix("~/") {
            return trimmed
        }
        guard trimmed.hasPrefix("/") else {
            return nil
        }
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if trimmed == homePath {
            return "~"
        }
        if trimmed.hasPrefix(homePath + "/") {
            return "~" + String(trimmed.dropFirst(homePath.count))
        }
        return trimmed
    }

    public static func matchesWorkingDirectoryDisplay(
        title: String?,
        workingDirectory: String?
    ) -> Bool {
        guard let titleDisplay = normalizedPathDisplay(for: title),
              let workingDirectoryDisplay = displayPath(for: workingDirectory) else {
            return false
        }
        return titleDisplay == workingDirectoryDisplay
    }

    private static func normalizedPathDisplay(for rawTitle: String?) -> String? {
        displayPath(for: rawTitle) ?? promptDecoratedPathDisplay(for: rawTitle)
    }

    private static func promptDecoratedPathDisplay(for rawTitle: String?) -> String? {
        guard let trimmed = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.contains("@") else {
            return nil
        }
        if let hostSeparator = trimmed.firstIndex(of: ":") {
            let suffix = trimmed[trimmed.index(after: hostSeparator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let display = displayPath(for: suffix) {
                return display
            }
        }
        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let candidate = tokens.reversed().first(where: { displayPath(for: $0) != nil }),
              candidate != trimmed else {
            return nil
        }
        return displayPath(for: candidate)
    }

}
