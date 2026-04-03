import XCTest
@testable import DevHavenApp
@testable import DevHavenCore

final class WorkspaceBrowserProjectionPolicyTests: XCTestCase {
    func testResolveSuppressesProjectionWhileLoading() {
        let existing = WorkspaceBrowserState(
            surfaceId: "surface:1",
            projectPath: "/tmp/browser-policy",
            tabId: "tab:1",
            paneId: "pane:1",
            title: "www.baidu.com",
            urlString: "https://www.baidu.com/",
            isLoading: false
        )
        let runtime = WorkspaceBrowserRuntimeSnapshot(
            title: "www.baidu.com",
            urlString: "http://www.baidu.com/",
            isLoading: true,
            canGoBack: false,
            canGoForward: false
        )

        let resolved = WorkspaceBrowserProjectionPolicy.resolve(existing: existing, runtime: runtime)

        XCTAssertEqual(resolved.title, "www.baidu.com")
        XCTAssertEqual(resolved.urlString, "https://www.baidu.com/")
        XCTAssertFalse(resolved.isLoading)
        XCTAssertTrue(resolved.suppressedProjectionWhileLoading)
    }

    func testResolveKeepsRuntimeURLWhenNoStableExistingURL() {
        let runtime = WorkspaceBrowserRuntimeSnapshot(
            title: "Example",
            urlString: "https://example.com/",
            isLoading: true,
            canGoBack: false,
            canGoForward: false
        )

        let resolved = WorkspaceBrowserProjectionPolicy.resolve(existing: nil, runtime: runtime)

        XCTAssertEqual(resolved.title, "Example")
        XCTAssertEqual(resolved.urlString, "https://example.com/")
        XCTAssertTrue(resolved.isLoading)
        XCTAssertFalse(resolved.suppressedProjectionWhileLoading)
    }

    func testResolveAppliesFinalURLWhenLoadingEnds() {
        let existing = WorkspaceBrowserState(
            surfaceId: "surface:1",
            projectPath: "/tmp/browser-policy",
            tabId: "tab:1",
            paneId: "pane:1",
            title: "www.baidu.com",
            urlString: "https://www.baidu.com/",
            isLoading: true
        )
        let runtime = WorkspaceBrowserRuntimeSnapshot(
            title: "www.baidu.com",
            urlString: "https://www.baidu.com/",
            isLoading: false,
            canGoBack: false,
            canGoForward: false
        )

        let resolved = WorkspaceBrowserProjectionPolicy.resolve(existing: existing, runtime: runtime)

        XCTAssertEqual(resolved.urlString, "https://www.baidu.com/")
        XCTAssertFalse(resolved.isLoading)
        XCTAssertFalse(resolved.suppressedProjectionWhileLoading)
    }
}
