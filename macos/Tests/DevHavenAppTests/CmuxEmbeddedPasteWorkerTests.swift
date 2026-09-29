import AppKit
import XCTest

@MainActor
final class CmuxEmbeddedPasteWorkerTests: XCTestCase {
    func testHostExecutablePreparesTextWithoutStartingApplication() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let marker = "DevHaven 粘贴回归测试 — no newline submission"
        pasteboard.setString(marker, forType: .string)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-paste-preparation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let request: [String: Any] = [
            "pasteboard": ["pasteboardName": pasteboard.name.rawValue, "changeCount": pasteboard.changeCount],
            "mode": ["paste": [:]],
            "destination": ["terminal": [:]],
        ]
        try JSONSerialization.data(withJSONObject: request)
            .write(to: directory.appendingPathComponent("request.json"))

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "--cmux-paste-preparation-worker",
            "--cmux-paste-preparation-working-directory", directory.path,
        ]
        // The upstream worker monitors stdin EOF for parent death.
        let liveness = Pipe()
        process.standardInput = liveness
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = expectation(description: "Paste worker exits without launching SwiftUI")
        process.terminationHandler = { _ in finished.fulfill() }
        try process.run()
        defer {
            if process.isRunning { process.terminate() }
            try? liveness.fileHandleForWriting.close()
        }
        await fulfillment(of: [finished], timeout: 8)
        guard !process.isRunning else { return }
        XCTAssertEqual(process.terminationStatus, 0)
        let payloadURL = directory.appendingPathComponent("text-payload.txt")
        XCTAssertEqual(try String(contentsOf: payloadURL, encoding: .utf8), marker)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("response.json").path))
    }

    func testMalformedWorkerRequestExitsInsteadOfOpeningHomePage() async throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--cmux-paste-preparation-worker"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = expectation(description: "Invalid worker request exits")
        process.terminationHandler = { _ in finished.fulfill() }
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        await fulfillment(of: [finished], timeout: 8)
        guard !process.isRunning else { return }
        XCTAssertEqual(process.terminationStatus, 64)
    }

    private var executableURL: URL {
        if let path = ProcessInfo.processInfo.environment["DEVHAVEN_TEST_APP_EXECUTABLE"] {
            return URL(fileURLWithPath: path)
        }
        // SwiftPM places the App executable next to this test bundle.
        return Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("DevHavenApp")
    }
}
