import XCTest
@testable import DevHavenCore

final class WorkspaceProjectTreeControllerTests: XCTestCase {
    private var rootURL: URL!
    private var projectURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-project-tree-controller-\(UUID().uuidString)", isDirectory: true)
        projectURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        projectURL = nil
        rootURL = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testPrepareActiveProjectTreeStateBuildsInitialState() async throws {
        try createDirectory("Sources")
        try createFile("README.md", contents: "hello")
        let normalizedProjectPath = normalizeTestPath(projectURL.path)
        let store = WorkspaceProjectTreeStateStore()
        let controller = makeController(
            store: store,
            normalizedProjectPath: normalizedProjectPath
        )

        controller.prepareActiveProjectTreeState()

        let loaded = await waitUntil(timeout: 1) {
            store.statesByProjectPath[normalizedProjectPath]?.rootNodes.count == 2
        }
        XCTAssertTrue(loaded)

        let state = try XCTUnwrap(store.statesByProjectPath[normalizedProjectPath])
        XCTAssertEqual(state.rootNodes.map(\.name).sorted(), ["README.md", "Sources"])
        XCTAssertFalse(store.refreshingProjectPaths.contains(normalizedProjectPath))
    }

    @MainActor
    func testSelectProjectTreeNodeUpdatesStateAndSyncsGitSelection() throws {
        let normalizedProjectPath = normalizeTestPath(projectURL.path)
        let selectedFilePath = normalizeTestPath(projectURL.appendingPathComponent("App.swift").path)
        var syncedSelections: [(String, String?)] = []
        let store = WorkspaceProjectTreeStateStore(
            statesByProjectPath: [
                normalizedProjectPath: WorkspaceProjectTreeState(
                    rootProjectPath: normalizedProjectPath,
                    rootNodes: [
                        WorkspaceProjectTreeNode(
                            path: selectedFilePath,
                            parentPath: normalizedProjectPath,
                            name: "App.swift",
                            kind: .file,
                            isHidden: false
                        )
                    ],
                    childrenByDirectoryPath: [normalizedProjectPath: []]
                )
            ]
        )
        let controller = makeController(
            store: store,
            normalizedProjectPath: normalizedProjectPath,
            syncGitSelection: { projectPath, selectedPath in
                syncedSelections.append((projectPath, selectedPath))
            }
        )

        controller.selectProjectTreeNode(selectedFilePath, in: normalizedProjectPath)

        XCTAssertEqual(store.statesByProjectPath[normalizedProjectPath]?.selectedPath, selectedFilePath)
        XCTAssertEqual(syncedSelections.count, 1)
        XCTAssertEqual(syncedSelections.first?.0, normalizedProjectPath)
        XCTAssertEqual(syncedSelections.first?.1, selectedFilePath)
    }

    @MainActor
    private func makeController(
        store: WorkspaceProjectTreeStateStore,
        normalizedProjectPath: String,
        syncGitSelection: @escaping @MainActor (String, String?) -> Void = { _, _ in }
    ) -> WorkspaceProjectTreeController {
        WorkspaceProjectTreeController(
            stateStore: store,
            fileSystemService: WorkspaceFileSystemService(),
            diagnostics: .shared,
            normalizePath: { normalizeTestPath($0) },
            resolveProjectPath: { path in
                normalizeTestPath(path ?? normalizedProjectPath)
            },
            activeProjectTreeProject: {
                Project(
                    id: UUID().uuidString,
                    name: "repo",
                    path: normalizedProjectPath,
                    tags: [],
                    runConfigurations: [],
                    worktrees: [],
                    mtime: 0,
                    size: 0,
                    checksum: "checksum",
                    isGitRepository: false,
                    gitCommits: 0,
                    gitLastCommit: 0,
                    created: 0,
                    checked: 0
                )
            },
            syncGitSelection: syncGitSelection,
            reportError: { _ in }
        )
    }

    private func createDirectory(_ relativePath: String) throws {
        try FileManager.default.createDirectory(
            at: projectURL.appendingPathComponent(relativePath, isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func createFile(_ relativePath: String, contents: String) throws {
        try contents.write(
            to: projectURL.appendingPathComponent(relativePath),
            atomically: true,
            encoding: .utf8
        )
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}

private func normalizeTestPath(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return ""
    }
    var normalized = canonicalTestPath(trimmed).replacingOccurrences(of: "\\", with: "/")
    while normalized.count > 1 && normalized.hasSuffix("/") {
        normalized.removeLast()
    }
    return normalized
}

private func canonicalTestPath(_ path: String) -> String {
    let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
    let fileManager = FileManager.default
    var ancestorPath = standardizedPath
    var trailingComponents = [String]()

    while ancestorPath != "/", !fileManager.fileExists(atPath: ancestorPath) {
        let lastComponent = (ancestorPath as NSString).lastPathComponent
        guard !lastComponent.isEmpty else {
            break
        }
        trailingComponents.insert(lastComponent, at: 0)
        ancestorPath = (ancestorPath as NSString).deletingLastPathComponent
        if ancestorPath.isEmpty {
            ancestorPath = "/"
            break
        }
    }

    let canonicalAncestorPath = realpathTestPath(ancestorPath) ?? ancestorPath
    guard !trailingComponents.isEmpty else {
        return canonicalAncestorPath
    }

    return trailingComponents.reduce(canonicalAncestorPath as NSString) { partial, component in
        partial.appendingPathComponent(component) as NSString
    } as String
}

private func realpathTestPath(_ path: String) -> String? {
    guard !path.isEmpty else {
        return nil
    }
    return path.withCString { pointer in
        guard let resolvedPointer = realpath(pointer, nil) else {
            return nil
        }
        defer { free(resolvedPointer) }
        return String(cString: resolvedPointer)
    }
}
