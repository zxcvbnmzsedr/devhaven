import XCTest
@testable import DevHavenCore

final class WorkspaceDiffPaneMetadataModelsTests: XCTestCase {
    func testPaneMetadataOmitsMissingDetailsWithoutFabricatingPlaceholders() {
        let metadata = WorkspaceDiffPaneMetadata(
            title: "HEAD",
            path: "Sources/App.swift",
            oldPath: nil,
            revision: nil,
            hash: nil,
            author: nil,
            timestamp: nil,
            copyPayloads: []
        )

        XCTAssertEqual(metadata.title, "HEAD")
        XCTAssertEqual(metadata.path, "Sources/App.swift")
        XCTAssertNil(metadata.oldPath)
        XCTAssertTrue(metadata.primaryDetails.isEmpty)
        XCTAssertTrue(metadata.secondaryDetails.isEmpty)
        XCTAssertTrue(metadata.copyPayloads.isEmpty)
        XCTAssertNil(metadata.tooltip)
    }
}
