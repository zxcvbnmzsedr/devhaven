import XCTest
@testable import DevHavenApp

final class ProjectSearchHighlightingTests: XCTestCase {
    func testProjectSearchHighlightRangesReturnsEmptyWhenQueryIsBlank() {
        XCTAssertTrue(projectSearchHighlightRanges(in: "Payments", query: "   ").isEmpty)
    }

    func testProjectSearchHighlightRangesMatchesCaseInsensitiveSubstring() {
        let value = "供应商报价聚合与回调排障"
        let ranges = projectSearchHighlightRanges(in: value, query: "报价聚合")

        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(String(value[ranges[0]]), "报价聚合")
    }

    func testProjectSearchHighlightRangesReturnsAllMatches() {
        let value = "alpha beta ALPHA gamma alpha"
        let ranges = projectSearchHighlightRanges(in: value, query: "alpha")

        XCTAssertEqual(ranges.count, 3)
        XCTAssertEqual(ranges.map { String(value[$0]).lowercased() }, ["alpha", "alpha", "alpha"])
    }
}
