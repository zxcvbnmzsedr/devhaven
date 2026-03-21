import XCTest
@testable import DevHavenApp

@MainActor
final class GhosttyRuntimeConfigLoaderTests: XCTestCase {
    func testPreferredConfigFileURLsFallbackToStandaloneGhosttyConfigWhenDevHavenConfigMissing() throws {
        let homeURL = try makeTemporaryDirectory()
        let standaloneConfigURL = homeURL
            .appending(path: "Library/Application Support/com.mitchellh.ghostty/config", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: standaloneConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "font-family = Hack\n".write(to: standaloneConfigURL, atomically: true, encoding: .utf8)

        let urls = GhosttyRuntime.preferredConfigFileURLs(
            fileManager: FileManager.default,
            homeDirectoryURL: homeURL
        )

        XCTAssertEqual(urls, [standaloneConfigURL])
    }

    func testPreferredConfigFileURLsPreferDevHavenSpecificConfigOverStandaloneGhosttyConfig() throws {
        let homeURL = try makeTemporaryDirectory()
        let devHavenConfigURL = homeURL
            .appending(path: ".devhaven/ghostty/config", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: devHavenConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "theme = tokyonight\n".write(to: devHavenConfigURL, atomically: true, encoding: .utf8)

        let standaloneConfigURL = homeURL
            .appending(path: "Library/Application Support/com.mitchellh.ghostty/config", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: standaloneConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "theme = iTerm2 Solarized Dark\n".write(to: standaloneConfigURL, atomically: true, encoding: .utf8)

        let urls = GhosttyRuntime.preferredConfigFileURLs(
            fileManager: FileManager.default,
            homeDirectoryURL: homeURL
        )

        XCTAssertEqual(urls, [devHavenConfigURL])
    }

    func testEnsureEditableConfigFileFallsBackToStandaloneGhosttyConfigWhenDevHavenConfigMissing() throws {
        let homeURL = try makeTemporaryDirectory()
        let standaloneConfigURL = homeURL
            .appending(path: "Library/Application Support/com.mitchellh.ghostty/config.ghostty", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: standaloneConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "font-size = 14\n".write(to: standaloneConfigURL, atomically: true, encoding: .utf8)

        let url = try GhosttyRuntime.ensureEditableConfigFile(
            fileManager: FileManager.default,
            homeDirectoryURL: homeURL
        )

        XCTAssertEqual(url, standaloneConfigURL)
    }

    func testEnsureEditableConfigFileCreatesDevHavenConfigWhenNoConfigExists() throws {
        let homeURL = try makeTemporaryDirectory()

        let url = try GhosttyRuntime.ensureEditableConfigFile(
            fileManager: FileManager.default,
            homeDirectoryURL: homeURL
        )

        XCTAssertEqual(
            url,
            homeURL.appending(path: ".devhaven/ghostty/config", directoryHint: .notDirectory)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
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
