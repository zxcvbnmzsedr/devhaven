import AppKit
import XCTest
@testable import DevHavenApp

final class GhosttyPasteboardTests: XCTestCase {
    func testGetOpinionatedStringContentsEscapesFileURLs() {
        let pasteboard = makePasteboard()
        let urls = [
            URL(fileURLWithPath: "/tmp/space name/file(1).txt"),
            URL(fileURLWithPath: "/tmp/regular.txt"),
        ]

        XCTAssertTrue(pasteboard.writeObjects(urls as [NSURL]))
        XCTAssertTrue(pasteboard.hasOpinionatedStringContents())
        XCTAssertEqual(
            pasteboard.getOpinionatedStringContents(),
            urls
                .map(\.path)
                .map(NSPasteboard.ghosttyEscape)
                .joined(separator: " ")
        )
    }

    func testGetOpinionatedStringContentsFallsBackToPlainText() {
        let pasteboard = makePasteboard()

        XCTAssertTrue(pasteboard.setString("echo hello", forType: .string))
        XCTAssertTrue(pasteboard.hasOpinionatedStringContents())
        XCTAssertEqual(pasteboard.getOpinionatedStringContents(), "echo hello")
    }
}

private func makePasteboard() -> NSPasteboard {
    let pasteboard = NSPasteboard(name: .init("devhaven-ghostty-tests-\(UUID().uuidString)"))
    pasteboard.clearContents()
    return pasteboard
}
