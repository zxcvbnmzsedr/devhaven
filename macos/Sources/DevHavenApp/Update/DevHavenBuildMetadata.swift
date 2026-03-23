import Foundation
import DevHavenCore

struct DevHavenBuildMetadata: Equatable {
    let shortVersion: String
    let buildVersion: String
    let bundleIdentifier: String
    let stableFeedURL: URL?
    let nightlyFeedURL: URL?
    let stableDownloadsPageURL: URL?
    let nightlyDownloadsPageURL: URL?
    let sparklePublicKey: String?
    let updateDeliveryMode: DevHavenUpdateDeliveryMode
    let isAppBundle: Bool

    var supportsUpdateChecks: Bool {
        isAppBundle && stableFeedURL != nil && nightlyFeedURL != nil
    }

    var supportsAutomaticUpdates: Bool {
        supportsUpdateChecks
            && updateDeliveryMode == .automatic
            && !(sparklePublicKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var supportsUpdater: Bool {
        supportsAutomaticUpdates
    }

    func feedURL(for channel: UpdateChannel) -> URL? {
        switch channel {
        case .stable:
            return stableFeedURL
        case .nightly:
            return nightlyFeedURL
        }
    }

    func downloadsPageURL(for channel: UpdateChannel) -> URL? {
        switch channel {
        case .stable:
            return stableDownloadsPageURL
        case .nightly:
            return nightlyDownloadsPageURL
        }
    }

    static func current(bundle: Bundle = .main) -> DevHavenBuildMetadata {
        let info = bundle.infoDictionary ?? [:]
        let shortVersion = (info["CFBundleShortVersionString"] as? String)?.nonEmpty ?? "DevHaven Native Preview"
        let buildVersion = (info["CFBundleVersion"] as? String)?.nonEmpty ?? "0"
        let bundleIdentifier = bundle.bundleIdentifier ?? "com.devhaven"
        let stableFeedURL = URL(string: (info["DevHavenStableFeedURL"] as? String)?.nonEmpty ?? "")
        let nightlyFeedURL = URL(string: (info["DevHavenNightlyFeedURL"] as? String)?.nonEmpty ?? "")
        let stableDownloadsPageURL = URL(string: (info["DevHavenStableDownloadsPageURL"] as? String)?.nonEmpty ?? "")
        let nightlyDownloadsPageURL = URL(string: (info["DevHavenNightlyDownloadsPageURL"] as? String)?.nonEmpty ?? "")
        let sparklePublicKey = (info["SUPublicEDKey"] as? String)?.nonEmpty
        let updateDeliveryMode = DevHavenUpdateDeliveryMode(
            rawValue: (info["DevHavenUpdateDeliveryMode"] as? String)?.nonEmpty ?? ""
        ) ?? .manualDownload
        let isAppBundle = bundle.bundleURL.pathExtension == "app"
        return DevHavenBuildMetadata(
            shortVersion: shortVersion,
            buildVersion: buildVersion,
            bundleIdentifier: bundleIdentifier,
            stableFeedURL: stableFeedURL,
            nightlyFeedURL: nightlyFeedURL,
            stableDownloadsPageURL: stableDownloadsPageURL,
            nightlyDownloadsPageURL: nightlyDownloadsPageURL,
            sparklePublicKey: sparklePublicKey,
            updateDeliveryMode: updateDeliveryMode,
            isAppBundle: isAppBundle
        )
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
