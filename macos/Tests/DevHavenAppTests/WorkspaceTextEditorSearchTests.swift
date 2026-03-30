import XCTest
@testable import DevHavenApp

final class WorkspaceTextEditorSearchTests: XCTestCase {
    func testBaseDecorationSignatureIgnoresSelectionChanges() {
        let first = WorkspaceTextEditorDecorationSignature(
            contentRevision: 7,
            syntaxStyle: .swift,
            highlights: [],
            inlineHighlights: []
        )
        let second = WorkspaceTextEditorDecorationSignature(
            contentRevision: 7,
            syntaxStyle: .swift,
            highlights: [],
            inlineHighlights: []
        )

        XCTAssertEqual(first, second)
    }

    func testBaseDecorationSignatureTracksContentRevisionChanges() {
        let first = WorkspaceTextEditorDecorationSignature(
            contentRevision: 7,
            syntaxStyle: .swift,
            highlights: [],
            inlineHighlights: []
        )
        let second = WorkspaceTextEditorDecorationSignature(
            contentRevision: 8,
            syntaxStyle: .swift,
            highlights: [],
            inlineHighlights: []
        )

        XCTAssertNotEqual(first, second)
    }

    func testSearchHighlightSignatureTracksSelectionChangesSeparately() {
        let first = WorkspaceTextEditorSearchHighlightSignature(
            contentRevision: 1,
            query: "alpha",
            isSearchCaseSensitive: true,
            matchesWholeWords: false,
            usesRegularExpression: false,
            selectedRange: NSRange(location: 0, length: 5)
        )
        let second = WorkspaceTextEditorSearchHighlightSignature(
            contentRevision: 1,
            query: "alpha",
            isSearchCaseSensitive: true,
            matchesWholeWords: false,
            usesRegularExpression: false,
            selectedRange: NSRange(location: 11, length: 5)
        )

        XCTAssertNotEqual(first, second)
    }

    func testEffectiveSearchHighlightSignatureIgnoresSelectionWhenQueryIsEmpty() {
        let first = workspaceTextEditorEffectiveSearchHighlightSignature(
            contentRevision: 1,
            query: "",
            isCaseSensitive: true,
            matchesWholeWords: true,
            usesRegularExpression: true,
            selectedRange: NSRange(location: 0, length: 0)
        )
        let second = workspaceTextEditorEffectiveSearchHighlightSignature(
            contentRevision: 99,
            query: "",
            isCaseSensitive: false,
            matchesWholeWords: false,
            usesRegularExpression: false,
            selectedRange: NSRange(location: 42, length: 3)
        )

        XCTAssertEqual(first, second)
    }

    func testNextMatchWrapsAfterCurrentSelection() {
        let content = "alpha beta alpha" as NSString
        let selected = NSRange(location: 11, length: 5)

        let range = workspaceTextEditorNextMatch(
            query: "alpha",
            in: content,
            selectedRange: selected,
            isCaseSensitive: true,
            matchesWholeWords: false,
            usesRegularExpression: false
        )

        XCTAssertEqual(range, NSRange(location: 0, length: 5))
    }

    func testPreviousMatchWrapsToLastOccurrence() {
        let content = "alpha beta alpha" as NSString
        let selected = NSRange(location: 0, length: 5)

        let range = workspaceTextEditorPreviousMatch(
            query: "alpha",
            in: content,
            selectedRange: selected,
            isCaseSensitive: true,
            matchesWholeWords: false,
            usesRegularExpression: false
        )

        XCTAssertEqual(range, NSRange(location: 11, length: 5))
    }

    func testReplaceAllHonorsCaseSensitivity() {
        let content = "Alpha alpha ALPHA" as NSString

        let insensitive = workspaceTextEditorReplaceAll(
            query: "alpha",
            replacement: "beta",
            in: content,
            isCaseSensitive: false,
            matchesWholeWords: false,
            usesRegularExpression: false,
            preservesReplacementCase: false
        )
        let sensitive = workspaceTextEditorReplaceAll(
            query: "alpha",
            replacement: "beta",
            in: content,
            isCaseSensitive: true,
            matchesWholeWords: false,
            usesRegularExpression: false,
            preservesReplacementCase: false
        )

        XCTAssertEqual(insensitive.text, "beta beta beta")
        XCTAssertEqual(insensitive.replacementCount, 3)
        XCTAssertEqual(sensitive.text, "Alpha beta ALPHA")
        XCTAssertEqual(sensitive.replacementCount, 1)
    }

    func testWholeWordSearchSkipsEmbeddedMatches() {
        let content = "alpha alphabet alpha_beta alpha" as NSString

        let ranges = workspaceTextEditorMatchRanges(
            query: "alpha",
            in: content,
            isCaseSensitive: true,
            matchesWholeWords: true,
            usesRegularExpression: false
        )

        XCTAssertEqual(ranges, [
            NSRange(location: 0, length: 5),
            NSRange(location: 26, length: 5),
        ])
    }

    func testRegexSearchMatchesPatternOccurrences() {
        let content = "foo1 foo22 bar333" as NSString

        let ranges = workspaceTextEditorMatchRanges(
            query: #"foo\d+"#,
            in: content,
            isCaseSensitive: true,
            matchesWholeWords: false,
            usesRegularExpression: true
        )

        XCTAssertEqual(ranges, [
            NSRange(location: 0, length: 4),
            NSRange(location: 5, length: 5),
        ])
    }

    func testReplaceAllPreserveCaseAdjustsReplacementToMatchedText() {
        let content = "Alpha alpha ALPHA" as NSString

        let replaced = workspaceTextEditorReplaceAll(
            query: "alpha",
            replacement: "beta",
            in: content,
            isCaseSensitive: false,
            matchesWholeWords: false,
            usesRegularExpression: false,
            preservesReplacementCase: true
        )

        XCTAssertEqual(replaced.text, "Beta beta BETA")
        XCTAssertEqual(replaced.replacementCount, 3)
    }

    func testRegexReplaceAllSupportsCaptureGroups() {
        let content = "foo-123 foo-456" as NSString

        let replaced = workspaceTextEditorReplaceAll(
            query: #"foo-(\d+)"#,
            replacement: #"bar-$1"#,
            in: content,
            isCaseSensitive: true,
            matchesWholeWords: false,
            usesRegularExpression: true,
            preservesReplacementCase: false
        )

        XCTAssertEqual(replaced.text, "bar-123 bar-456")
        XCTAssertEqual(replaced.replacementCount, 2)
    }

    func testSearchSessionStateReportsInvalidRegexError() {
        let content = "alpha beta" as NSString

        let state = workspaceTextEditorSearchSessionState(
            query: "[alpha",
            in: content,
            isCaseSensitive: true,
            matchesWholeWords: false,
            usesRegularExpression: true,
            selectedRange: NSRange(location: 0, length: 0)
        )

        XCTAssertEqual(state.matchCount, 0)
        XCTAssertNil(state.currentMatchIndex)
        XCTAssertNotNil(state.errorMessage)
    }

    func testSearchSessionStateReportsCurrentMatchIndex() {
        let content = "alpha beta alpha" as NSString

        let state = workspaceTextEditorSearchSessionState(
            query: "alpha",
            in: content,
            isCaseSensitive: true,
            matchesWholeWords: false,
            usesRegularExpression: false,
            selectedRange: NSRange(location: 11, length: 5)
        )

        XCTAssertEqual(state.matchCount, 2)
        XCTAssertEqual(state.currentMatchIndex, 2)
        XCTAssertNil(state.errorMessage)
    }
}
