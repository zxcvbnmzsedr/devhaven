import XCTest
@testable import DevHavenCore

final class WorkspaceFileSystemServiceTests: XCTestCase {
    private var temporaryDirectoryURL: URL!
    private var service: WorkspaceFileSystemService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        service = WorkspaceFileSystemService()
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        service = nil
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testListDirectorySkipsGitAndSortsDirectoriesBeforeFiles() throws {
        let sourceRoot = temporaryDirectoryURL!
        try FileManager.default.createDirectory(
            at: sourceRoot.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try FileManager.default.createDirectory(
            at: sourceRoot.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try "README".write(
            to: sourceRoot.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try "env".write(
            to: sourceRoot.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )

        let nodes = try service.listDirectory(at: sourceRoot.path)

        XCTAssertEqual(nodes.map(\.name), ["Sources", ".env", "README.md"])
        XCTAssertFalse(nodes.contains(where: { $0.name == ".git" }))
        XCTAssertEqual(nodes.first?.kind, .directory)
    }

    func testLoadAndSaveTextDocumentRoundTripsUTF8() throws {
        let fileURL = temporaryDirectoryURL.appendingPathComponent("notes.txt")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let loaded = try service.loadDocument(at: fileURL.path)
        XCTAssertEqual(loaded.kind, .text)
        XCTAssertEqual(loaded.text, "first")
        XCTAssertTrue(loaded.isEditable)

        let saved = try service.saveTextDocument("second", to: fileURL.path)
        XCTAssertEqual(saved.kind, .text)
        XCTAssertEqual(saved.text, "second")
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "second")
    }

    func testLoadDocumentMarksBinaryFileAsUnsupportedTextEditorContent() throws {
        let fileURL = temporaryDirectoryURL.appendingPathComponent("image.bin")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: fileURL)

        let loaded = try service.loadDocument(at: fileURL.path)

        XCTAssertEqual(loaded.kind, .binary)
        XCTAssertFalse(loaded.isEditable)
        XCTAssertNotNil(loaded.message)
    }

    func testCreateRenameAndTrashItemLifecycle() throws {
        let createdDirectory = try service.createDirectory(
            named: "Sources",
            inDirectory: temporaryDirectoryURL.path
        )
        XCTAssertEqual(createdDirectory.kind, .directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdDirectory.path))

        let createdFile = try service.createFile(
            named: "main.swift",
            inDirectory: createdDirectory.path
        )
        XCTAssertEqual(createdFile.kind, .file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdFile.path))

        let renamedFile = try service.renameItem(at: createdFile.path, to: "App.swift")
        XCTAssertEqual(renamedFile.name, "App.swift")
        XCTAssertFalse(FileManager.default.fileExists(atPath: createdFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedFile.path))

        try service.trashItem(at: renamedFile.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamedFile.path))
    }
}
