import XCTest
import WebKit
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class WorkspaceBrowserConfigurationTests: XCTestCase {
    func testHostModelUsesPersistentStoreAndSafariUserAgent() {
        let first = WorkspaceBrowserHostModel(
            state: WorkspaceBrowserState(
                surfaceId: "surface:first",
                projectPath: "/tmp/browser-config",
                tabId: "tab:1",
                paneId: "pane:1"
            )
        )
        let second = WorkspaceBrowserHostModel(
            state: WorkspaceBrowserState(
                surfaceId: "surface:second",
                projectPath: "/tmp/browser-config",
                tabId: "tab:1",
                paneId: "pane:1"
            )
        )

        XCTAssertEqual(
            first.webView.customUserAgent,
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.2 Safari/605.1.15"
        )
        XCTAssertTrue(first.webView.configuration.websiteDataStore === WKWebsiteDataStore.default())
        XCTAssertTrue(second.webView.configuration.websiteDataStore === WKWebsiteDataStore.default())
        XCTAssertNotNil(first.webView.underPageBackgroundColor)
    }
}
