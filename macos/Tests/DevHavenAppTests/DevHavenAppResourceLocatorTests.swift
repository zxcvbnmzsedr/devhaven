import XCTest
@testable import DevHavenApp

@MainActor
final class DevHavenAppResourceLocatorTests: XCTestCase {
    func testResolveAgentResourcesURLPrefersAppContentsResourcesBundle() throws {
        let rootURL = try makeTemporaryDirectory()
        let appURL = rootURL.appending(path: "DevHaven.app", directoryHint: .isDirectory)
        let resourcesURL = appURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let bundleURL = resourcesURL.appending(path: DevHavenAppResourceLocator.resourceBundleName, directoryHint: .isDirectory)
        let agentResourcesURL = bundleURL.appending(path: "AgentResources", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: agentResourcesURL, withIntermediateDirectories: true)

        let mainBundle = try XCTUnwrap(Bundle(path: appURL.path))
        let resolved = DevHavenAppResourceLocator.resolveAgentResourcesURL(mainBundle: mainBundle)

        XCTAssertEqual(resolved?.path, agentResourcesURL.path)
    }

    func testResolveAgentResourcesURLFallsBackToSiblingOfMainBundle() throws {
        let rootURL = try makeTemporaryDirectory()
        let xctestURL = rootURL.appending(path: "DevHavenNativePackageTests.xctest", directoryHint: .isDirectory)
        let siblingBundleURL = rootURL.appending(path: DevHavenAppResourceLocator.resourceBundleName, directoryHint: .isDirectory)
        let agentResourcesURL = siblingBundleURL.appending(path: "AgentResources", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: xctestURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agentResourcesURL, withIntermediateDirectories: true)

        let mainBundle = try XCTUnwrap(Bundle(path: xctestURL.path))
        let resolved = DevHavenAppResourceLocator.resolveAgentResourcesURL(mainBundle: mainBundle)

        XCTAssertEqual(resolved?.path, agentResourcesURL.path)
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
