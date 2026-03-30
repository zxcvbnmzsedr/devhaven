import XCTest
import DevHavenCore
@testable import DevHavenApp

final class WorkspaceTextEditorMarkupTests: XCTestCase {
    func testMarkupModelBuildsOverviewAndChangeGutterMarkersFromDiffHighlights() {
        let content = "alpha\nbeta\ngamma" as NSString
        let offsets = WorkspaceTextEditorLineMetrics.lineStartOffsets(in: content)

        let markup = workspaceTextEditorMarkupModel(
            highlights: [
                WorkspaceDiffEditorHighlight(
                    kind: .added,
                    lineRange: WorkspaceDiffLineRange(startLine: 0, lineCount: 1)
                ),
                WorkspaceDiffEditorHighlight(
                    kind: .conflict,
                    lineRange: WorkspaceDiffLineRange(startLine: 2, lineCount: 1)
                ),
            ],
            searchQuery: "",
            in: content,
            lineStartOffsets: offsets,
            isSearchCaseSensitive: true,
            matchesWholeWords: false,
            usesRegularExpression: false
        )

        XCTAssertEqual(markup.overviewMarkers.map(\.kind), [.added, .conflict])
        XCTAssertEqual(markup.gutterMarkers.map(\.lane), [.lineStatus, .lineStatus])
        XCTAssertEqual(markup.gutterMarkers.map(\.kind), [.added, .conflict])
        XCTAssertEqual(markup.gutterMarkers.map(\.lineRange.startLine), [0, 2])
    }

    func testMarkupModelKeepsSearchMatchesInOverviewOnly() {
        let content = "alpha\nbeta\nalpha" as NSString
        let offsets = WorkspaceTextEditorLineMetrics.lineStartOffsets(in: content)

        let markup = workspaceTextEditorMarkupModel(
            highlights: [],
            searchQuery: "alpha",
            in: content,
            lineStartOffsets: offsets,
            isSearchCaseSensitive: true,
            matchesWholeWords: false,
            usesRegularExpression: false
        )

        XCTAssertEqual(markup.overviewMarkers.count, 2)
        XCTAssertEqual(markup.overviewMarkers.map(\.kind), [.searchMatch, .searchMatch])
        XCTAssertEqual(markup.overviewMarkers.map(\.lineRange.startLine), [0, 2])
        XCTAssertTrue(markup.gutterMarkers.isEmpty)
    }

    func testGutterWidthExpandsForMarkupLanes() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let baseline = WorkspaceTextEditorLineMetrics.gutterWidth(lineCount: 120, font: font)
        let markupWidth = WorkspaceTextEditorLineMetrics.gutterWidth(
            lineCount: 120,
            font: font,
            markupMarkers: [
                WorkspaceEditorMarkupMarker(
                    id: "change",
                    kind: .changed,
                    lineRange: WorkspaceDiffLineRange(startLine: 3, lineCount: 1),
                    lane: .lineStatus,
                    showsInOverview: true,
                    showsInGutter: true
                ),
                WorkspaceEditorMarkupMarker(
                    id: "bookmark",
                    kind: .bookmark,
                    lineRange: WorkspaceDiffLineRange(startLine: 8, lineCount: 1),
                    lane: .icons,
                    icon: .bookmark,
                    showsInOverview: false,
                    showsInGutter: true
                ),
            ]
        )

        XCTAssertGreaterThan(markupWidth, baseline)
    }

    func testMarkupModelAppendsExplicitMarkupMarkers() {
        let content = "alpha\nbeta\ngamma" as NSString
        let offsets = WorkspaceTextEditorLineMetrics.lineStartOffsets(in: content)
        let explicitMarker = WorkspaceEditorMarkupMarker(
            id: "bookmark",
            kind: .bookmark,
            lineRange: WorkspaceDiffLineRange(startLine: 2, lineCount: 1),
            lane: .icons,
            icon: .bookmark,
            showsInOverview: false,
            showsInGutter: true
        )

        let markup = workspaceTextEditorMarkupModel(
            highlights: [
                WorkspaceDiffEditorHighlight(
                    kind: .added,
                    lineRange: WorkspaceDiffLineRange(startLine: 0, lineCount: 1)
                ),
            ],
            additionalMarkers: [explicitMarker],
            searchQuery: "",
            in: content,
            lineStartOffsets: offsets,
            isSearchCaseSensitive: true,
            matchesWholeWords: false,
            usesRegularExpression: false
        )

        XCTAssertEqual(markup.overviewMarkers.map(\.kind), [.added])
        XCTAssertEqual(markup.gutterMarkers.map(\.kind), [.added, .bookmark])
        XCTAssertEqual(markup.gutterMarkers.last?.lane, .icons)
    }

    func testPreferredGutterMarkersPicksHighestPriorityPerLineAndLane() {
        let markers = workspaceTextEditorPreferredGutterMarkers(
            [
                WorkspaceEditorMarkupMarker(
                    id: "low",
                    kind: .info,
                    lineRange: WorkspaceDiffLineRange(startLine: 2, lineCount: 1),
                    lane: .icons,
                    priority: 1,
                    icon: .circle,
                    showsInOverview: false,
                    showsInGutter: true
                ),
                WorkspaceEditorMarkupMarker(
                    id: "high",
                    kind: .breakpoint,
                    lineRange: WorkspaceDiffLineRange(startLine: 2, lineCount: 1),
                    lane: .icons,
                    priority: 10,
                    icon: .circle,
                    showsInOverview: false,
                    showsInGutter: true
                ),
            ],
            for: .icons
        )

        XCTAssertEqual(markers.map(\.id), ["high"])
    }
}
