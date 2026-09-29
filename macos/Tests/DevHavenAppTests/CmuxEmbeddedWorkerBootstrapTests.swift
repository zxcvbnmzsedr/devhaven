import XCTest
@testable import DevHavenApp

final class CmuxEmbeddedWorkerBootstrapTests: XCTestCase {
    func testNormalStartupDoesNotRunPasteWorker() {
        let status = CmuxEmbeddedWorkerBootstrap.exitCodeIfRequested(arguments: ["DevHavenApp"]) {
            XCTFail("Normal startup must not invoke a clipboard worker")
            return 0
        }
        XCTAssertNil(status)
    }

    func testPasteWorkerReturnsItsExitStatusInsteadOfStartingApp() {
        var calls = 0
        let status = CmuxEmbeddedWorkerBootstrap.exitCodeIfRequested(
            arguments: ["DevHavenApp", "--cmux-paste-preparation-worker"]
        ) {
            calls += 1
            return 64
        }
        XCTAssertEqual(status, 64)
        XCTAssertEqual(calls, 1)
    }

    func testSuccessfulWorkerStillExitsBeforeAppStartup() {
        XCTAssertEqual(
            CmuxEmbeddedWorkerBootstrap.exitCodeIfRequested(
                arguments: ["DevHavenApp", "--cmux-paste-preparation-worker"],
                runWorker: { 0 }
            ),
            0
        )
    }

    func testMissingWorkerSymbolFailsWithoutOpeningApp() {
        XCTAssertEqual(
            CmuxEmbeddedWorkerBootstrap.exitCodeIfRequested(
                arguments: ["DevHavenApp", "--cmux-paste-preparation-worker"],
                runWorker: { nil }
            ),
            78
        )
    }
}
