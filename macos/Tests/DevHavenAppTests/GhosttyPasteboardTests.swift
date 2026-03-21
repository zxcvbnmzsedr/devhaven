import AppKit
import XCTest
@testable import DevHavenApp

@MainActor
final class GhosttyPasteboardTests: XCTestCase {
    func testOpinionatedStringContentsPrefersEscapedFileURLPaths() throws {
        let rootURL = try makeTemporaryDirectory()
        let fileURL = rootURL.appending(path: "Screen Shot 2026-03-21.png", directoryHint: .notDirectory)
        try Data("png".utf8).write(to: fileURL)

        let pasteboard = NSPasteboard(name: .init("devhaven-test-file-url-\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([fileURL as NSURL]))

        XCTAssertEqual(
            pasteboard.getOpinionatedStringContents(),
            fileURL.path.replacingOccurrences(of: " ", with: "\\ ")
        )
    }

    func testOpinionatedStringContentsFallsBackToUTF8PlainText() {
        let pasteboard = NSPasteboard(name: .init("devhaven-test-utf8-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let utf8Type = NSPasteboard.PasteboardType("public.utf8-plain-text")
        pasteboard.setString("/tmp/from-utf8-plain-text.png", forType: utf8Type)

        XCTAssertEqual(
            pasteboard.getOpinionatedStringContents(),
            "/tmp/from-utf8-plain-text.png"
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
