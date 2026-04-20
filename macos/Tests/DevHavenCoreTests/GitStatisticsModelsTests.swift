import XCTest
@testable import DevHavenCore

final class GitStatisticsModelsTests: XCTestCase {
    func testRefreshSummaryCountsRequestedUpdatedAndFailedResults() {
        let summary = GitStatisticsRefreshSummary(results: [
            GitDailyRefreshResult(path: "/repo/a", gitDaily: "2026-04-20:1", error: nil),
            GitDailyRefreshResult(path: "/repo/b", gitDaily: nil, error: "not a git repo"),
            GitDailyRefreshResult(path: "/repo/c", gitDaily: "2026-04-20:3", error: nil),
        ])

        XCTAssertEqual(summary.requestedRepositories, 3)
        XCTAssertEqual(summary.updatedRepositories, 2)
        XCTAssertEqual(summary.failedRepositories, 1)
    }

    func testRefreshSummaryHandlesEmptyResults() {
        let summary = GitStatisticsRefreshSummary(results: [])

        XCTAssertEqual(summary.requestedRepositories, 0)
        XCTAssertEqual(summary.updatedRepositories, 0)
        XCTAssertEqual(summary.failedRepositories, 0)
    }
}
