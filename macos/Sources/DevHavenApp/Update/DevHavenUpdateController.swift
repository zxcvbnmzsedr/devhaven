import AppKit
import Combine
import Foundation
@preconcurrency import Sparkle
import DevHavenCore

@MainActor
final class DevHavenUpdateController: NSObject, ObservableObject {
    @Published private(set) var metadata: DevHavenBuildMetadata
    @Published private(set) var diagnostics: DevHavenUpdateDiagnostics

    private let delegateBridge: DevHavenSparkleUpdaterDelegate
    private var currentSettings: AppSettings
    private var updaterController: SPUStandardUpdaterController?
    private var didStartUpdater = false
    private var latestResolvedDownloadURL: URL?
    private var manualCheckTask: Task<Void, Never>?
    private var lastAutomaticManualCheckChannel: UpdateChannel?

    override init() {
        let metadata = DevHavenBuildMetadata.current()
        let settings = AppSettings()
        let diagnostics = DevHavenUpdateDiagnostics(
            currentChannel: settings.updateChannel,
            currentFeedURL: metadata.feedURL(for: settings.updateChannel)?.absoluteString,
            currentDownloadsPageURL: metadata.downloadsPageURL(for: settings.updateChannel)?.absoluteString,
            lastCheckedAt: nil,
            lastAvailableVersion: nil,
            lastAvailableBuildVersion: nil,
            lastResolvedDownloadURL: nil,
            lastStatusMessage: metadata.supportsUpdateChecks ? (metadata.supportsAutomaticUpdates ? "等待首次检查更新" : "当前构建将以手动下载模式检查更新") : "当前运行态不支持检查更新",
            lastErrorMessage: nil
        )

        self.metadata = metadata
        self.currentSettings = settings
        self.diagnostics = diagnostics
        self.delegateBridge = DevHavenSparkleUpdaterDelegate(
            metadata: metadata,
            settings: settings
        )
        super.init()

        delegateBridge.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleDelegateEvent(event)
            }
        }

        guard metadata.supportsAutomaticUpdates else {
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: delegateBridge,
            userDriverDelegate: nil
        )
    }

    var isSupported: Bool {
        metadata.supportsUpdateChecks
    }

    var supportsAutomaticUpdates: Bool {
        metadata.supportsAutomaticUpdates
    }

    var canOpenDownloadPage: Bool {
        resolvedDownloadURL != nil
    }

    var supportDescription: String {
        guard metadata.supportsUpdateChecks else {
            return "当前运行态不支持检查更新；请从正式 `.app` release 构建中使用该能力。"
        }
        if metadata.supportsAutomaticUpdates {
            return "当前构建支持自动升级。"
        }
        return "当前构建仅支持检查新版本并打开下载页；由于未启用 Apple Developer ID / notarization，自动安装更新已关闭。"
    }

    var diagnosticsText: String {
        diagnostics.exportText(metadata: metadata)
    }

    func apply(settings: AppSettings) {
        currentSettings = settings
        diagnostics.currentChannel = settings.updateChannel
        diagnostics.currentFeedURL = metadata.feedURL(for: settings.updateChannel)?.absoluteString
        diagnostics.currentDownloadsPageURL = metadata.downloadsPageURL(for: settings.updateChannel)?.absoluteString
        delegateBridge.update(metadata: metadata, settings: settings)
        latestResolvedDownloadURL = metadata.downloadsPageURL(for: settings.updateChannel)

        guard metadata.supportsUpdateChecks else {
            diagnostics.lastStatusMessage = supportDescription
            return
        }

        guard metadata.supportsAutomaticUpdates else {
            if settings.updateAutomaticallyChecks && lastAutomaticManualCheckChannel != settings.updateChannel {
                lastAutomaticManualCheckChannel = settings.updateChannel
                checkForUpdates(userInitiated: false)
            }
            return
        }

        guard let updater = updaterController?.updater else {
            return
        }

        if !didStartUpdater {
            do {
                try updater.start()
                didStartUpdater = true
                diagnostics.lastStatusMessage = "Updater 已启动"
            } catch {
                diagnostics.lastErrorMessage = error.localizedDescription
                diagnostics.lastStatusMessage = "Updater 启动失败"
                return
            }
        }

        updater.automaticallyChecksForUpdates = settings.updateAutomaticallyChecks
        updater.automaticallyDownloadsUpdates = settings.updateAutomaticallyDownloads
    }

    func checkForUpdates() {
        checkForUpdates(userInitiated: true)
    }

    func openDownloadPage() {
        guard let url = resolvedDownloadURL else {
            diagnostics.lastStatusMessage = "当前没有可打开的下载页"
            return
        }

        let opened = NSWorkspace.shared.open(url)
        diagnostics.lastStatusMessage = opened ? "已打开下载页" : "打开下载页失败"
        if !opened {
            diagnostics.lastErrorMessage = url.absoluteString
        }
    }

    func copyDiagnosticsToPasteboard() {
        let text = diagnosticsText
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        diagnostics.lastStatusMessage = "已复制升级诊断"
    }

    private var resolvedDownloadURL: URL? {
        latestResolvedDownloadURL ?? metadata.downloadsPageURL(for: currentSettings.updateChannel)
    }

    private func checkForUpdates(userInitiated: Bool) {
        diagnostics.lastCheckedAt = Date()
        diagnostics.lastErrorMessage = nil
        diagnostics.lastStatusMessage = userInitiated ? "正在检查更新…" : "正在后台检查更新…"

        guard metadata.supportsUpdateChecks else {
            diagnostics.lastStatusMessage = supportDescription
            return
        }

        guard metadata.supportsAutomaticUpdates else {
            startManualUpdateCheck(userInitiated: userInitiated)
            return
        }

        guard let updater = updaterController?.updater else {
            diagnostics.lastStatusMessage = supportDescription
            return
        }

        if !didStartUpdater {
            do {
                try updater.start()
                didStartUpdater = true
            } catch {
                diagnostics.lastErrorMessage = error.localizedDescription
                diagnostics.lastStatusMessage = "Updater 启动失败"
                return
            }
        }

        updater.checkForUpdates()
    }

    private func startManualUpdateCheck(userInitiated: Bool) {
        guard let feedURL = metadata.feedURL(for: currentSettings.updateChannel) else {
            diagnostics.lastStatusMessage = "当前通道缺少 appcast feed"
            return
        }

        manualCheckTask?.cancel()
        let currentBuildVersion = metadata.buildVersion
        let fallbackURL = metadata.downloadsPageURL(for: currentSettings.updateChannel)
        manualCheckTask = Task { [weak self] in
            do {
                let latestItem = try await Self.fetchLatestAppcastItem(from: feedURL)
                await MainActor.run {
                    self?.applyManualCheckResult(
                        latestItem,
                        currentBuildVersion: currentBuildVersion,
                        fallbackURL: fallbackURL,
                        userInitiated: userInitiated
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self?.diagnostics.lastErrorMessage = error.localizedDescription
                    self?.diagnostics.lastStatusMessage = "检查更新失败"
                    self?.latestResolvedDownloadURL = fallbackURL
                }
            }
        }
    }

    private func applyManualCheckResult(
        _ latestItem: DevHavenAppcastItem?,
        currentBuildVersion: String,
        fallbackURL: URL?,
        userInitiated: Bool
    ) {
        latestResolvedDownloadURL = fallbackURL

        guard let latestItem else {
            diagnostics.lastAvailableVersion = nil
            diagnostics.lastAvailableBuildVersion = nil
            diagnostics.lastResolvedDownloadURL = fallbackURL?.absoluteString
            diagnostics.lastStatusMessage = userInitiated ? "未从 feed 中解析到版本信息" : "后台检查未解析到版本信息"
            return
        }

        diagnostics.lastAvailableVersion = latestItem.shortVersion ?? latestItem.buildVersion
        diagnostics.lastAvailableBuildVersion = latestItem.buildVersion
        latestResolvedDownloadURL = latestItem.preferredDownloadURL ?? fallbackURL
        diagnostics.lastResolvedDownloadURL = latestResolvedDownloadURL?.absoluteString

        if Self.isRemoteBuild(latestItem.buildVersion, newerThan: currentBuildVersion) {
            let version = latestItem.shortVersion ?? latestItem.buildVersion ?? "未知版本"
            diagnostics.lastStatusMessage = "发现新版本：\(version)。请打开下载页完成更新。"
            diagnostics.lastErrorMessage = nil
        } else {
            diagnostics.lastStatusMessage = userInitiated ? "当前已是最新版本" : "后台检查完成：当前已是最新版本"
            diagnostics.lastErrorMessage = nil
        }
    }

    private func handleDelegateEvent(_ event: DevHavenSparkleDelegateEvent) {
        switch event {
        case let .resolvedFeedURL(url):
            diagnostics.currentFeedURL = url
        case let .didFindValidUpdate(version):
            diagnostics.lastAvailableVersion = version
            diagnostics.lastStatusMessage = "发现可用更新：\(version)"
            diagnostics.lastErrorMessage = nil
        case let .didNotFindUpdate(message, errorMessage):
            diagnostics.lastStatusMessage = message
            diagnostics.lastErrorMessage = errorMessage
        case let .willInstallUpdateOnQuit(version):
            diagnostics.lastStatusMessage = "更新已下载，将在退出后安装：\(version)"
            diagnostics.lastErrorMessage = nil
        case .willRelaunchApplication:
            diagnostics.lastStatusMessage = "正在重启以完成升级"
            diagnostics.lastErrorMessage = nil
        }
    }

    private static func fetchLatestAppcastItem(from feedURL: URL) async throws -> DevHavenAppcastItem? {
        var request = URLRequest(url: feedURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw NSError(
                domain: "DevHavenUpdate",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "appcast 请求失败：HTTP \(httpResponse.statusCode)"]
            )
        }
        return try DevHavenAppcastParser.parse(data: data).latestItem
    }

    private static func isRemoteBuild(_ remoteBuild: String?, newerThan localBuild: String) -> Bool {
        guard let remoteBuild else {
            return false
        }
        switch (Int64(remoteBuild), Int64(localBuild)) {
        case let (.some(remote), .some(local)):
            return remote > local
        default:
            return remoteBuild != localBuild
        }
    }
}

private enum DevHavenSparkleDelegateEvent {
    case resolvedFeedURL(String?)
    case didFindValidUpdate(String)
    case didNotFindUpdate(message: String, errorMessage: String?)
    case willInstallUpdateOnQuit(String)
    case willRelaunchApplication
}

private final class DevHavenSparkleUpdaterDelegateState: @unchecked Sendable {
    private let lock = NSLock()
    private var metadata: DevHavenBuildMetadata
    private var settings: AppSettings

    init(metadata: DevHavenBuildMetadata, settings: AppSettings) {
        self.metadata = metadata
        self.settings = settings
    }

    func update(metadata: DevHavenBuildMetadata, settings: AppSettings) {
        lock.lock()
        self.metadata = metadata
        self.settings = settings
        lock.unlock()
    }

    func snapshot() -> (metadata: DevHavenBuildMetadata, settings: AppSettings) {
        lock.lock()
        let snapshot = (metadata, settings)
        lock.unlock()
        return snapshot
    }
}

private final class DevHavenSparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var onEvent: ((DevHavenSparkleDelegateEvent) -> Void)?

    private let state: DevHavenSparkleUpdaterDelegateState

    init(metadata: DevHavenBuildMetadata, settings: AppSettings) {
        self.state = DevHavenSparkleUpdaterDelegateState(metadata: metadata, settings: settings)
        super.init()
    }

    func update(metadata: DevHavenBuildMetadata, settings: AppSettings) {
        state.update(metadata: metadata, settings: settings)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        let snapshot = state.snapshot()
        let url = snapshot.metadata.feedURL(for: snapshot.settings.updateChannel)?.absoluteString
        onEvent?(.resolvedFeedURL(url))
        return url
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        onEvent?(.didFindValidUpdate(item.displayVersionString))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let nsError = error as NSError
        let message: String
        let errorMessage: String?
        if nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = "当前已是最新版本"
            errorMessage = nil
        } else {
            message = "未发现可安装更新"
            errorMessage = nsError.localizedDescription
        }
        onEvent?(.didNotFindUpdate(message: message, errorMessage: errorMessage))
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        onEvent?(.willInstallUpdateOnQuit(item.displayVersionString))
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        onEvent?(.willRelaunchApplication)
    }
}
