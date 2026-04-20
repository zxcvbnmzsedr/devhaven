import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceProjectProjectionBuilderTests: XCTestCase {
    func testSelectedProjectFallsBackToFilteredThenVisibleProjects() {
        let selected = makeProject(id: "selected", name: "Selected", path: "/repo/selected")
        let filtered = makeProject(id: "filtered", name: "Filtered", path: "/repo/filtered")
        let visible = makeProject(id: "visible", name: "Visible", path: "/repo/visible")
        let builder = makeBuilder(projectsByPath: [
            selected.path: selected,
        ])

        XCTAssertEqual(
            builder.selectedProject(
                selectedProjectPath: selected.path,
                filteredProjects: [filtered],
                visibleProjects: [visible]
            ),
            selected
        )
        XCTAssertEqual(
            builder.selectedProject(
                selectedProjectPath: nil,
                filteredProjects: [filtered],
                visibleProjects: [visible]
            ),
            filtered
        )
        XCTAssertEqual(
            builder.selectedProject(
                selectedProjectPath: nil,
                filteredProjects: [],
                visibleProjects: [visible]
            ),
            visible
        )
    }

    func testMountedWorkspaceProjectPathPrefersActiveThenHiddenCanonicalPath() {
        let canonicalActive = "/canonical/active"
        let canonicalHidden = "/canonical/hidden"
        let builder = makeBuilder(canonicalPaths: [
            "/active": canonicalActive,
            "/hidden": canonicalHidden,
        ])

        XCTAssertEqual(
            builder.mountedWorkspaceProjectPath(
                activeProjectPath: "/active",
                hiddenMountedProjectPath: "/hidden"
            ),
            canonicalActive
        )
        XCTAssertEqual(
            builder.mountedWorkspaceProjectPath(
                activeProjectPath: nil,
                hiddenMountedProjectPath: "/hidden"
            ),
            canonicalHidden
        )
        XCTAssertNil(builder.mountedWorkspaceProjectPath(activeProjectPath: nil, hiddenMountedProjectPath: nil))
    }

    func testActiveWorkspaceProjectTreeProjectFallsBackToWorkspaceRootSession() {
        let activeProject = makeProject(id: "project", name: "Project", path: "/repo/project")
        let workspaceRootSession = OpenWorkspaceSessionState(
            projectPath: "/tmp/workspace-root",
            controller: GhosttyWorkspaceController(projectPath: "/tmp/workspace-root"),
            isQuickTerminal: true,
            workspaceRootContext: WorkspaceRootSessionContext(
                workspaceID: "workspace-1",
                workspaceName: "支付链路"
            )
        )
        let builder = makeBuilder()

        XCTAssertEqual(
            builder.activeWorkspaceProjectTreeProject(
                activeProject: activeProject,
                activeSession: workspaceRootSession
            ),
            activeProject
        )

        let fallback = builder.activeWorkspaceProjectTreeProject(
            activeProject: nil,
            activeSession: workspaceRootSession
        )
        XCTAssertEqual(fallback?.name, "支付链路")
        XCTAssertEqual(fallback?.path, "/tmp/workspace-root")
        XCTAssertTrue(fallback?.isWorkspaceRoot == true)
    }

    func testOpenWorkspaceProjectionNormalizesPathsAndDeduplicatesRootProjectPaths() {
        let root = makeProject(id: "root", name: "Root", path: "/repo/root")
        let worktree = makeProject(id: "worktree", name: "Worktree", path: "/repo/root-feature")
        let sessions = [
            OpenWorkspaceSessionState(
                projectPath: "/repo/root/",
                controller: GhosttyWorkspaceController(projectPath: "/repo/root/")
            ),
            OpenWorkspaceSessionState(
                projectPath: "/repo/root-feature/",
                rootProjectPath: "/repo/root/",
                controller: GhosttyWorkspaceController(projectPath: "/repo/root-feature/")
            ),
            OpenWorkspaceSessionState(
                projectPath: "/tmp/quick",
                controller: GhosttyWorkspaceController(projectPath: "/tmp/quick"),
                isQuickTerminal: true
            ),
        ]
        let builder = makeBuilder(projectsByPath: [
            "/repo/root": root,
            "/repo/root-feature": worktree,
        ])

        XCTAssertEqual(
            builder.openWorkspaceProjectPaths(sessions: sessions),
            ["/repo/root", "/repo/root-feature", "/tmp/quick"]
        )
        XCTAssertEqual(builder.openWorkspaceRootProjectPaths(sessions: sessions), ["/repo/root/"])
        XCTAssertEqual(builder.openWorkspaceProjects(sessions: sessions).map(\.id), ["root", "worktree"])
    }

    func testAvailableProjectsExcludeOpenRootProjectsAndAlignmentOptionsExcludeQuickTerminals() {
        let root = makeProject(id: "root", name: "Root", path: "/repo/root")
        let other = makeProject(id: "other", name: "Other", path: "/repo/other")
        let quick = Project.quickTerminal(at: "/tmp/quick")
        let builder = makeBuilder()

        let available = builder.availableWorkspaceProjects(
            visibleProjects: [root, other, quick],
            openRootProjectPaths: ["/repo/root/"]
        )

        XCTAssertEqual(available.map(\.id), ["other", quick.id])
        XCTAssertEqual(
            builder.workspaceAlignmentProjectOptions(visibleProjects: [root, other, quick]).map(\.id),
            ["root", "other"]
        )
    }

    func testActiveWorkspaceSessionPrefersExactSessionBeforeNormalizedFallback() {
        let exactSession = OpenWorkspaceSessionState(
            projectPath: "/repo/root/",
            controller: GhosttyWorkspaceController(projectPath: "/repo/root/")
        )
        let normalizedSession = OpenWorkspaceSessionState(
            projectPath: "/repo/root",
            controller: GhosttyWorkspaceController(projectPath: "/repo/root")
        )
        let builder = makeBuilder(
            exactSessions: ["/repo/root/": exactSession],
            sessions: ["/repo/root/": normalizedSession]
        )

        XCTAssertEqual(builder.activeWorkspaceSession(activeProjectPath: "/repo/root/"), exactSession)
    }

    private func makeBuilder(
        projectsByPath: [String: Project] = [:],
        canonicalPaths: [String: String] = [:],
        exactSessions: [String: OpenWorkspaceSessionState] = [:],
        sessions: [String: OpenWorkspaceSessionState] = [:]
    ) -> WorkspaceProjectProjectionBuilder {
        WorkspaceProjectProjectionBuilder(
            normalizePath: normalizeWorkspaceProjectProjectionTestPath,
            resolveDisplayProject: { path, _ in projectsByPath[normalizeWorkspaceProjectProjectionTestPath(path)] },
            canonicalSessionPath: { path in path.flatMap { canonicalPaths[$0] } },
            exactSession: { path in path.flatMap { exactSessions[$0] } },
            session: { path in path.flatMap { sessions[$0] } }
        )
    }

    private func makeProject(
        id: String,
        name: String,
        path: String,
        tags: [String] = []
    ) -> Project {
        Project(
            id: id,
            name: name,
            path: path,
            tags: tags,
            runConfigurations: [],
            worktrees: [],
            mtime: 0,
            size: 0,
            checksum: id,
            gitCommits: 0,
            gitLastCommit: 0,
            created: 0,
            checked: 0
        )
    }
}

private func normalizeWorkspaceProjectProjectionTestPath(_ path: String) -> String {
    var normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\", with: "/")
    while normalized.count > 1 && normalized.hasSuffix("/") {
        normalized.removeLast()
    }
    return normalized
}
