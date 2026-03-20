import XCTest
@testable import DevHavenApp

@MainActor
final class GhosttyAppRuntimeBundleLocatorTests: XCTestCase {
    func testResolveResourceBundleURLPrefersAppContentsResourcesBundle() throws {
        let rootURL = try makeTemporaryDirectory()
        let appURL = rootURL.appending(path: "DevHaven.app", directoryHint: .isDirectory)
        let resourcesURL = appURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let bundleURL = resourcesURL.appending(path: GhosttyAppRuntime.resourceBundleName, directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let mainBundle = Bundle(path: appURL.path)
        XCTAssertNotNil(mainBundle)

        let resolved = GhosttyAppRuntime.resolveResourceBundleURL(mainBundle: try XCTUnwrap(mainBundle))

        XCTAssertEqual(resolved?.path, bundleURL.path)
    }

    func testResolveResourceBundleURLFallsBackToSiblingOfMainBundle() throws {
        let rootURL = try makeTemporaryDirectory()
        let xctestURL = rootURL.appending(path: "DevHavenNativePackageTests.xctest", directoryHint: .isDirectory)
        let siblingBundleURL = rootURL.appending(path: GhosttyAppRuntime.resourceBundleName, directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: xctestURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: siblingBundleURL, withIntermediateDirectories: true)

        let mainBundle = Bundle(path: xctestURL.path)
        XCTAssertNotNil(mainBundle)

        let resolved = GhosttyAppRuntime.resolveResourceBundleURL(mainBundle: try XCTUnwrap(mainBundle))

        XCTAssertEqual(resolved?.path, siblingBundleURL.path)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        return rootURL
    }
}
