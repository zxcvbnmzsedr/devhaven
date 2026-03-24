import XCTest
@testable import DevHavenApp

final class GhosttySurfaceBridgeOpenURLTests: XCTestCase {
    func testResolvedOpenURLPreservesHTTPURL() {
        let url = GhosttySurfaceBridge.resolvedOpenURL(
            from: "https://github.com/zxcvbnmzsedr/devhaven/issues/42",
            workingDirectory: nil
        )

        XCTAssertEqual(url?.absoluteString, "https://github.com/zxcvbnmzsedr/devhaven/issues/42")
        XCTAssertFalse(url?.isFileURL ?? true)
    }

    func testResolvedOpenURLTreatsAbsolutePathAsFileURL() {
        let path = "/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/.build/native-app/release/DevHaven.app"

        let url = GhosttySurfaceBridge.resolvedOpenURL(from: path, workingDirectory: nil)

        XCTAssertEqual(url?.path, path)
        XCTAssertTrue(url?.isFileURL ?? false)
    }

    func testResolvedOpenURLExtractsAbsolutePathFromShellAssignment() {
        let path = "/Users/zhaotianzeng/WebstormProjects/DevHaven/macos/.build/native-app/release"

        let url = GhosttySurfaceBridge.resolvedOpenURL(from: "OUTPUT_DIR=\(path)", workingDirectory: nil)

        XCTAssertEqual(url?.path, path)
        XCTAssertTrue(url?.isFileURL ?? false)
    }

    func testResolvedOpenURLResolvesRelativePathAgainstWorkingDirectory() {
        let workingDirectory = "/Users/zhaotianzeng/WebstormProjects/DevHaven/macos"

        let url = GhosttySurfaceBridge.resolvedOpenURL(
            from: "./.build/native-app/release",
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(url?.path, workingDirectory + "/.build/native-app/release")
        XCTAssertTrue(url?.isFileURL ?? false)
    }
}
