import XCTest
@testable import DevHavenApp

@MainActor
final class GhosttyAppRuntimeTests: XCTestCase {
    func testSharedExposesBundledGhosttyResourcesDirectory() {
        let runtime = GhosttyAppRuntime.shared

        XCTAssertNotNil(runtime.resourcesDirectoryURL)
        XCTAssertEqual(runtime.resourcesDirectoryURL?.lastPathComponent, "ghostty")
        XCTAssertTrue(runtime.resourcesDirectoryURL?.path.contains("GhosttyResources") == true)
    }

    func testSharedReturnsSameRuntimeInstance() {
        XCTAssertTrue(GhosttyAppRuntime.shared === GhosttyAppRuntime.shared)
    }
}
