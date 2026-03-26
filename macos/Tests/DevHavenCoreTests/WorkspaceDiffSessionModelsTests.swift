import XCTest
@testable import DevHavenCore

final class WorkspaceDiffSessionModelsTests: XCTestCase {
    func testRequestChainKeepsActiveIndexWithinBounds() {
        let single = WorkspaceDiffRequestChain(
            items: [makeItem(id: "one", filePath: "README.md")],
            activeIndex: 9
        )

        XCTAssertEqual(single.activeIndex, 0)
        XCTAssertEqual(single.activeItem?.id, "one")

        let lowerBound = WorkspaceDiffRequestChain(
            items: [
                makeItem(id: "one", filePath: "README.md"),
                makeItem(id: "two", filePath: "Package.swift"),
            ],
            activeIndex: -4
        )

        XCTAssertEqual(lowerBound.activeIndex, 0)
        XCTAssertEqual(lowerBound.activeItem?.id, "one")

        let upperBound = WorkspaceDiffRequestChain(
            items: [
                makeItem(id: "one", filePath: "README.md"),
                makeItem(id: "two", filePath: "Package.swift"),
            ],
            activeIndex: 99
        )

        XCTAssertEqual(upperBound.activeIndex, 1)
        XCTAssertEqual(upperBound.activeItem?.id, "two")
    }

    func testNavigatorStateDisablesNextAtChainEnd() {
        let chain = WorkspaceDiffRequestChain(
            items: [
                makeItem(id: "one", filePath: "README.md"),
                makeItem(id: "two", filePath: "Package.swift"),
            ],
            activeIndex: 1
        )

        let terminalState = WorkspaceDiffNavigatorState(
            requestChain: chain,
            currentDifferenceIndex: 2,
            totalDifferences: 2
        )

        XCTAssertEqual(terminalState.currentDifferenceIndex, 2)
        XCTAssertEqual(terminalState.totalDifferences, 2)
        XCTAssertEqual(terminalState.currentRequestIndex, 2)
        XCTAssertEqual(terminalState.totalRequests, 2)
        XCTAssertFalse(terminalState.canGoNext)
        XCTAssertTrue(terminalState.canGoPrevious)

        let emptyState = WorkspaceDiffNavigatorState(
            requestChain: WorkspaceDiffRequestChain(
                items: [makeItem(id: "one", filePath: "README.md")],
                activeIndex: 0
            ),
            currentDifferenceIndex: 0,
            totalDifferences: 0
        )

        XCTAssertEqual(emptyState.currentDifferenceIndex, 0)
        XCTAssertEqual(emptyState.totalDifferences, 0)
        XCTAssertFalse(emptyState.canGoNext)
        XCTAssertFalse(emptyState.canGoPrevious)
    }

    private func makeItem(id: String, filePath: String) -> WorkspaceDiffRequestItem {
        WorkspaceDiffRequestItem(
            id: id,
            title: filePath,
            source: .workingTreeChange(
                repositoryPath: "/tmp/repo",
                executionPath: "/tmp/repo",
                filePath: filePath,
                group: .unstaged,
                status: .modified,
                oldPath: nil
            ),
            preferredViewerMode: .sideBySide
        )
    }
}
