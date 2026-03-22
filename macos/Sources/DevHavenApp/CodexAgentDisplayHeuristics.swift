import DevHavenCore

enum CodexAgentDisplayHeuristics {
    static func displayState(for visibleText: String) -> WorkspaceAgentState? {
        let normalizedText = visibleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return nil
        }
        if containsAnyMarker(in: normalizedText, markers: runningMarkers) {
            return .running
        }
        if containsAnyMarker(in: normalizedText, markers: waitingMarkers)
            || (normalizedText.contains("OpenAI Codex")
                && normalizedText.contains("model:")
                && normalizedText.contains("directory:")
                && !containsAnyMarker(in: normalizedText, markers: runningMarkers))
        {
            return .waiting
        }
        return nil
    }

    private static let runningMarkers = [
        "Working (",
        "esc to interrupt",
        "Starting MCP servers (",
    ]

    private static let waitingMarkers = [
        "Improve documentation in @filename",
        "Write tests for @filename",
        "/model to change",
    ]

    private static func containsAnyMarker(in text: String, markers: [String]) -> Bool {
        markers.contains { text.contains($0) }
    }
}
