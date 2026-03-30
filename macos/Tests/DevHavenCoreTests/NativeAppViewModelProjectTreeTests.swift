import XCTest
@testable import DevHavenCore

final class NativeAppViewModelProjectTreeTests: XCTestCase {
    private var rootURL: URL!
    private var homeURL: URL!
    private var projectURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-project-tree-\(UUID().uuidString)", isDirectory: true)
        homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        projectURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        projectURL = nil
        homeURL = nil
        rootURL = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testProjectTreeCompactsJavaPackagesAfterExpandingSourceRoot() throws {
        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: homeURL))
        try createDirectory("src/main/java/com/example/service/user/api")
        try createDirectory("src/main/resources/com/example")
        try "class App {}".write(
            to: projectURL.appendingPathComponent("src/main/java/com/example/service/App.java"),
            atomically: true,
            encoding: .utf8
        )
        try "class UserController {}".write(
            to: projectURL.appendingPathComponent("src/main/java/com/example/service/user/api/UserController.java"),
            atomically: true,
            encoding: .utf8
        )
        try "hello".write(
            to: projectURL.appendingPathComponent("src/main/resources/com/example/application.properties"),
            atomically: true,
            encoding: .utf8
        )

        viewModel.snapshot = NativeAppSnapshot(projects: [makeProject()])
        viewModel.enterWorkspace(projectURL.path)
        viewModel.prepareActiveWorkspaceProjectTreeState()

        let srcPath = projectURL.appendingPathComponent("src", isDirectory: true).path
        let mainPath = projectURL.appendingPathComponent("src/main", isDirectory: true).path
        let javaPath = projectURL.appendingPathComponent("src/main/java", isDirectory: true).path

        viewModel.toggleWorkspaceProjectTreeDirectory(srcPath, in: projectURL.path)
        viewModel.toggleWorkspaceProjectTreeDirectory(mainPath, in: projectURL.path)
        viewModel.toggleWorkspaceProjectTreeDirectory(javaPath, in: projectURL.path)

        let treeState = try XCTUnwrap(viewModel.activeWorkspaceProjectTreeState)
        let mainDisplayNode = try XCTUnwrap(treeState.displayNode(for: mainPath))
        XCTAssertEqual(mainDisplayNode.children.map(\.name), ["java", "resources"])

        let javaDisplayNode = try XCTUnwrap(treeState.displayNode(for: javaPath))
        XCTAssertEqual(javaDisplayNode.children.map(\.name), ["com.example.service"])

        let serviceNode = try XCTUnwrap(javaDisplayNode.children.first)
        XCTAssertEqual(
            serviceNode.compactedDirectoryPaths.map(canonicalPath),
            [
                canonicalPath(projectURL.appendingPathComponent("src/main/java/com").path),
                canonicalPath(projectURL.appendingPathComponent("src/main/java/com/example").path),
                canonicalPath(projectURL.appendingPathComponent("src/main/java/com/example/service").path),
            ]
        )

        viewModel.toggleWorkspaceProjectTreeDirectory(serviceNode.path, in: projectURL.path)

        let expandedTreeState = try XCTUnwrap(viewModel.activeWorkspaceProjectTreeState)
        let expandedServiceNode = try XCTUnwrap(expandedTreeState.displayNode(for: serviceNode.path))
        XCTAssertEqual(expandedServiceNode.children.map(\.name), ["user.api", "App.java"])
    }

    @MainActor
    func testProjectTreeCompactsJavaPackagesInsideNestedModule() throws {
        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: homeURL))
        let moduleURL = projectURL.appendingPathComponent("whale-module-ai", isDirectory: true)
        try FileManager.default.createDirectory(at: moduleURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: moduleURL.appendingPathComponent("src/main/java/com/whale/server/module/ai", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "class AiApplication {}".write(
            to: moduleURL.appendingPathComponent("src/main/java/com/whale/server/module/ai/AiApplication.java"),
            atomically: true,
            encoding: .utf8
        )

        viewModel.snapshot = NativeAppSnapshot(projects: [makeProject()])
        viewModel.enterWorkspace(projectURL.path)
        viewModel.prepareActiveWorkspaceProjectTreeState()

        let modulePath = moduleURL.path
        let srcPath = moduleURL.appendingPathComponent("src", isDirectory: true).path
        let mainPath = moduleURL.appendingPathComponent("src/main", isDirectory: true).path
        let javaPath = moduleURL.appendingPathComponent("src/main/java", isDirectory: true).path

        viewModel.toggleWorkspaceProjectTreeDirectory(modulePath, in: projectURL.path)
        viewModel.toggleWorkspaceProjectTreeDirectory(srcPath, in: projectURL.path)
        viewModel.toggleWorkspaceProjectTreeDirectory(mainPath, in: projectURL.path)
        viewModel.toggleWorkspaceProjectTreeDirectory(javaPath, in: projectURL.path)

        let treeState = try XCTUnwrap(viewModel.activeWorkspaceProjectTreeState)
        let javaDisplayNode = try XCTUnwrap(treeState.displayNode(for: javaPath))
        XCTAssertEqual(javaDisplayNode.children.map(\.name), ["com.whale.server.module.ai"])
    }

    private func createDirectory(_ relativePath: String) throws {
        try FileManager.default.createDirectory(
            at: projectURL.appendingPathComponent(relativePath, isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func makeProject() -> Project {
        let now = Date().timeIntervalSinceReferenceDate
        return Project(
            id: UUID().uuidString,
            name: projectURL.lastPathComponent,
            path: projectURL.path,
            tags: [],
            runConfigurations: [],
            worktrees: [],
            mtime: now,
            size: 0,
            checksum: UUID().uuidString,
            isGitRepository: false,
            gitCommits: 0,
            gitLastCommit: now,
            created: now,
            checked: now
        )
    }
}

private func canonicalPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
}
