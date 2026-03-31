import Foundation
import Darwin

public final class WorkspaceAgentSignalStore {
    public typealias ChangeHandler = @Sendable ([String: WorkspaceAgentSessionSignal]) -> Void
    public typealias ProcessAliveHandler = @Sendable (Int32) -> Bool
    public typealias SignalLoader = @Sendable (URL) throws -> WorkspaceAgentSessionSignal

    private struct CachedSignalFileSnapshot: Sendable {
        var signal: WorkspaceAgentSessionSignal
        var modificationDate: Date?
        var fileSize: Int?
    }

    private struct SnapshotReloadOutcome: Sendable {
        var snapshots: [String: WorkspaceAgentSessionSignal]
        var didChange: Bool
    }

    private let fileManager: FileManager
    private let processAliveHandler: ProcessAliveHandler
    private let signalLoader: SignalLoader
    private let queue = DispatchQueue(label: "DevHavenCore.WorkspaceAgentSignalStore")
    private let queueSpecificKey = DispatchSpecificKey<UInt8>()
    private let queueSpecificValue: UInt8 = 1
    private let staleActiveSignalInterval: TimeInterval
    private let completedSignalRetentionInterval: TimeInterval
    private let reloadDebounceNanoseconds: UInt64

    private var monitorSource: DispatchSourceFileSystemObject?
    private var monitorFileDescriptor: Int32 = -1
    private var sweepTimer: DispatchSourceTimer?
    private var directoryDidChange = false
    private var pendingReloadWorkItem: DispatchWorkItem?

    public let baseDirectoryURL: URL
    public var onSignalsChange: ChangeHandler?
    public private(set) var snapshotsByTerminalSessionID: [String: WorkspaceAgentSessionSignal] = [:]
    private var cachedSignalsByFileName: [String: CachedSignalFileSnapshot] = [:]

    public init(
        baseDirectoryURL: URL,
        fileManager: FileManager = .default,
        staleActiveSignalInterval: TimeInterval = 30,
        completedSignalRetentionInterval: TimeInterval = 8,
        reloadDebounceNanoseconds: UInt64 = 80_000_000,
        processAlive: @escaping ProcessAliveHandler = WorkspaceAgentSignalStore.defaultProcessAlive,
        signalLoader: @escaping SignalLoader = WorkspaceAgentSignalStore.defaultSignalLoader
    ) {
        self.baseDirectoryURL = baseDirectoryURL
        self.fileManager = fileManager
        self.staleActiveSignalInterval = staleActiveSignalInterval
        self.completedSignalRetentionInterval = completedSignalRetentionInterval
        self.reloadDebounceNanoseconds = reloadDebounceNanoseconds
        self.processAliveHandler = processAlive
        self.signalLoader = signalLoader
        self.queue.setSpecific(key: queueSpecificKey, value: queueSpecificValue)
    }

    deinit {
        stop()
    }

    public var currentSnapshots: [String: WorkspaceAgentSessionSignal] {
        syncOnStoreQueueIfNeeded { snapshotsByTerminalSessionID }
    }

    public func ensureDirectoryExists() throws {
        try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    }

    public func start() throws {
        try ensureDirectoryExists()
        let initialReload = try reload(now: Date())
        if initialReload.didChange {
            notifyChange(initialReload.snapshots)
        }

        if monitorSource == nil {
            let descriptor = open(baseDirectoryURL.path, O_EVTONLY)
            guard descriptor >= 0 else {
                throw NSError(
                    domain: "DevHavenCore.WorkspaceAgentSignalStore",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "无法监听 Agent signal 目录：\(baseDirectoryURL.path)"]
                )
            }

            monitorFileDescriptor = descriptor
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.reloadAfterDirectoryEvent()
            }
            source.setCancelHandler { [weak self] in
                guard let self else { return }
                if self.monitorFileDescriptor >= 0 {
                    close(self.monitorFileDescriptor)
                    self.monitorFileDescriptor = -1
                }
            }
            monitorSource = source
            source.resume()
        }

        if sweepTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 10, repeating: 10)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                guard self.directoryDidChange else { return }
                self.directoryDidChange = false
                do {
                    try self.sweepStaleSignals(now: Date())
                } catch {
                    // 忽略后台清理错误，避免影响 UI 线程
                }
            }
            sweepTimer = timer
            timer.resume()
        }
    }

    public func stop() {
        syncOnStoreQueueIfNeeded {
            pendingReloadWorkItem?.cancel()
            pendingReloadWorkItem = nil
            sweepTimer?.cancel()
            sweepTimer = nil
            monitorSource?.cancel()
            monitorSource = nil
        }
    }

    @discardableResult
    public func reloadForTesting() throws -> [String: WorkspaceAgentSessionSignal] {
        try reload(now: Date()).snapshots
    }

    @discardableResult
    public func sweepStaleSignals(
        now: Date = Date(),
        processAlive: ProcessAliveHandler? = nil
    ) throws -> [String: WorkspaceAgentSessionSignal] {
        let alive = processAlive ?? processAliveHandler
        let outcome = syncOnStoreQueueIfNeeded { () -> SnapshotReloadOutcome in
            let previousSnapshots = snapshotsByTerminalSessionID
            for (terminalSessionID, snapshot) in snapshotsByTerminalSessionID {
                let age = now.timeIntervalSince(snapshot.updatedAt)
                guard age >= staleActiveSignalInterval else { continue }
                guard snapshot.state == .running || snapshot.state == .waiting else { continue }
                if let pid = snapshot.pid, alive(pid) {
                    continue
                }
                let signalURL = signalFileURL(for: terminalSessionID)
                try? fileManager.removeItem(at: signalURL)
                snapshotsByTerminalSessionID.removeValue(forKey: terminalSessionID)
                cachedSignalsByFileName.removeValue(forKey: signalURL.lastPathComponent)
            }
            snapshotsByTerminalSessionID = normalizeSnapshots(snapshotsByTerminalSessionID, now: now)
            return SnapshotReloadOutcome(
                snapshots: snapshotsByTerminalSessionID,
                didChange: snapshotsByTerminalSessionID != previousSnapshots
            )
        }
        if outcome.didChange {
            notifyChange(outcome.snapshots)
        }
        return outcome.snapshots
    }

    private func reloadAfterDirectoryEvent() {
        directoryDidChange = true
        pendingReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.pendingReloadWorkItem = nil
            do {
                let outcome = try self.reload(now: Date())
                if outcome.didChange {
                    self.notifyChange(outcome.snapshots)
                }
            } catch {
                // 忽略目录监听瞬时错误，等待下次事件 / sweep
            }
        }
        pendingReloadWorkItem = workItem
        if reloadDebounceNanoseconds == 0 {
            queue.async(execute: workItem)
        } else {
            let nanoseconds = reloadDebounceNanoseconds > UInt64(Int.max)
                ? Int.max
                : Int(reloadDebounceNanoseconds)
            let delay = DispatchTimeInterval.nanoseconds(
                nanoseconds
            )
            queue.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    @discardableResult
    private func reload(now: Date) throws -> SnapshotReloadOutcome {
        try syncOnStoreQueueIfNeeded {
            let previousSnapshots = snapshotsByTerminalSessionID
            let urls = try fileManager.contentsOfDirectory(
                at: baseDirectoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
            )
            var nextCache: [String: CachedSignalFileSnapshot] = [:]
            let signals = urls.compactMap { url -> WorkspaceAgentSessionSignal? in
                guard url.pathExtension == "json" else {
                    return nil
                }
                let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
                guard resourceValues?.isRegularFile != false else {
                    return nil
                }
                let fileName = url.lastPathComponent
                let modificationDate = resourceValues?.contentModificationDate
                let fileSize = resourceValues?.fileSize

                if let cached = cachedSignalsByFileName[fileName],
                   cached.modificationDate == modificationDate,
                   cached.fileSize == fileSize {
                    nextCache[fileName] = cached
                    return cached.signal
                }

                guard let signal = try? signalLoader(url) else {
                    return nil
                }
                nextCache[fileName] = CachedSignalFileSnapshot(
                    signal: signal,
                    modificationDate: modificationDate,
                    fileSize: fileSize
                )
                return signal
            }
            cachedSignalsByFileName = nextCache
            snapshotsByTerminalSessionID = normalizeSnapshots(
                Dictionary(uniqueKeysWithValues: signals.map { ($0.terminalSessionId, $0) }),
                now: now
            )
            return SnapshotReloadOutcome(
                snapshots: snapshotsByTerminalSessionID,
                didChange: snapshotsByTerminalSessionID != previousSnapshots
            )
        }
    }

    public static func defaultSignalLoader(at url: URL) throws -> WorkspaceAgentSessionSignal {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(WorkspaceAgentSessionSignal.self, from: data)
    }

    private func normalizeSnapshots(
        _ snapshots: [String: WorkspaceAgentSessionSignal],
        now: Date
    ) -> [String: WorkspaceAgentSessionSignal] {
        snapshots.reduce(into: [:]) { partialResult, entry in
            var snapshot = entry.value
            let age = now.timeIntervalSince(snapshot.updatedAt)
            if age >= completedSignalRetentionInterval,
               snapshot.state == .completed || snapshot.state == .failed {
                snapshot.state = .idle
                snapshot.summary = nil
                snapshot.detail = nil
                snapshot.pid = nil
            }
            partialResult[entry.key] = snapshot
        }
    }

    private func signalFileURL(for terminalSessionID: String) -> URL {
        baseDirectoryURL.appending(
            path: Self.signalFileName(for: terminalSessionID),
            directoryHint: .notDirectory
        )
    }

    static func signalFileName(for terminalSessionID: String) -> String {
        let encoded = Data(terminalSessionID.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(encoded).json"
    }

    private func notifyChange(_ snapshots: [String: WorkspaceAgentSessionSignal]) {
        guard let onSignalsChange else { return }
        onSignalsChange(snapshots)
    }

    func performOnStoreQueueForTesting<T>(_ operation: () throws -> T) rethrows -> T {
        try queue.sync(execute: operation)
    }

    private func syncOnStoreQueueIfNeeded<T>(_ operation: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueSpecificKey) == queueSpecificValue {
            return try operation()
        }
        return try queue.sync(execute: operation)
    }

    public static func defaultProcessAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        errno = 0
        if kill(pid, 0) == 0 {
            return true
        }
        return POSIXErrorCode(rawValue: errno) == .EPERM
    }
}
