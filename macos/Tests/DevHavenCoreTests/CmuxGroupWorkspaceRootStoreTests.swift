import Foundation
import XCTest
@testable import DevHavenCore

final class CmuxGroupWorkspaceRootStoreTests: XCTestCase {
    func testFourProjectsShareRootAndMembershipRefreshPreservesUserFiles() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let members = try (0..<4).map { index in
            let path = base.appendingPathComponent("repos/\(index)/项目 same name")
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            return CmuxGroupWorkspaceRootStore.Member(name: "项目 \(index)", path: path.path)
        }
        let store = CmuxGroupWorkspaceRootStore(baseURL: base.appendingPathComponent("groups"))
        let id = UUID()
        let root = try store.sync(id: id, name: "四仓联动", members: members)
        XCTAssertEqual(Set(members.map(\.alias)).count, 4)
        for member in members {
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent(member.alias).path), member.path)
        }
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("AGENTS.md"), encoding: .utf8).contains("成员真实路径"))
        let userFile = root.appendingPathComponent("notes.txt")
        try "保留".write(to: userFile, atomically: true, encoding: .utf8)
        _ = try store.sync(id: id, name: "改名", members: Array(members.dropFirst()) + [members[1]])
        let manifest = try JSONDecoder().decode(CmuxGroupWorkspaceRootStore.Manifest.self, from: Data(contentsOf: root.appendingPathComponent("WORKSPACE.json")))
        XCTAssertEqual(manifest.name, "改名")
        XCTAssertEqual(manifest.members.count, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(members[0].alias).path))
        XCTAssertEqual(try String(contentsOf: userFile, encoding: .utf8), "保留")
        XCTAssertEqual(root, store.rootURL(for: id))
    }

    func testInvalidMemberKeepsPreviousManifestAndNeverOverwritesRegularFile() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let member = CmuxGroupWorkspaceRootStore.Member(name: "项目", path: base.appendingPathComponent("repo").path)
        try FileManager.default.createDirectory(atPath: member.path, withIntermediateDirectories: true)
        let store = CmuxGroupWorkspaceRootStore(baseURL: base.appendingPathComponent("groups"))
        let id = UUID()
        let root = try store.sync(id: id, name: "分组", members: [member])
        let before = try Data(contentsOf: root.appendingPathComponent("WORKSPACE.json"))
        let missing = CmuxGroupWorkspaceRootStore.Member(name: "缺失", path: base.appendingPathComponent("missing").path)
        XCTAssertThrowsError(try store.sync(id: id, name: "分组", members: [member, missing]))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("WORKSPACE.json")), before)
        let link = root.appendingPathComponent(member.alias)
        try FileManager.default.removeItem(at: link)
        try "用户文件".write(to: link, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.sync(id: id, name: "分组", members: [member]))
        XCTAssertEqual(try String(contentsOf: link, encoding: .utf8), "用户文件")
    }

    func testCodexCommandPassesRealPathsAsLiteralArguments() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let store = CmuxGroupWorkspaceRootStore(baseURL: base)
        let id = UUID()
        let members = ["repo with spaces", "repo'quote", "repo$(touch injected)", "repo`touch injected`"].map {
            CmuxGroupWorkspaceRootStore.Member(name: $0, path: base.appendingPathComponent($0).path)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = base
        // shell 函数替代 Codex，检查最终 argv，不启动真实 AI 会话。
        process.arguments = ["-c", "codex() { printf '%s\\0' \"$@\"; }; " + store.codexCommand(id: id, members: members + [members[0]])]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let args = String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init)
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(args, ["--cd", store.rootURL(for: id).path] + members.flatMap { ["--add-dir", $0.path] })
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("injected").path))
    }
}
