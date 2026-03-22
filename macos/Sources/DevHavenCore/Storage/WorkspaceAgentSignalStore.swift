import Foundation
import Darwin

public final class WorkspaceAgentSignalStore {
    public typealias ChangeHandler = @Sendable ([String: WorkspaceAgentSessionSignal]) -> Void
    public typealias ProcessAliveHandler = @Sendable (Int32) -> Bool

    private let fileManager: FileManager
    private let processAliveHandler: ProcessAliveHandler
    private let queue = DispatchQueue(label: "DevHavenCore.WorkspaceAgentSignalStore")
    private let queueSpecificKey = DispatchSpecificKey<UInt8>()
    private let queueSpecificValue: UInt8 = 1
    private let staleActiveSignalInterval: TimeInterval
    private let completedSignalRetentionInterval: TimeInterval

    private var monitorSource: DispatchSourceFileSystemObject?
    private var monitorFileDescriptor: Int32 = -1
    private var sweepTimer: DispatchSourceTimer?

    public let baseDirectoryURL: URL
    public var onSignalsChange: ChangeHandler?
    public private(set) var snapshotsByTerminalSessionID: [String: WorkspaceAgentSessionSignal] = [:]

    public init(
        baseDirectoryURL: URL,
        fileManager: FileManager = .default,
        staleActiveSignalInterval: TimeInterval = 30,
        completedSignalRetentionInterval: TimeInterval = 8,
        processAlive: @escaping ProcessAliveHandler = WorkspaceAgentSignalStore.defaultProcessAlive
    ) {
        self.baseDirectoryURL = baseDirectoryURL
        self.fileManager = fileManager
        self.staleActiveSignalInterval = staleActiveSignalInterval
        self.completedSignalRetentionInterval = completedSignalRetentionInterval
        self.processAliveHandler = processAlive
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
        let snapshots = try reload(now: Date())
        notifyChange(snapshots)

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
            timer.schedule(deadline: .now() + 5, repeating: 5)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
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
            sweepTimer?.cancel()
            sweepTimer = nil
            monitorSource?.cancel()
            monitorSource = nil
        }
    }

    @discardableResult
    public func reloadForTesting() throws -> [String: WorkspaceAgentSessionSignal] {
        try reload(now: Date())
    }

    @discardableResult
    public func sweepStaleSignals(
        now: Date = Date(),
        processAlive: ProcessAliveHandler? = nil
    ) throws -> [String: WorkspaceAgentSessionSignal] {
        let alive = processAlive ?? processAliveHandler
        let snapshots = syncOnStoreQueueIfNeeded {
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
            }
            snapshotsByTerminalSessionID = normalizeSnapshots(snapshotsByTerminalSessionID, now: now)
            return snapshotsByTerminalSessionID
        }
        notifyChange(snapshots)
        return snapshots
    }

    private func reloadAfterDirectoryEvent() {
        do {
            let snapshots = try reload(now: Date())
            notifyChange(snapshots)
        } catch {
            // 忽略目录监听瞬时错误，等待下次事件 / sweep
        }
    }

    @discardableResult
    private func reload(now: Date) throws -> [String: WorkspaceAgentSessionSignal] {
        try syncOnStoreQueueIfNeeded {
            let urls = try fileManager.contentsOfDirectory(
                at: baseDirectoryURL,
                includingPropertiesForKeys: nil
            )
            let signals = urls
                .filter { $0.pathExtension == "json" }
                .compactMap { url in
                    try? loadSignal(at: url)
                }
            snapshotsByTerminalSessionID = normalizeSnapshots(
                Dictionary(uniqueKeysWithValues: signals.map { ($0.terminalSessionId, $0) }),
                now: now
            )
            return snapshotsByTerminalSessionID
        }
    }

    private func loadSignal(at url: URL) throws -> WorkspaceAgentSessionSignal {
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
