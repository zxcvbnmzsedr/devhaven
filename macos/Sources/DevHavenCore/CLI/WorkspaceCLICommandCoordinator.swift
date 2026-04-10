import Foundation
import Darwin

@MainActor
public final class WorkspaceCLICommandCoordinator {
    private let store: WorkspaceCLICommandStore
    private let executor: WorkspaceCLICommandExecutor
    private let startedAt: Date
    private let queue = DispatchQueue(label: "DevHavenCore.WorkspaceCLICommandCoordinator")
    private let responseRetentionInterval: TimeInterval

    private var monitorSource: DispatchSourceFileSystemObject?
    private var monitorFileDescriptor: Int32 = -1
    private var pendingReloadWorkItem: DispatchWorkItem?
    private var isStarted = false

    public init(
        viewModel: NativeAppViewModel,
        store: WorkspaceCLICommandStore = WorkspaceCLICommandStore(),
        responseRetentionInterval: TimeInterval = 60
    ) {
        self.store = store
        self.executor = WorkspaceCLICommandExecutor(viewModel: viewModel)
        self.startedAt = Date()
        self.responseRetentionInterval = responseRetentionInterval
    }

    public func start() throws {
        guard !isStarted else {
            return
        }
        try store.ensureDirectoriesExist()
        try store.pruneResponses(olderThan: responseRetentionInterval)
        try store.writeServerState(makeServerState())
        try installMonitorIfNeeded()
        isStarted = true
        processPendingRequests()
    }

    public func stop() {
        pendingReloadWorkItem?.cancel()
        pendingReloadWorkItem = nil
        monitorSource?.cancel()
        monitorSource = nil
        if monitorFileDescriptor >= 0 {
            close(monitorFileDescriptor)
            monitorFileDescriptor = -1
        }
        try? store.removeServerState()
        isStarted = false
    }

    private func installMonitorIfNeeded() throws {
        guard monitorSource == nil else {
            return
        }
        let descriptor = open(store.requestsDirectoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw NSError(
                domain: "DevHavenCore.WorkspaceCLICommandCoordinator",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无法监听 CLI requests 目录：\(store.requestsDirectoryURL.path)"]
            )
        }
        monitorFileDescriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )
        source.setEventHandler { @Sendable [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRequestReload()
            }
        }
        source.setCancelHandler { @Sendable in }
        monitorSource = source
        source.resume()
    }

    private func scheduleRequestReload() {
        pendingReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { @Sendable [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.pendingReloadWorkItem = nil
                self.processPendingRequests()
            }
        }
        pendingReloadWorkItem = workItem
        queue.asyncAfter(deadline: .now() + .milliseconds(80), execute: workItem)
    }

    private func processPendingRequests() {
        guard isStarted else {
            return
        }
        let requests = (try? store.pendingRequests()) ?? []
        guard !requests.isEmpty else {
            return
        }

        for queuedRequest in requests {
            let response = executor.execute(queuedRequest.envelope)
            _ = try? store.writeResponse(response)
            try? store.removeRequest(at: queuedRequest.fileURL)
        }
    }

    private func makeServerState() -> WorkspaceCLIServerState {
        WorkspaceCLIServerState(
            pid: ProcessInfo.processInfo.processIdentifier,
            startedAt: startedAt,
            isReady: true,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }
}
