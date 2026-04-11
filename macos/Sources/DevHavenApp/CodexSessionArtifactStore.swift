import Foundation
import Darwin
import DevHavenCore

struct CodexSessionArtifactSnapshot: Equatable, Sendable {
    let sessionID: String
    let threadTitle: String?
    let lastActivityAt: Date?
    let lastAssistantSummary: String?
    let lastTaskCompleteSummary: String?
    let lastTaskCompleteAt: Date?
    let sessionFileURL: URL?

    func preferredSummary(for signalState: WorkspaceAgentState) -> String? {
        switch signalState {
        case .waiting:
            return lastTaskCompleteSummary ?? lastAssistantSummary ?? threadTitle
        case .running, .completed, .failed, .idle, .unknown:
            return lastAssistantSummary ?? lastTaskCompleteSummary ?? threadTitle
        }
    }
}

final class CodexSessionArtifactStore {
    typealias ChangeHandler = @Sendable ([String: CodexSessionArtifactSnapshot]) -> Void

    private struct SessionIndexRecord: Equatable, Sendable {
        var sessionID: String
        var threadTitle: String?
        var updatedAt: Date?
    }

    private struct TranscriptArtifact: Equatable, Sendable {
        var fallbackThreadTitle: String?
        var lastActivityAt: Date?
        var lastAssistantSummary: String?
        var lastTaskCompleteSummary: String?
        var lastTaskCompleteAt: Date?
    }

    private struct CachedIndexSnapshot: Sendable {
        var recordsBySessionID: [String: SessionIndexRecord]
        var modificationDate: Date?
        var fileSize: Int?
    }

    private struct CachedTranscriptSnapshot: Sendable {
        var fileURL: URL
        var artifact: TranscriptArtifact
        var modificationDate: Date?
        var fileSize: Int?
    }

    private struct SnapshotReloadOutcome: Sendable {
        var snapshots: [String: CodexSessionArtifactSnapshot]
        var didChange: Bool
    }

    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "DevHavenApp.CodexSessionArtifactStore")
    private let queueSpecificKey = DispatchSpecificKey<UInt8>()
    private let queueSpecificValue: UInt8 = 1
    private let reloadDebounceNanoseconds: UInt64
    private let periodicReloadInterval: TimeInterval
    private let transcriptPrefixReadLimit: Int
    private let transcriptSuffixReadLimit: Int

    let codexHomeURL: URL
    let sessionIndexURL: URL
    let sessionsRootURL: URL

    var onSnapshotsChange: ChangeHandler?
    private(set) var snapshotsBySessionID: [String: CodexSessionArtifactSnapshot] = [:]

    private var trackedSessionIDs: Set<String> = []
    private var monitorSourcesByDirectoryPath: [String: DispatchSourceFileSystemObject] = [:]
    private var monitorFileDescriptorsByDirectoryPath: [String: Int32] = [:]
    private var sweepTimer: DispatchSourceTimer?
    private var pendingReloadWorkItem: DispatchWorkItem?
    private var cachedIndexSnapshot: CachedIndexSnapshot?
    private var cachedTranscriptSnapshotsBySessionID: [String: CachedTranscriptSnapshot] = [:]
    private var transcriptURLBySessionID: [String: URL] = [:]

    init(
        codexHomeURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true),
        fileManager: FileManager = .default,
        reloadDebounceNanoseconds: UInt64 = 80_000_000,
        periodicReloadInterval: TimeInterval = 2,
        transcriptPrefixReadLimit: Int = 64 * 1024,
        transcriptSuffixReadLimit: Int = 128 * 1024
    ) {
        self.codexHomeURL = codexHomeURL
        self.sessionIndexURL = codexHomeURL.appendingPathComponent("session_index.jsonl", isDirectory: false)
        self.sessionsRootURL = codexHomeURL.appendingPathComponent("sessions", isDirectory: true)
        self.fileManager = fileManager
        self.reloadDebounceNanoseconds = reloadDebounceNanoseconds
        self.periodicReloadInterval = periodicReloadInterval
        self.transcriptPrefixReadLimit = max(1, transcriptPrefixReadLimit)
        self.transcriptSuffixReadLimit = max(1, transcriptSuffixReadLimit)
        self.queue.setSpecific(key: queueSpecificKey, value: queueSpecificValue)
    }

    deinit {
        stop()
    }

    var currentSnapshots: [String: CodexSessionArtifactSnapshot] {
        syncOnQueueIfNeeded { snapshotsBySessionID }
    }

    func syncTrackedSessionIDs(_ sessionIDs: Set<String>) {
        let normalizedSessionIDs = Set(
            sessionIDs.compactMap {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        )

        let outcome = syncOnQueueIfNeeded { () -> SnapshotReloadOutcome? in
            if normalizedSessionIDs == trackedSessionIDs {
                return nil
            }

            trackedSessionIDs = normalizedSessionIDs
            cachedTranscriptSnapshotsBySessionID = cachedTranscriptSnapshotsBySessionID.filter {
                normalizedSessionIDs.contains($0.key)
            }
            transcriptURLBySessionID = transcriptURLBySessionID.filter {
                normalizedSessionIDs.contains($0.key)
            }

            if normalizedSessionIDs.isEmpty {
                let didChange = !snapshotsBySessionID.isEmpty
                snapshotsBySessionID = [:]
                cachedIndexSnapshot = nil
                syncDirectoryMonitors(watching: [])
                stopSweepTimer()
                return SnapshotReloadOutcome(
                    snapshots: snapshotsBySessionID,
                    didChange: didChange
                )
            }

            installSweepTimerIfNeeded()
            let outcome = try? reload()
            return outcome
        }

        if let outcome, outcome.didChange {
            notifyChange(outcome.snapshots)
        }
    }

    func stop() {
        syncOnQueueIfNeeded {
            pendingReloadWorkItem?.cancel()
            pendingReloadWorkItem = nil
            syncDirectoryMonitors(watching: [])
            stopSweepTimer()
        }
    }

    @discardableResult
    func reloadForTesting() throws -> [String: CodexSessionArtifactSnapshot] {
        let outcome = try reload()
        if outcome.didChange {
            notifyChange(outcome.snapshots)
        }
        return outcome.snapshots
    }

    @discardableResult
    private func reload() throws -> SnapshotReloadOutcome {
        try syncOnQueueIfNeeded {
            let previousSnapshots = snapshotsBySessionID
            let indexRecordsBySessionID = try loadIndexRecordsBySessionID()
            var nextSnapshots: [String: CodexSessionArtifactSnapshot] = [:]
            var watchedDirectoryPaths: Set<String> = [codexHomeURL.path]

            for sessionID in trackedSessionIDs {
                let indexRecord = indexRecordsBySessionID[sessionID]
                let transcriptURL = try resolvedTranscriptURL(for: sessionID)
                if let transcriptURL {
                    watchedDirectoryPaths.insert(transcriptURL.deletingLastPathComponent().path)
                }
                let transcriptArtifact = try loadTranscriptArtifact(
                    for: sessionID,
                    at: transcriptURL
                )
                nextSnapshots[sessionID] = mergedSnapshot(
                    for: sessionID,
                    indexRecord: indexRecord,
                    transcriptArtifact: transcriptArtifact,
                    sessionFileURL: transcriptURL
                )
            }

            snapshotsBySessionID = nextSnapshots
            syncDirectoryMonitors(watching: watchedDirectoryPaths)
            return SnapshotReloadOutcome(
                snapshots: nextSnapshots,
                didChange: nextSnapshots != previousSnapshots
            )
        }
    }

    private func loadIndexRecordsBySessionID() throws -> [String: SessionIndexRecord] {
        guard fileManager.fileExists(atPath: sessionIndexURL.path) else {
            cachedIndexSnapshot = nil
            return [:]
        }

        let resourceValues = try? sessionIndexURL.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        let modificationDate = resourceValues?.contentModificationDate
        let fileSize = resourceValues?.fileSize

        if let cachedIndexSnapshot,
           cachedIndexSnapshot.modificationDate == modificationDate,
           cachedIndexSnapshot.fileSize == fileSize {
            return cachedIndexSnapshot.recordsBySessionID
        }

        let data = try Data(contentsOf: sessionIndexURL)
        let recordsBySessionID = Self.parseSessionIndexRecords(from: data)
        cachedIndexSnapshot = CachedIndexSnapshot(
            recordsBySessionID: recordsBySessionID,
            modificationDate: modificationDate,
            fileSize: fileSize
        )
        return recordsBySessionID
    }

    private func resolvedTranscriptURL(for sessionID: String) throws -> URL? {
        if let cachedURL = transcriptURLBySessionID[sessionID],
           fileManager.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }

        guard fileManager.fileExists(atPath: sessionsRootURL.path) else {
            transcriptURLBySessionID.removeValue(forKey: sessionID)
            return nil
        }

        let expectedSuffix = "\(sessionID).jsonl"
        let enumerator = fileManager.enumerator(
            at: sessionsRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let nextURL = enumerator?.nextObject() as? URL {
            guard nextURL.lastPathComponent.hasSuffix(expectedSuffix) else {
                continue
            }
            let values = try? nextURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile != false else {
                continue
            }
            transcriptURLBySessionID[sessionID] = nextURL
            return nextURL
        }

        transcriptURLBySessionID.removeValue(forKey: sessionID)
        return nil
    }

    private func loadTranscriptArtifact(
        for sessionID: String,
        at fileURL: URL?
    ) throws -> TranscriptArtifact? {
        guard let fileURL else {
            cachedTranscriptSnapshotsBySessionID.removeValue(forKey: sessionID)
            return nil
        }

        let resourceValues = try? fileURL.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        let modificationDate = resourceValues?.contentModificationDate
        let fileSize = resourceValues?.fileSize

        if let cachedSnapshot = cachedTranscriptSnapshotsBySessionID[sessionID],
           cachedSnapshot.fileURL == fileURL,
           cachedSnapshot.modificationDate == modificationDate,
           cachedSnapshot.fileSize == fileSize {
            return cachedSnapshot.artifact
        }

        let artifact = try readTranscriptArtifact(from: fileURL, fileSize: fileSize)
        cachedTranscriptSnapshotsBySessionID[sessionID] = CachedTranscriptSnapshot(
            fileURL: fileURL,
            artifact: artifact,
            modificationDate: modificationDate,
            fileSize: fileSize
        )
        transcriptURLBySessionID[sessionID] = fileURL
        return artifact
    }

    private func readTranscriptArtifact(
        from fileURL: URL,
        fileSize: Int?
    ) throws -> TranscriptArtifact {
        let resolvedFileSize = max(0, fileSize ?? fileSizeOnDisk(for: fileURL))
        guard resolvedFileSize > 0 else {
            return TranscriptArtifact()
        }

        if resolvedFileSize <= transcriptPrefixReadLimit + transcriptSuffixReadLimit {
            let data = try Data(contentsOf: fileURL)
            return Self.parseTranscriptArtifact(
                fromPrefix: data,
                suffixData: data
            )
        }

        let prefixData = try readPrefix(
            from: fileURL,
            byteCount: transcriptPrefixReadLimit
        )
        let suffixData = try readSuffix(
            from: fileURL,
            byteCount: transcriptSuffixReadLimit
        )
        return Self.parseTranscriptArtifact(
            fromPrefix: prefixData,
            suffixData: suffixData
        )
    }

    private func mergedSnapshot(
        for sessionID: String,
        indexRecord: SessionIndexRecord?,
        transcriptArtifact: TranscriptArtifact?,
        sessionFileURL: URL?
    ) -> CodexSessionArtifactSnapshot {
        let activityCandidates = [
            indexRecord?.updatedAt,
            transcriptArtifact?.lastActivityAt
        ].compactMap { $0 }

        return CodexSessionArtifactSnapshot(
            sessionID: sessionID,
            threadTitle: indexRecord?.threadTitle ?? transcriptArtifact?.fallbackThreadTitle,
            lastActivityAt: activityCandidates.max(),
            lastAssistantSummary: transcriptArtifact?.lastAssistantSummary,
            lastTaskCompleteSummary: transcriptArtifact?.lastTaskCompleteSummary,
            lastTaskCompleteAt: transcriptArtifact?.lastTaskCompleteAt,
            sessionFileURL: sessionFileURL
        )
    }

    private func scheduleReloadAfterDirectoryEvent() {
        pendingReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.pendingReloadWorkItem = nil
            do {
                let outcome = try self.reload()
                if outcome.didChange {
                    self.notifyChange(outcome.snapshots)
                }
            } catch {
                // Ignore transient codex transcript write races and wait for the next event.
            }
        }
        pendingReloadWorkItem = workItem
        if reloadDebounceNanoseconds == 0 {
            queue.async(execute: workItem)
        } else {
            let nanoseconds = reloadDebounceNanoseconds > UInt64(Int.max)
                ? Int.max
                : Int(reloadDebounceNanoseconds)
            queue.asyncAfter(
                deadline: .now() + .nanoseconds(nanoseconds),
                execute: workItem
            )
        }
    }

    private func installSweepTimerIfNeeded() {
        guard periodicReloadInterval > 0, sweepTimer == nil else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + periodicReloadInterval,
            repeating: periodicReloadInterval
        )
        timer.setEventHandler { [weak self] in
            guard let self, !self.trackedSessionIDs.isEmpty else {
                return
            }
            do {
                let outcome = try self.reload()
                if outcome.didChange {
                    self.notifyChange(outcome.snapshots)
                }
            } catch {
                // Ignore periodic sweep races and wait for the next interval.
            }
        }
        sweepTimer = timer
        timer.resume()
    }

    private func stopSweepTimer() {
        sweepTimer?.cancel()
        sweepTimer = nil
    }

    private func syncDirectoryMonitors(watching directoryPaths: Set<String>) {
        let existingPaths = Set(monitorSourcesByDirectoryPath.keys)
        let removedPaths = existingPaths.subtracting(directoryPaths)
        for path in removedPaths {
            monitorSourcesByDirectoryPath[path]?.cancel()
            monitorSourcesByDirectoryPath.removeValue(forKey: path)
        }

        for path in directoryPaths.subtracting(existingPaths) {
            guard fileManager.fileExists(atPath: path) else {
                continue
            }

            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else {
                continue
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename],
                queue: queue
            )
            monitorFileDescriptorsByDirectoryPath[path] = descriptor
            source.setEventHandler { [weak self] in
                self?.scheduleReloadAfterDirectoryEvent()
            }
            source.setCancelHandler { [weak self] in
                guard let self,
                      let descriptor = self.monitorFileDescriptorsByDirectoryPath.removeValue(forKey: path)
                else {
                    return
                }
                close(descriptor)
            }
            monitorSourcesByDirectoryPath[path] = source
            source.resume()
        }
    }

    private func notifyChange(_ snapshots: [String: CodexSessionArtifactSnapshot]) {
        let handler = syncOnQueueIfNeeded { onSnapshotsChange }
        DispatchQueue.main.async {
            handler?(snapshots)
        }
    }

    private func syncOnQueueIfNeeded<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueSpecificKey) == queueSpecificValue {
            return try body()
        }
        return try queue.sync(execute: body)
    }

    private static func parseSessionIndexRecords(from data: Data) -> [String: SessionIndexRecord] {
        var recordsBySessionID: [String: SessionIndexRecord] = [:]
        for line in data.split(whereSeparator: isJSONLNewline) {
            guard let jsonObject = try? JSONSerialization.jsonObject(with: Data(line)),
                  let dictionary = jsonObject as? [String: Any],
                  let sessionID = stringValue(forKey: "id", in: dictionary)
            else {
                continue
            }

            recordsBySessionID[sessionID] = SessionIndexRecord(
                sessionID: sessionID,
                threadTitle: normalizedSummaryText(stringValue(forKey: "thread_name", in: dictionary)),
                updatedAt: parsedDate(from: dictionary["updated_at"])
            )
        }
        return recordsBySessionID
    }

    private static func parseTranscriptArtifact(
        fromPrefix prefixData: Data,
        suffixData: Data
    ) -> TranscriptArtifact {
        var artifact = TranscriptArtifact()

        for line in completeJSONLLines(inPrefixData: prefixData) {
            guard artifact.fallbackThreadTitle == nil,
                  let jsonObject = try? JSONSerialization.jsonObject(with: Data(line)),
                  let dictionary = jsonObject as? [String: Any],
                  stringValue(forKey: "type", in: dictionary) == "event_msg",
                  let payload = dictionaryValue(forKey: "payload", in: dictionary),
                  stringValue(forKey: "type", in: payload) == "user_message",
                  let title = normalizedSummaryText(stringValue(forKey: "message", in: payload))
            else {
                continue
            }
            artifact.fallbackThreadTitle = title
            break
        }

        for line in completeJSONLLines(inSuffixData: suffixData) {
            guard let jsonObject = try? JSONSerialization.jsonObject(with: Data(line)),
                  let dictionary = jsonObject as? [String: Any],
                  let lineType = stringValue(forKey: "type", in: dictionary)
            else {
                continue
            }

            let timestamp = parsedDate(from: dictionary["timestamp"])
            artifact.lastActivityAt = maxDate(artifact.lastActivityAt, timestamp)
            switch lineType {
            case "response_item":
                guard let payload = dictionaryValue(forKey: "payload", in: dictionary),
                      stringValue(forKey: "type", in: payload) == "message"
                else {
                    continue
                }
                if stringValue(forKey: "role", in: payload) == "assistant",
                   let summary = assistantSummary(from: payload) {
                    artifact.lastAssistantSummary = summary
                }
            case "event_msg":
                guard let payload = dictionaryValue(forKey: "payload", in: dictionary),
                      let payloadType = stringValue(forKey: "type", in: payload)
                else {
                    continue
                }

                switch payloadType {
                case "agent_message":
                    if let summary = normalizedSummaryText(stringValue(forKey: "message", in: payload)) {
                        artifact.lastAssistantSummary = summary
                    }
                case "task_complete":
                    if let summary = normalizedSummaryText(stringValue(forKey: "last_agent_message", in: payload)) {
                        artifact.lastTaskCompleteSummary = summary
                    }
                    artifact.lastTaskCompleteAt = maxDate(artifact.lastTaskCompleteAt, timestamp)
                case "agent_reasoning":
                    continue
                default:
                    continue
                }
            default:
                continue
            }
        }

        return artifact
    }

    private func fileSizeOnDisk(for fileURL: URL) -> Int {
        (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private func readPrefix(from fileURL: URL, byteCount: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        return try handle.read(upToCount: byteCount) ?? Data()
    }

    private func readSuffix(from fileURL: URL, byteCount: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        let startOffset = fileSize > UInt64(byteCount) ? fileSize - UInt64(byteCount) : 0
        try handle.seek(toOffset: startOffset)
        return try handle.readToEnd() ?? Data()
    }

    private static func assistantSummary(from payload: [String: Any]) -> String? {
        guard let content = payload["content"] as? [[String: Any]] else {
            return nil
        }

        let text = content.compactMap { item -> String? in
            guard stringValue(forKey: "type", in: item) == "output_text" else {
                return nil
            }
            return stringValue(forKey: "text", in: item)
        }.joined(separator: "\n")

        return normalizedSummaryText(text)
    }

    private static func normalizedSummaryText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }
        let condensed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !condensed.isEmpty else {
            return nil
        }
        let limit = 140
        guard condensed.count > limit else {
            return condensed
        }
        let truncated = condensed.prefix(limit - 1).trimmingCharacters(in: .whitespacesAndNewlines)
        return truncated + "…"
    }

    private static func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    private static func stringValue(forKey key: String, in dictionary: [String: Any]) -> String? {
        dictionary[key] as? String
    }

    private static func dictionaryValue(forKey key: String, in dictionary: [String: Any]) -> [String: Any]? {
        dictionary[key] as? [String: Any]
    }

    private static func parsedDate(from value: Any?) -> Date? {
        switch value {
        case let string as String:
            return iso8601Date(from: string)
        case let number as NSNumber:
            return Date(timeIntervalSince1970: number.doubleValue)
        default:
            return nil
        }
    }

    private static func iso8601Date(from value: String) -> Date? {
        let internetDateFormatter = ISO8601DateFormatter()
        internetDateFormatter.formatOptions = [.withInternetDateTime]
        internetDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        if let date = internetDateFormatter.date(from: value) {
            return date
        }

        let fractionalDateFormatter = ISO8601DateFormatter()
        fractionalDateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        fractionalDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return fractionalDateFormatter.date(from: value)
    }

    private static func isJSONLNewline(_ byte: UInt8) -> Bool {
        byte == 0x0A || byte == 0x0D
    }

    private static func completeJSONLLines(inPrefixData data: Data) -> [Data] {
        guard let lastNewlineIndex = data.lastIndex(where: isJSONLNewline) else {
            return [data].filter { !$0.isEmpty }
        }
        return scanJSONLLines(in: data[..<lastNewlineIndex])
    }

    private static func completeJSONLLines(inSuffixData data: Data) -> [Data] {
        let startIndex: Data.Index
        if let firstNewlineIndex = data.firstIndex(where: isJSONLNewline) {
            startIndex = data.index(after: firstNewlineIndex)
        } else {
            startIndex = data.startIndex
        }
        guard startIndex < data.endIndex else {
            return []
        }
        return scanJSONLLines(in: data[startIndex...])
    }

    private static func scanJSONLLines(in data: Data.SubSequence) -> [Data] {
        var lines: [Data] = []
        var lineStart = data.startIndex
        var cursor = data.startIndex

        while cursor < data.endIndex {
            if isJSONLNewline(data[cursor]) {
                if lineStart < cursor {
                    lines.append(Data(data[lineStart..<cursor]))
                }
                cursor = data.index(after: cursor)
                lineStart = cursor
                continue
            }
            cursor = data.index(after: cursor)
        }

        if lineStart < data.endIndex {
            lines.append(Data(data[lineStart..<data.endIndex]))
        }
        return lines
    }
}
