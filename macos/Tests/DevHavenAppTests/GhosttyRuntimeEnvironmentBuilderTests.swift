import XCTest
import DevHavenCore
@testable import DevHavenApp

final class GhosttyRuntimeEnvironmentBuilderTests: XCTestCase {
    func testBuildInjectsWorkspaceContextWhenManifestExists() throws {
        let fixture = try WorkspaceRootFixture.make()
        defer { fixture.cleanup() }

        let environment = GhosttyRuntimeEnvironmentBuilder.build(
            baseEnvironment: [
                "DEVHAVEN_PROJECT_PATH": fixture.rootURL.path
            ],
            agentResourcesURL: nil
        )

        XCTAssertEqual(environment["DEVHAVEN_WORKSPACE_ROOT"], fixture.rootURL.path)
        XCTAssertEqual(environment["DEVHAVEN_WORKSPACE_MANIFEST"], fixture.manifestURL.path)
        XCTAssertEqual(environment["DEVHAVEN_WORKSPACE_README"], fixture.readmeURL.path)
        XCTAssertEqual(environment["DEVHAVEN_WORKSPACE_ID"], "workspace-1")
        XCTAssertEqual(environment["DEVHAVEN_WORKSPACE_NAME"], "支付链路联调")
    }

    func testBuildSkipsWorkspaceContextWhenManifestMissing() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-workspace-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let environment = GhosttyRuntimeEnvironmentBuilder.build(
            baseEnvironment: [
                "DEVHAVEN_PROJECT_PATH": tempRoot.path
            ],
            agentResourcesURL: nil
        )

        XCTAssertNil(environment["DEVHAVEN_WORKSPACE_ROOT"])
        XCTAssertNil(environment["DEVHAVEN_WORKSPACE_MANIFEST"])
        XCTAssertNil(environment["DEVHAVEN_WORKSPACE_README"])
        XCTAssertNil(environment["DEVHAVEN_WORKSPACE_ID"])
        XCTAssertNil(environment["DEVHAVEN_WORKSPACE_NAME"])
    }
}

private struct WorkspaceRootFixture {
    let rootURL: URL
    let manifestURL: URL
    let readmeURL: URL

    static func make() throws -> WorkspaceRootFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-workspace-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let manifest = WorkspaceAlignmentRootManifest(
            id: "workspace-1",
            name: "支付链路联调",
            workspaceRootPath: rootURL.path,
            members: [
                .init(
                    alias: "A",
                    projectName: "service-a",
                    projectPath: "/tmp/service-a",
                    openPath: "/tmp/service-a-worktree",
                    branch: "feature/A",
                    status: "已对齐"
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let manifestURL = rootURL.appendingPathComponent("WORKSPACE.json")
        var manifestData = try encoder.encode(manifest)
        manifestData.append(0x0A)
        try manifestData.write(to: manifestURL, options: .atomic)

        let readmeURL = rootURL.appendingPathComponent("WORKSPACE.md")
        try "# 支付链路联调\n".write(to: readmeURL, atomically: true, encoding: .utf8)

        return WorkspaceRootFixture(
            rootURL: rootURL,
            manifestURL: manifestURL,
            readmeURL: readmeURL
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
