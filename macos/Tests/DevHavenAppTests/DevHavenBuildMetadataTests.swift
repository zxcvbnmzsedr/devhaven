import XCTest
@testable import DevHavenApp

final class DevHavenBuildMetadataTests: XCTestCase {
    func testNonBundleBuildDisablesAllUpdateSupport() {
        let metadata = DevHavenBuildMetadata(
            shortVersion: "3.0.0",
            buildVersion: "3000001",
            bundleIdentifier: "com.devhaven",
            stableFeedURL: URL(string: "https://download.devhaven.app/stable/appcast.xml")!,
            nightlyFeedURL: URL(string: "https://download.devhaven.app/nightly/appcast.xml")!,
            stableDownloadsPageURL: URL(string: "https://github.com/example/devhaven/releases")!,
            nightlyDownloadsPageURL: URL(string: "https://github.com/example/devhaven/releases/tag/nightly")!,
            sparklePublicKey: nil,
            updateDeliveryMode: .manualDownload,
            isAppBundle: false
        )

        XCTAssertFalse(metadata.supportsUpdateChecks)
        XCTAssertFalse(metadata.supportsAutomaticUpdates)
    }

    func testNightlyChannelUsesNightlyFeedURL() {
        let metadata = DevHavenBuildMetadata(
            shortVersion: "3.0.0",
            buildVersion: "3000001",
            bundleIdentifier: "com.devhaven",
            stableFeedURL: URL(string: "https://download.devhaven.app/stable/appcast.xml")!,
            nightlyFeedURL: URL(string: "https://download.devhaven.app/nightly/appcast.xml")!,
            stableDownloadsPageURL: URL(string: "https://github.com/example/devhaven/releases")!,
            nightlyDownloadsPageURL: URL(string: "https://github.com/example/devhaven/releases/tag/nightly")!,
            sparklePublicKey: "pub-key",
            updateDeliveryMode: .automatic,
            isAppBundle: true
        )

        XCTAssertEqual(metadata.feedURL(for: .nightly)?.absoluteString, "https://download.devhaven.app/nightly/appcast.xml")
        XCTAssertEqual(metadata.feedURL(for: .stable)?.absoluteString, "https://download.devhaven.app/stable/appcast.xml")
        XCTAssertEqual(metadata.downloadsPageURL(for: .nightly)?.absoluteString, "https://github.com/example/devhaven/releases/tag/nightly")
        XCTAssertTrue(metadata.supportsUpdateChecks)
        XCTAssertTrue(metadata.supportsAutomaticUpdates)
    }

    func testManualDownloadModeKeepsUpdateChecksButDisablesAutomaticUpdates() {
        let metadata = DevHavenBuildMetadata(
            shortVersion: "3.0.0",
            buildVersion: "3000001",
            bundleIdentifier: "com.devhaven",
            stableFeedURL: URL(string: "https://download.devhaven.app/stable/appcast.xml")!,
            nightlyFeedURL: URL(string: "https://download.devhaven.app/nightly/appcast.xml")!,
            stableDownloadsPageURL: URL(string: "https://github.com/example/devhaven/releases")!,
            nightlyDownloadsPageURL: URL(string: "https://github.com/example/devhaven/releases/tag/nightly")!,
            sparklePublicKey: nil,
            updateDeliveryMode: .manualDownload,
            isAppBundle: true
        )

        XCTAssertTrue(metadata.supportsUpdateChecks)
        XCTAssertFalse(metadata.supportsAutomaticUpdates)
        XCTAssertEqual(metadata.downloadsPageURL(for: .stable)?.absoluteString, "https://github.com/example/devhaven/releases")
    }
}
