import Foundation

public final class WorkspaceCLICommandStore: @unchecked Sendable {
    private let baseDirectoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        baseDirectoryURL: URL = LegacyCompatStore().cliControlV1DirectoryURL,
        fileManager: FileManager = .default
    ) {
        self.baseDirectoryURL = baseDirectoryURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public var requestsDirectoryURL: URL {
        baseDirectoryURL.appending(path: "requests", directoryHint: .isDirectory)
    }

    public var responsesDirectoryURL: URL {
        baseDirectoryURL.appending(path: "responses", directoryHint: .isDirectory)
    }

    public var serverFileURL: URL {
        baseDirectoryURL.appending(path: "server.json", directoryHint: .notDirectory)
    }

    public func ensureDirectoriesExist() throws {
        try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: requestsDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: responsesDirectoryURL, withIntermediateDirectories: true)
    }

    @discardableResult
    public func writeServerState(_ state: WorkspaceCLIServerState) throws -> URL {
        try ensureDirectoriesExist()
        try write(state, to: serverFileURL)
        return serverFileURL
    }

    public func loadServerState() throws -> WorkspaceCLIServerState? {
        guard fileManager.fileExists(atPath: serverFileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: serverFileURL)
        return try decoder.decode(WorkspaceCLIServerState.self, from: data)
    }

    public func removeServerState() throws {
        guard fileManager.fileExists(atPath: serverFileURL.path) else {
            return
        }
        try fileManager.removeItem(at: serverFileURL)
    }

    @discardableResult
    public func writeRequest(_ request: WorkspaceCLIRequestEnvelope) throws -> URL {
        try ensureDirectoriesExist()
        let url = requestsDirectoryURL.appending(path: requestFileName(for: request), directoryHint: .notDirectory)
        try write(request, to: url)
        return url
    }

    public func pendingRequests() throws -> [WorkspaceCLIQueuedRequest] {
        guard fileManager.fileExists(atPath: requestsDirectoryURL.path) else {
            return []
        }

        return try fileManager.contentsOfDirectory(
            at: requestsDirectoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let envelope = try? decoder.decode(WorkspaceCLIRequestEnvelope.self, from: data)
            else {
                try? fileManager.removeItem(at: url)
                return nil
            }
            return WorkspaceCLIQueuedRequest(fileURL: url, envelope: envelope)
        }
    }

    @discardableResult
    public func writeResponse(_ response: WorkspaceCLIResponseEnvelope) throws -> URL {
        try ensureDirectoriesExist()
        let url = responseFileURL(for: response.requestID)
        try write(response, to: url)
        return url
    }

    public func loadResponse(requestID: String) throws -> WorkspaceCLIResponseEnvelope? {
        let url = responseFileURL(for: requestID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(WorkspaceCLIResponseEnvelope.self, from: data)
    }

    public func responseFileURL(for requestID: String) -> URL {
        responsesDirectoryURL.appending(path: "\(requestID).json", directoryHint: .notDirectory)
    }

    public func removeRequest(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    public func removeResponse(requestID: String) throws {
        let url = responseFileURL(for: requestID)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    public func pruneResponses(olderThan interval: TimeInterval, now: Date = Date()) throws {
        guard interval > 0, fileManager.fileExists(atPath: responsesDirectoryURL.path) else {
            return
        }

        for url in try fileManager.contentsOfDirectory(
            at: responsesDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) where url.pathExtension == "json" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let modificationDate = values?.contentModificationDate ?? .distantPast
            guard now.timeIntervalSince(modificationDate) >= interval else {
                continue
            }
            try? fileManager.removeItem(at: url)
        }
    }

    private func requestFileName(for request: WorkspaceCLIRequestEnvelope) -> String {
        "\(fileTimestamp(for: request.createdAt))-\(request.requestID).json"
    }

    private func fileTimestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return formatter.string(from: date)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        let temporaryURL = url.deletingLastPathComponent()
            .appending(path: "\(url.lastPathComponent).tmp-\(UUID().uuidString)", directoryHint: .notDirectory)
        try data.write(to: temporaryURL, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: temporaryURL, to: url)
    }
}
