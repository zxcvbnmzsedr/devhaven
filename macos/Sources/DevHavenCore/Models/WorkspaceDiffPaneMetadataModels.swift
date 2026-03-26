import Foundation

public struct WorkspaceDiffPaneCopyPayload: Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var value: String

    public init(
        id: String,
        label: String,
        value: String
    ) {
        self.id = id
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct WorkspaceDiffPaneMetadata: Equatable, Sendable {
    public var title: String
    public var path: String?
    public var oldPath: String?
    public var revision: String?
    public var hash: String?
    public var author: String?
    public var timestamp: String?
    public var tooltip: String?
    public var copyPayloads: [WorkspaceDiffPaneCopyPayload]

    public init(
        title: String,
        path: String? = nil,
        oldPath: String? = nil,
        revision: String? = nil,
        hash: String? = nil,
        author: String? = nil,
        timestamp: String? = nil,
        tooltip: String? = nil,
        copyPayloads: [WorkspaceDiffPaneCopyPayload] = []
    ) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.path = Self.sanitized(path)
        self.oldPath = Self.sanitized(oldPath)
        self.revision = Self.sanitized(revision)
        self.hash = Self.sanitized(hash)
        self.author = Self.sanitized(author)
        self.timestamp = Self.sanitized(timestamp)
        self.tooltip = Self.sanitized(tooltip)
        self.copyPayloads = copyPayloads
    }

    public var primaryDetails: [String] {
        [revision, hash].compactMap { Self.sanitized($0) }
    }

    public var secondaryDetails: [String] {
        [author, timestamp].compactMap { Self.sanitized($0) }
    }

    private static func sanitized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}
