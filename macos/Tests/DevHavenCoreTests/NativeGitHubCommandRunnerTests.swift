import XCTest
@testable import DevHavenCore

final class NativeGitHubCommandRunnerTests: XCTestCase {
    func testNormalizedSearchPathAppendsCommonBrewLocations() {
        let normalized = NativeGitHubCommandRunner.normalizedSearchPath(
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        )
        let entries = normalized.split(separator: ":").map(String.init)

        XCTAssertTrue(entries.contains("/opt/homebrew/bin"))
        XCTAssertTrue(entries.contains("/usr/local/bin"))
        XCTAssertEqual(entries.filter { $0 == "/usr/bin" }.count, 1)
    }

    func testResolveExecutablePathFindsGhInSearchPath() {
        let resolved = NativeGitHubCommandRunner.resolveExecutablePath(
            searchPath: "/usr/bin:/opt/homebrew/bin:/usr/local/bin",
            isExecutableFile: { path in
                path == "/opt/homebrew/bin/gh"
            }
        )

        XCTAssertEqual(resolved, "/opt/homebrew/bin/gh")
    }
}
