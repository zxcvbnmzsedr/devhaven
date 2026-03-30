import XCTest
import DevHavenCore
@testable import DevHavenApp

final class WorkspaceTextEditorLineMetricsTests: XCTestCase {
    func testLineStartOffsetsPreserveTrailingEmptyLine() {
        let content = "alpha\nbeta\n" as NSString

        let offsets = WorkspaceTextEditorLineMetrics.lineStartOffsets(in: content)

        XCTAssertEqual(offsets, [0, 6, 11])
    }

    func testLineIndexMapsCharacterLocationsIntoLogicalLines() {
        let content = "alpha\nbeta\ngamma" as NSString
        let offsets = WorkspaceTextEditorLineMetrics.lineStartOffsets(in: content)

        XCTAssertEqual(
            WorkspaceTextEditorLineMetrics.lineIndex(forCharacterLocation: 0, lineStartOffsets: offsets),
            0
        )
        XCTAssertEqual(
            WorkspaceTextEditorLineMetrics.lineIndex(forCharacterLocation: 6, lineStartOffsets: offsets),
            1
        )
        XCTAssertEqual(
            WorkspaceTextEditorLineMetrics.lineIndex(forCharacterLocation: content.length, lineStartOffsets: offsets),
            2
        )
    }

    func testVisibleLineRangeRespectsInsetAndClampsToTotalLineCount() {
        let visible = WorkspaceTextEditorLineMetrics.visibleLineRange(
            contentOffsetY: 30,
            viewportHeight: 54,
            insetTop: 12,
            lineHeight: 18,
            totalLineCount: 5
        )

        XCTAssertEqual(visible, 1...4)
    }

    func testGutterWidthExpandsWhenLineDigitsIncrease() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        let singleDigit = WorkspaceTextEditorLineMetrics.gutterWidth(lineCount: 9, font: font)
        let tripleDigit = WorkspaceTextEditorLineMetrics.gutterWidth(lineCount: 10_000, font: font)

        XCTAssertGreaterThan(tripleDigit, singleDigit)
    }

    func testGutterWidthExpandsForMarkupLanes() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        let baseWidth = WorkspaceTextEditorLineMetrics.gutterWidth(lineCount: 99, font: font)
        let expandedWidth = WorkspaceTextEditorLineMetrics.gutterWidth(
            lineCount: 99,
            font: font,
            markupMarkers: [
                WorkspaceEditorMarkupMarker(
                    id: "change",
                    kind: .added,
                    lineRange: WorkspaceDiffLineRange(startLine: 4, lineCount: 1),
                    lane: .lineStatus,
                    showsInGutter: true
                ),
                WorkspaceEditorMarkupMarker(
                    id: "icon",
                    kind: .breakpoint,
                    lineRange: WorkspaceDiffLineRange(startLine: 6, lineCount: 1),
                    lane: .icons,
                    icon: .circle,
                    showsInGutter: true
                ),
                WorkspaceEditorMarkupMarker(
                    id: "annotation",
                    kind: .info,
                    lineRange: WorkspaceDiffLineRange(startLine: 8, lineCount: 1),
                    lane: .annotations,
                    annotationText: "status",
                    showsInGutter: true
                ),
            ]
        )

        XCTAssertGreaterThan(expandedWidth, baseWidth)
    }

    func testMarkupModelCombinesDiffHighlightsAndSearchMatches() {
        let content = "alpha\nbeta\ngamma\nalpha" as NSString
        let offsets = WorkspaceTextEditorLineMetrics.lineStartOffsets(in: content)

        let markup = workspaceTextEditorMarkupModel(
            highlights: [
                WorkspaceDiffEditorHighlight(
                    kind: .changed,
                    lineRange: WorkspaceDiffLineRange(startLine: 1, lineCount: 1)
                ),
            ],
            searchQuery: "alpha",
            in: content,
            lineStartOffsets: offsets,
            isSearchCaseSensitive: true,
            matchesWholeWords: false,
            usesRegularExpression: false
        )

        XCTAssertEqual(markup.overviewMarkers.count, 3)
        XCTAssertTrue(markup.overviewMarkers.contains(where: {
            $0.kind == .changed && $0.lineRange == WorkspaceDiffLineRange(startLine: 1, lineCount: 1)
        }))
        XCTAssertEqual(markup.overviewMarkers.filter { $0.kind == .searchMatch }.count, 2)
        XCTAssertEqual(markup.gutterMarkers.count, 1)
        XCTAssertEqual(markup.gutterMarkers.first?.lane, .lineStatus)
        XCTAssertEqual(markup.gutterMarkers.first?.kind, .changed)
    }
}
