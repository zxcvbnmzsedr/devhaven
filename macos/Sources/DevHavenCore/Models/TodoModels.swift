import Foundation

public struct TodoItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var done: Bool

    public init(id: String = UUID().uuidString, text: String, done: Bool) {
        self.id = id
        self.text = text
        self.done = done
    }
}

public enum TodoMarkdownCodec {
    public static func parse(_ content: String) -> [TodoItem] {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return content
            .split(whereSeparator: \ .isNewline)
            .compactMap { line in
                let text = String(line)
                guard let match = text.firstMatch(of: /^\s*[-*]\s+\[( |x|X)\]\s+(.*)$/) else {
                    return nil
                }
                let body = String(match.output.2).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty else {
                    return nil
                }
                return TodoItem(text: body, done: String(match.output.1).lowercased() == "x")
            }
    }

    public static func serialize(_ items: [TodoItem]) -> String {
        items
            .compactMap { item in
                let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    return nil
                }
                return "- [\(item.done ? "x" : " ")] \(text)"
            }
            .joined(separator: "\n")
    }
}
