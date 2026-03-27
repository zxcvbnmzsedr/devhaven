import XCTest
@testable import DevHavenCore

final class WorkspaceDiffPatchParserTests: XCTestCase {
    func testParserBuildsTextDocumentWithHunksAndLineKinds() {
        let diff = """
        diff --git a/README.md b/README.md
        index 1111111..2222222 100644
        --- a/README.md
        +++ b/README.md
        @@ -1,2 +1,3 @@
         hello
        -before
        +after
        +added
        """

        let document = WorkspaceDiffPatchParser.parse(diff)

        XCTAssertEqual(document.kind, .text)
        XCTAssertEqual(document.oldPath, "README.md")
        XCTAssertEqual(document.newPath, "README.md")
        XCTAssertEqual(document.hunks.count, 1)
        XCTAssertEqual(document.hunks.first?.lines.map(\.kind), [.context, .removed, .added, .added])
    }

    func testParserBuildsSideBySideRowsForModifiedAndAddedLines() throws {
        let diff = """
        diff --git a/README.md b/README.md
        --- a/README.md
        +++ b/README.md
        @@ -1,2 +1,3 @@
         hello
        -before
        +after
        +added
        """

        let document = WorkspaceDiffPatchParser.parse(diff)
        let rows = try XCTUnwrap(document.hunks.first?.sideBySideRows)

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].leftLine?.kind, .context)
        XCTAssertEqual(rows[0].rightLine?.kind, .context)
        XCTAssertEqual(rows[1].leftLine?.kind, .removed)
        XCTAssertEqual(rows[1].rightLine?.kind, .added)
        XCTAssertNil(rows[2].leftLine)
        XCTAssertEqual(rows[2].rightLine?.kind, .added)
    }

    func testParserReturnsEmptyDocumentForBlankDiff() {
        let document = WorkspaceDiffPatchParser.parse("")

        XCTAssertEqual(document.kind, .empty)
        XCTAssertEqual(document.message, "暂无 Diff")
        XCTAssertTrue(document.hunks.isEmpty)
    }

    func testParserReturnsBinaryFallbackForBinaryDiff() {
        let diff = """
        diff --git a/logo.png b/logo.png
        new file mode 100644
        index 0000000..1111111
        Binary files /dev/null and b/logo.png differ
        """

        let document = WorkspaceDiffPatchParser.parse(diff)

        XCTAssertEqual(document.kind, .binary)
        XCTAssertEqual(document.message, "二进制文件 Diff 暂不支持预览")
    }

    func testParserReturnsUnsupportedFallbackForMalformedDiff() {
        let diff = """
        diff --git a/README.md b/README.md
        --- a/README.md
        +++ b/README.md
        @@ malformed header @@
        ???
        """

        let document = WorkspaceDiffPatchParser.parse(diff)

        XCTAssertEqual(document.kind, .unsupported)
        XCTAssertEqual(document.message, "无法解析 Diff")
    }
}
