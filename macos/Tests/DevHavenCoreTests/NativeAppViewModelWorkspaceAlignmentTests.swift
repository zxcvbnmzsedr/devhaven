import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelWorkspaceAlignmentTests: XCTestCase {
    func testRootCheckoutOfTargetBranchIsReportedAsAlignedAndApplyDoesNotCreateManagedWorktree() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "develop")
        try fixture.commit(fileName: "README.md", content: "hello")
        try fixture.git(in: fixture.repositoryURL, ["checkout", "-b", "feature/payment"])

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            name: "支付链路",
            targetBranch: "feature/payment",
            projectPaths: [fixture.repositoryURL.path]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)

        let memberAfterRecheck = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)
        XCTAssertEqual(memberAfterRecheck.status, .aligned)
        XCTAssertEqual(memberAfterRecheck.openTarget, .project(projectPath: fixture.repositoryURL.path))

        let managedPath = try viewModel.managedWorktreePathPreview(
            for: fixture.repositoryURL.path,
            branch: "feature/payment"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedPath))

        try await viewModel.applyWorkspaceAlignmentGroup(group.id)

        let memberAfterApply = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)
        XCTAssertEqual(memberAfterApply.status, .aligned)
        XCTAssertEqual(memberAfterApply.openTarget, .project(projectPath: fixture.repositoryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedPath))
    }

    func testExistingCheckoutInAnotherWorktreeIsReusedInsteadOfCreatingManagedWorktree() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "develop")
        try fixture.commit(fileName: "README.md", content: "hello")

        let existingWorktreeURL = fixture.rootURL.appendingPathComponent("existing-feature-worktree", isDirectory: true)
        try fixture.git(
            in: fixture.repositoryURL,
            ["worktree", "add", existingWorktreeURL.path, "-b", "feature/payment", "develop"]
        )
        let expectedWorktreePath = existingWorktreeURL.resolvingSymlinksInPath().path

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            name: "支付链路",
            targetBranch: "feature/payment",
            projectPaths: [fixture.repositoryURL.path]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)

        let memberAfterRecheck = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)
        XCTAssertEqual(memberAfterRecheck.status, .aligned)
        assertWorktreeOpenTarget(
            memberAfterRecheck.openTarget,
            rootProjectPath: fixture.repositoryURL.path,
            worktreePath: expectedWorktreePath
        )
        XCTAssertEqual(
            viewModel.snapshot.projects.first?.worktrees.map { canonicalPath($0.path) },
            [canonicalPath(expectedWorktreePath)]
        )

        let managedPath = try viewModel.managedWorktreePathPreview(
            for: fixture.repositoryURL.path,
            branch: "feature/payment"
        )
        XCTAssertNotEqual(managedPath, expectedWorktreePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedPath))

        try await viewModel.applyWorkspaceAlignmentGroup(group.id)

        let memberAfterApply = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)
        XCTAssertEqual(memberAfterApply.status, .aligned)
        assertWorktreeOpenTarget(
            memberAfterApply.openTarget,
            rootProjectPath: fixture.repositoryURL.path,
            worktreePath: expectedWorktreePath
        )
        XCTAssertEqual(
            viewModel.snapshot.projects.first?.worktrees.map { canonicalPath($0.path) },
            [canonicalPath(expectedWorktreePath)]
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedPath))
    }

    func testApplyWorkspaceAlignmentGroupCreatesMissingBranchFromSelectedBaseBranch() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        let member = WorkspaceAlignmentMemberDefinition(
            projectPath: fixture.repositoryURL.path,
            targetBranch: "feature/payment",
            baseBranchMode: .specified,
            specifiedBaseBranch: "main"
        )
        let group = WorkspaceAlignmentGroupDefinition(
            name: "支付链路",
            targetBranch: "feature/payment",
            projectPaths: [fixture.repositoryURL.path],
            members: [member]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)
        let memberAfterRecheck = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)
        XCTAssertEqual(memberAfterRecheck.status, .branchMissing)

        try await viewModel.applyWorkspaceAlignmentGroup(group.id)

        let managedPath = try viewModel.managedWorktreePathPreview(
            for: fixture.repositoryURL.path,
            branch: "feature/payment"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedPath))
        XCTAssertEqual(
            try fixture.git(in: URL(fileURLWithPath: managedPath, isDirectory: true), ["branch", "--show-current"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "feature/payment"
        )

        let memberAfterApply = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)
        XCTAssertEqual(memberAfterApply.status, .aligned)
        assertWorktreeOpenTarget(
            memberAfterApply.openTarget,
            rootProjectPath: fixture.repositoryURL.path,
            worktreePath: managedPath
        )
    }

    func testApplyWorkspaceAlignmentGroupRejectsLegacyAutoDetectBaseBranch() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        let member = WorkspaceAlignmentMemberDefinition(
            projectPath: fixture.repositoryURL.path,
            targetBranch: "feature/payment",
            baseBranchMode: .autoDetect
        )
        let group = WorkspaceAlignmentGroupDefinition(
            name: "支付链路",
            targetBranch: "feature/payment",
            projectPaths: [fixture.repositoryURL.path],
            members: [member]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        do {
            try await viewModel.applyWorkspaceAlignmentGroup(group.id)
            XCTFail("预期旧的自动探测配置会被拒绝，但实际成功")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertTrue(message.contains("自动探测"), "错误文案应提示旧配置需重新选择基线分支，实际：\(message)")
        }
    }

    func testEnterWorkspaceAlignmentGroupCreatesWorkspaceRootSessionAndManifest() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            name: "支付链路联调",
            targetBranch: "main",
            projectPaths: [fixture.repositoryURL.path]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)
        try viewModel.enterWorkspaceAlignmentGroup(group.id)

        let activePath = try XCTUnwrap(viewModel.activeWorkspaceProjectPath)
        XCTAssertTrue(activePath.hasPrefix(fixture.homeURL.appendingPathComponent(".devhaven/workspaces", isDirectory: true).path))

        let session = try XCTUnwrap(viewModel.openWorkspaceSessions.first(where: { $0.projectPath == activePath }))
        XCTAssertTrue(session.isQuickTerminal)
        XCTAssertEqual(session.workspaceRootContext?.workspaceID, group.id)
        XCTAssertEqual(session.workspaceRootContext?.workspaceName, group.name)

        let manifestURL = URL(fileURLWithPath: activePath, isDirectory: true).appendingPathComponent("WORKSPACE.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(WorkspaceAlignmentRootManifest.self, from: manifestData)

        XCTAssertEqual(manifest.id, group.id)
        XCTAssertEqual(manifest.name, group.name)
        XCTAssertEqual(manifest.members.count, 1)
        XCTAssertEqual(manifest.members.first?.projectPath, fixture.repositoryURL.path)
        XCTAssertEqual(manifest.members.first?.openPath, fixture.repositoryURL.path)

        let alias = try XCTUnwrap(manifest.members.first?.alias)
        let aliasURL = URL(fileURLWithPath: activePath, isDirectory: true).appendingPathComponent(alias)
        XCTAssertTrue(FileManager.default.fileExists(atPath: aliasURL.path))
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: aliasURL.path)
        XCTAssertEqual(canonicalPath(destination), canonicalPath(fixture.repositoryURL.path))
    }

    func testWorkspaceRootSessionCanLoadProjectTree() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            name: "支付链路联调",
            targetBranch: "main",
            projectPaths: [fixture.repositoryURL.path]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)
        try viewModel.enterWorkspaceAlignmentGroup(group.id)

        let activePath = try XCTUnwrap(viewModel.activeWorkspaceProjectPath)
        let projectTreeProject = try XCTUnwrap(viewModel.activeWorkspaceProjectTreeProject)
        XCTAssertTrue(projectTreeProject.isWorkspaceRoot)
        XCTAssertEqual(canonicalPath(projectTreeProject.path), canonicalPath(activePath))

        viewModel.prepareActiveWorkspaceProjectTreeState()
        let treeLoaded = await waitUntil(timeout: 1) {
            viewModel.activeWorkspaceProjectTreeState != nil
        }
        XCTAssertTrue(treeLoaded)

        let treeState = try XCTUnwrap(viewModel.activeWorkspaceProjectTreeState)
        XCTAssertEqual(canonicalPath(treeState.rootProjectPath), canonicalPath(activePath))
        XCTAssertTrue(treeState.displayRootNodes.contains(where: { $0.name == "WORKSPACE.json" }))
    }

    func testWorkspaceRootSymlinkDirectoryExpandsInlineForLinkedProject() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            name: "支付链路联调",
            targetBranch: "main",
            projectPaths: [fixture.repositoryURL.path]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)
        try viewModel.enterWorkspaceAlignmentGroup(group.id)

        let workspaceRootPath = try XCTUnwrap(viewModel.activeWorkspaceProjectPath)
        viewModel.prepareActiveWorkspaceProjectTreeState()
        let treeLoaded = await waitUntil(timeout: 1) {
            viewModel.activeWorkspaceProjectTreeState != nil
        }
        XCTAssertTrue(treeLoaded)

        let manifest = try readWorkspaceManifest(at: workspaceRootPath)
        let alias = try XCTUnwrap(manifest.members.first?.alias)
        let linkPath = URL(fileURLWithPath: workspaceRootPath, isDirectory: true)
            .appendingPathComponent(alias, isDirectory: true)
            .path

        let initialTreeState = try XCTUnwrap(viewModel.activeWorkspaceProjectTreeState)
        let linkNode = try XCTUnwrap(initialTreeState.displayNode(for: linkPath))
        XCTAssertEqual(linkNode.kind, .symlink)
        XCTAssertEqual(linkNode.resolvedKind, .directory)
        XCTAssertTrue(linkNode.isDirectory)

        viewModel.toggleWorkspaceProjectTreeDirectory(linkPath, in: workspaceRootPath)

        let linkedProjectExpanded = await waitUntil(timeout: 1) {
            guard let treeState = viewModel.activeWorkspaceProjectTreeState,
                  let expandedLinkNode = treeState.displayNode(for: linkPath)
            else {
                return false
            }
            return expandedLinkNode.children.contains(where: { $0.name == "README.md" })
        }
        XCTAssertTrue(linkedProjectExpanded)

        let expandedTreeState = try XCTUnwrap(viewModel.activeWorkspaceProjectTreeState)
        let expandedLinkNode = try XCTUnwrap(expandedTreeState.displayNode(for: linkPath))
        XCTAssertTrue(expandedLinkNode.children.contains(where: { $0.name == "README.md" }))
        XCTAssertEqual(canonicalPath(try XCTUnwrap(viewModel.activeWorkspaceProjectPath)), canonicalPath(workspaceRootPath))
    }

    func testWorkspaceRootSymlinkDirectoryExpandsInlineForLinkedWorktree() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "develop")
        try fixture.commit(fileName: "README.md", content: "hello")

        let existingWorktreeURL = fixture.rootURL.appendingPathComponent("existing-feature-worktree", isDirectory: true)
        try fixture.git(
            in: fixture.repositoryURL,
            ["worktree", "add", existingWorktreeURL.path, "-b", "feature/payment", "develop"]
        )
        let expectedWorktreePath = existingWorktreeURL.resolvingSymlinksInPath().path

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            name: "支付链路",
            targetBranch: "feature/payment",
            projectPaths: [fixture.repositoryURL.path]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)
        try viewModel.enterWorkspaceAlignmentGroup(group.id)

        let workspaceRootPath = try XCTUnwrap(viewModel.activeWorkspaceProjectPath)
        viewModel.prepareActiveWorkspaceProjectTreeState()
        let treeLoaded = await waitUntil(timeout: 1) {
            viewModel.activeWorkspaceProjectTreeState != nil
        }
        XCTAssertTrue(treeLoaded)

        let manifest = try readWorkspaceManifest(at: workspaceRootPath)
        let alias = try XCTUnwrap(manifest.members.first?.alias)
        let linkPath = URL(fileURLWithPath: workspaceRootPath, isDirectory: true)
            .appendingPathComponent(alias, isDirectory: true)
            .path

        let initialTreeState = try XCTUnwrap(viewModel.activeWorkspaceProjectTreeState)
        let linkNode = try XCTUnwrap(initialTreeState.displayNode(for: linkPath))
        XCTAssertEqual(linkNode.kind, .symlink)
        XCTAssertEqual(linkNode.resolvedKind, .directory)
        XCTAssertTrue(linkNode.isDirectory)

        viewModel.toggleWorkspaceProjectTreeDirectory(linkPath, in: workspaceRootPath)

        let linkedWorktreeExpanded = await waitUntil(timeout: 1) {
            guard let treeState = viewModel.activeWorkspaceProjectTreeState,
                  let expandedLinkNode = treeState.displayNode(for: linkPath)
            else {
                return false
            }
            return expandedLinkNode.children.contains(where: { $0.name == "README.md" })
        }
        XCTAssertTrue(linkedWorktreeExpanded)

        let expandedTreeState = try XCTUnwrap(viewModel.activeWorkspaceProjectTreeState)
        let expandedLinkNode = try XCTUnwrap(expandedTreeState.displayNode(for: linkPath))
        XCTAssertTrue(expandedLinkNode.children.contains(where: { $0.name == "README.md" }))
        XCTAssertEqual(canonicalPath(try XCTUnwrap(viewModel.activeWorkspaceProjectPath)), canonicalPath(workspaceRootPath))
        XCTAssertFalse(viewModel.openWorkspaceSessions.contains(where: {
            canonicalPath($0.projectPath) == canonicalPath(expectedWorktreePath) && $0.workspaceRootContext == nil
        }))
    }

    func testOpeningAlignmentProjectMemberAppearsInOpenedProjectsWhileKeepingAlignmentOwnershipUntilPromoted() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            name: "支付链路联调",
            targetBranch: "main",
            projectPaths: [fixture.repositoryURL.path]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)
        let member = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)

        viewModel.openWorkspaceAlignmentMember(member)

        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, fixture.repositoryURL.path)
        XCTAssertEqual(viewModel.openWorkspaceSessions.count, 2)
        XCTAssertTrue(viewModel.openWorkspaceRootProjectPaths.contains(fixture.repositoryURL.path))
        XCTAssertFalse(viewModel.availableWorkspaceProjects.contains(where: { $0.path == fixture.repositoryURL.path }))
        XCTAssertTrue(viewModel.workspaceSidebarGroups.contains(where: { $0.rootProject.path == fixture.repositoryURL.path }))
        XCTAssertTrue(viewModel.workspaceAlignmentGroups.first?.isActive == true)
        XCTAssertTrue(viewModel.workspaceAlignmentGroups.first?.members.first?.isActive == true)

        let memberSession = try XCTUnwrap(viewModel.openWorkspaceSessions.first(where: { $0.projectPath == fixture.repositoryURL.path }))
        XCTAssertEqual(memberSession.workspaceAlignmentGroupID, group.id)
        XCTAssertEqual(memberSession.rootProjectPath, fixture.repositoryURL.path)

        viewModel.enterWorkspace(fixture.repositoryURL.path)

        let promotedSession = try XCTUnwrap(viewModel.openWorkspaceSessions.first(where: { $0.projectPath == fixture.repositoryURL.path }))
        XCTAssertNil(promotedSession.workspaceAlignmentGroupID)
        XCTAssertEqual(promotedSession.rootProjectPath, fixture.repositoryURL.path)
        XCTAssertTrue(viewModel.openWorkspaceRootProjectPaths.contains(fixture.repositoryURL.path))
        XCTAssertFalse(viewModel.availableWorkspaceProjects.contains(where: { $0.path == fixture.repositoryURL.path }))
    }

    func testClosingAlignmentProjectMemberDoesNotCloseWorkspaceRootSession() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            name: "支付链路联调",
            targetBranch: "main",
            projectPaths: [fixture.repositoryURL.path]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)
        let member = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)

        viewModel.openWorkspaceAlignmentMember(member)

        let workspaceRootPath = try XCTUnwrap(viewModel.openWorkspaceSessions.first(where: {
            $0.isQuickTerminal && $0.workspaceRootContext?.workspaceID == group.id
        })?.projectPath)

        viewModel.closeWorkspaceProject(fixture.repositoryURL.path)

        XCTAssertFalse(viewModel.openWorkspaceSessions.contains(where: {
            canonicalPath($0.projectPath) == canonicalPath(fixture.repositoryURL.path)
        }))
        XCTAssertTrue(viewModel.openWorkspaceSessions.contains(where: {
            canonicalPath($0.projectPath) == canonicalPath(workspaceRootPath) &&
                $0.workspaceRootContext?.workspaceID == group.id
        }))
        XCTAssertEqual(canonicalPath(try XCTUnwrap(viewModel.activeWorkspaceProjectPath)), canonicalPath(workspaceRootPath))
    }

    func testOpeningAlignmentWorktreeMemberAppearsInOpenedProjectsWithoutOpeningRootSession() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "develop")
        try fixture.commit(fileName: "README.md", content: "hello")

        let existingWorktreeURL = fixture.rootURL.appendingPathComponent("existing-feature-worktree", isDirectory: true)
        try fixture.git(
            in: fixture.repositoryURL,
            ["worktree", "add", existingWorktreeURL.path, "-b", "feature/payment", "develop"]
        )
        let expectedWorktreePath = existingWorktreeURL.resolvingSymlinksInPath().path

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            name: "支付链路",
            targetBranch: "feature/payment",
            projectPaths: [fixture.repositoryURL.path]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)
        let member = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)
        assertWorktreeOpenTarget(
            member.openTarget,
            rootProjectPath: fixture.repositoryURL.path,
            worktreePath: expectedWorktreePath
        )

        viewModel.openWorkspaceAlignmentMember(member)

        XCTAssertEqual(
            canonicalPath(try XCTUnwrap(viewModel.activeWorkspaceProjectPath)),
            canonicalPath(expectedWorktreePath)
        )
        XCTAssertEqual(viewModel.openWorkspaceSessions.count, 2)
        XCTAssertFalse(viewModel.openWorkspaceSessions.contains(where: {
            $0.projectPath == fixture.repositoryURL.path && $0.workspaceRootContext == nil
        }))
        XCTAssertTrue(viewModel.openWorkspaceRootProjectPaths.contains(fixture.repositoryURL.path))
        XCTAssertFalse(viewModel.availableWorkspaceProjects.contains(where: { $0.path == fixture.repositoryURL.path }))

        let rootGroup = try XCTUnwrap(viewModel.workspaceSidebarGroups.first(where: {
            canonicalPath($0.rootProject.path) == canonicalPath(fixture.repositoryURL.path)
        }))
        XCTAssertTrue(rootGroup.isActive)
        let sidebarWorktree = try XCTUnwrap(rootGroup.worktrees.first(where: {
            canonicalPath($0.path) == canonicalPath(expectedWorktreePath)
        }))
        XCTAssertTrue(sidebarWorktree.isOpen)
        XCTAssertTrue(sidebarWorktree.isActive)
        let activeAlignmentGroup = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first)
        XCTAssertTrue(activeAlignmentGroup.isActive)
        XCTAssertTrue(activeAlignmentGroup.members.first?.isActive == true)

        let worktreeSession = try XCTUnwrap(viewModel.openWorkspaceSessions.first(where: {
            canonicalPath($0.projectPath) == canonicalPath(expectedWorktreePath)
        }))
        XCTAssertEqual(worktreeSession.rootProjectPath, fixture.repositoryURL.path)
        XCTAssertEqual(worktreeSession.workspaceAlignmentGroupID, group.id)
        XCTAssertEqual(canonicalPath(worktreeSession.projectPath), canonicalPath(expectedWorktreePath))
    }

    func testRegularOpenedWorktreeStillHighlightsMatchingWorkspaceMember() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "develop")
        try fixture.commit(fileName: "README.md", content: "hello")

        let existingWorktreeURL = fixture.rootURL.appendingPathComponent("existing-feature-worktree", isDirectory: true)
        try fixture.git(
            in: fixture.repositoryURL,
            ["worktree", "add", existingWorktreeURL.path, "-b", "feature/payment", "develop"]
        )
        let expectedWorktreePath = existingWorktreeURL.resolvingSymlinksInPath().path

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            name: "支付链路",
            targetBranch: "feature/payment",
            projectPaths: [fixture.repositoryURL.path]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)
        viewModel.openWorkspaceWorktree(expectedWorktreePath, from: fixture.repositoryURL.path)

        let activeAlignmentGroup = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first)
        XCTAssertTrue(activeAlignmentGroup.isActive)
        XCTAssertTrue(activeAlignmentGroup.members.first?.isActive == true)

        let activeSession = try XCTUnwrap(viewModel.openWorkspaceSessions.first(where: {
            canonicalPath($0.projectPath) == canonicalPath(expectedWorktreePath)
        }))
        XCTAssertNil(activeSession.workspaceAlignmentGroupID)
    }

    func testRegularOpenedWorktreeOnlyHighlightsMatchingWorkspaceGroupWhenMultipleGroupsShareRootProject() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "develop")
        try fixture.commit(fileName: "README.md", content: "hello")

        let issuesWorktreeURL = fixture.rootURL.appendingPathComponent("issues-8-worktree", isDirectory: true)
        let excelWorktreeURL = fixture.rootURL.appendingPathComponent("feature-excel-worktree", isDirectory: true)
        let partnerWorktreeURL = fixture.rootURL.appendingPathComponent("feature-openapi-partner-integration-worktree", isDirectory: true)
        try fixture.git(
            in: fixture.repositoryURL,
            ["worktree", "add", issuesWorktreeURL.path, "-b", "issues/8", "develop"]
        )
        try fixture.git(
            in: fixture.repositoryURL,
            ["worktree", "add", excelWorktreeURL.path, "-b", "feature/excel", "develop"]
        )
        try fixture.git(
            in: fixture.repositoryURL,
            ["worktree", "add", partnerWorktreeURL.path, "-b", "feature/openapi-partner-integration", "develop"]
        )
        let expectedIssuesWorktreePath = issuesWorktreeURL.resolvingSymlinksInPath().path

        let issuesGroup = WorkspaceAlignmentGroupDefinition(
            name: "回寄报告状态同步",
            targetBranch: "issues/8",
            projectPaths: [fixture.repositoryURL.path]
        )
        let excelGroup = WorkspaceAlignmentGroupDefinition(
            name: "检测回寄导出excel",
            targetBranch: "feature/excel",
            projectPaths: [fixture.repositoryURL.path]
        )
        let partnerGroup = WorkspaceAlignmentGroupDefinition(
            name: "对接艾米森",
            targetBranch: "feature/openapi-partner-integration",
            projectPaths: [fixture.repositoryURL.path]
        )

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [partnerGroup, excelGroup, issuesGroup]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(partnerGroup.id)
        try await viewModel.recheckWorkspaceAlignmentGroup(excelGroup.id)
        try await viewModel.recheckWorkspaceAlignmentGroup(issuesGroup.id)

        viewModel.openWorkspaceWorktree(expectedIssuesWorktreePath, from: fixture.repositoryURL.path)

        let groupsByName = Dictionary(uniqueKeysWithValues: viewModel.workspaceAlignmentGroups.map { ($0.definition.name, $0) })
        let activeIssuesGroup = try XCTUnwrap(groupsByName["回寄报告状态同步"])
        let inactiveExcelGroup = try XCTUnwrap(groupsByName["检测回寄导出excel"])
        let inactivePartnerGroup = try XCTUnwrap(groupsByName["对接艾米森"])

        XCTAssertTrue(activeIssuesGroup.isActive)
        XCTAssertTrue(activeIssuesGroup.members.first?.isActive == true)
        XCTAssertFalse(inactiveExcelGroup.isActive)
        XCTAssertFalse(inactiveExcelGroup.members.first?.isActive == true)
        XCTAssertFalse(inactivePartnerGroup.isActive)
        XCTAssertFalse(inactivePartnerGroup.members.first?.isActive == true)
    }

    func testAlignmentOwnedWorktreeOnlyHighlightsOwningWorkspaceGroupWhenMultipleGroupsShareRootProject() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "develop")
        try fixture.commit(fileName: "README.md", content: "hello")

        let issuesWorktreeURL = fixture.rootURL.appendingPathComponent("issues-8-worktree", isDirectory: true)
        let excelWorktreeURL = fixture.rootURL.appendingPathComponent("feature-excel-worktree", isDirectory: true)
        let partnerWorktreeURL = fixture.rootURL.appendingPathComponent("feature-openapi-partner-integration-worktree", isDirectory: true)
        try fixture.git(
            in: fixture.repositoryURL,
            ["worktree", "add", issuesWorktreeURL.path, "-b", "issues/8", "develop"]
        )
        try fixture.git(
            in: fixture.repositoryURL,
            ["worktree", "add", excelWorktreeURL.path, "-b", "feature/excel", "develop"]
        )
        try fixture.git(
            in: fixture.repositoryURL,
            ["worktree", "add", partnerWorktreeURL.path, "-b", "feature/openapi-partner-integration", "develop"]
        )
        let expectedIssuesWorktreePath = issuesWorktreeURL.resolvingSymlinksInPath().path

        let issuesGroup = WorkspaceAlignmentGroupDefinition(
            name: "回寄报告状态同步",
            targetBranch: "issues/8",
            projectPaths: [fixture.repositoryURL.path]
        )
        let excelGroup = WorkspaceAlignmentGroupDefinition(
            name: "检测回寄导出excel",
            targetBranch: "feature/excel",
            projectPaths: [fixture.repositoryURL.path]
        )
        let partnerGroup = WorkspaceAlignmentGroupDefinition(
            name: "对接艾米森",
            targetBranch: "feature/openapi-partner-integration",
            projectPaths: [fixture.repositoryURL.path]
        )

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [partnerGroup, excelGroup, issuesGroup]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(partnerGroup.id)
        try await viewModel.recheckWorkspaceAlignmentGroup(excelGroup.id)
        try await viewModel.recheckWorkspaceAlignmentGroup(issuesGroup.id)

        let issuesMember = try XCTUnwrap(
            viewModel.workspaceAlignmentGroups.first(where: { $0.id == issuesGroup.id })?.members.first
        )
        viewModel.openWorkspaceAlignmentMember(issuesMember)

        let activeSession = try XCTUnwrap(viewModel.openWorkspaceSessions.first(where: {
            canonicalPath($0.projectPath) == canonicalPath(expectedIssuesWorktreePath)
        }))
        XCTAssertEqual(activeSession.workspaceAlignmentGroupID, issuesGroup.id)

        let groupsByName = Dictionary(uniqueKeysWithValues: viewModel.workspaceAlignmentGroups.map { ($0.definition.name, $0) })
        let activeIssuesGroup = try XCTUnwrap(groupsByName["回寄报告状态同步"])
        let inactiveExcelGroup = try XCTUnwrap(groupsByName["检测回寄导出excel"])
        let inactivePartnerGroup = try XCTUnwrap(groupsByName["对接艾米森"])

        XCTAssertTrue(activeIssuesGroup.isActive)
        XCTAssertTrue(activeIssuesGroup.members.first?.isActive == true)
        XCTAssertFalse(inactiveExcelGroup.isActive)
        XCTAssertFalse(inactiveExcelGroup.members.first?.isActive == true)
        XCTAssertFalse(inactivePartnerGroup.isActive)
        XCTAssertFalse(inactivePartnerGroup.members.first?.isActive == true)
    }

    func testSidebarSelectingRootProjectOpensRealRootSessionForRegularWorktree() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "develop")
        try fixture.commit(fileName: "README.md", content: "hello")

        let existingWorktreeURL = fixture.rootURL.appendingPathComponent("existing-feature-worktree", isDirectory: true)
        try fixture.git(
            in: fixture.repositoryURL,
            ["worktree", "add", existingWorktreeURL.path, "-b", "feature/payment", "develop"]
        )
        let expectedWorktreePath = existingWorktreeURL.resolvingSymlinksInPath().path

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(),
            projects: [fixture.makeProject()]
        )

        try await viewModel.refreshProjectWorktrees(fixture.repositoryURL.path)
        viewModel.openWorkspaceWorktree(expectedWorktreePath, from: fixture.repositoryURL.path)
        XCTAssertFalse(viewModel.openWorkspaceSessions.contains(where: {
            canonicalPath($0.projectPath) == canonicalPath(fixture.repositoryURL.path)
        }))

        viewModel.activateWorkspaceSidebarProject(fixture.repositoryURL.path)

        XCTAssertEqual(
            canonicalPath(try XCTUnwrap(viewModel.activeWorkspaceProjectPath)),
            canonicalPath(fixture.repositoryURL.path)
        )
        XCTAssertTrue(viewModel.openWorkspaceSessions.contains(where: {
            canonicalPath($0.projectPath) == canonicalPath(fixture.repositoryURL.path) &&
                $0.workspaceRootContext == nil
        }))
        XCTAssertTrue(viewModel.openWorkspaceSessions.contains(where: {
            canonicalPath($0.projectPath) == canonicalPath(expectedWorktreePath)
        }))

        let rootGroup = try XCTUnwrap(viewModel.workspaceSidebarGroups.first(where: {
            canonicalPath($0.rootProject.path) == canonicalPath(fixture.repositoryURL.path)
        }))
        let sidebarWorktree = try XCTUnwrap(rootGroup.worktrees.first(where: {
            canonicalPath($0.path) == canonicalPath(expectedWorktreePath)
        }))
        XCTAssertTrue(sidebarWorktree.isOpen)
        XCTAssertFalse(sidebarWorktree.isActive)
    }

    func testSidebarSelectingRootProjectOpensRealRootSessionInsteadOfFallingBackToAlignmentWorktree() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "develop")
        try fixture.commit(fileName: "README.md", content: "hello")

        let existingWorktreeURL = fixture.rootURL.appendingPathComponent("existing-feature-worktree", isDirectory: true)
        try fixture.git(
            in: fixture.repositoryURL,
            ["worktree", "add", existingWorktreeURL.path, "-b", "feature/payment", "develop"]
        )
        let expectedWorktreePath = existingWorktreeURL.resolvingSymlinksInPath().path

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            name: "支付链路",
            targetBranch: "feature/payment",
            projectPaths: [fixture.repositoryURL.path]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)
        let member = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)
        viewModel.openWorkspaceAlignmentMember(member)

        let workspaceRootPath = try XCTUnwrap(viewModel.openWorkspaceSessions.first(where: {
            $0.isQuickTerminal && $0.workspaceRootContext?.workspaceID == group.id
        })?.projectPath)
        XCTAssertFalse(viewModel.openWorkspaceSessions.contains(where: {
            canonicalPath($0.projectPath) == canonicalPath(fixture.repositoryURL.path) &&
                $0.workspaceRootContext == nil
        }))

        viewModel.activateWorkspaceSidebarProject(fixture.repositoryURL.path)

        XCTAssertEqual(
            canonicalPath(try XCTUnwrap(viewModel.activeWorkspaceProjectPath)),
            canonicalPath(fixture.repositoryURL.path)
        )
        XCTAssertTrue(viewModel.openWorkspaceSessions.contains(where: {
            canonicalPath($0.projectPath) == canonicalPath(fixture.repositoryURL.path) &&
                $0.workspaceRootContext == nil
        }))
        XCTAssertTrue(viewModel.openWorkspaceSessions.contains(where: {
            canonicalPath($0.projectPath) == canonicalPath(expectedWorktreePath) &&
                $0.workspaceAlignmentGroupID == group.id
        }))
        XCTAssertTrue(viewModel.openWorkspaceSessions.contains(where: {
            canonicalPath($0.projectPath) == canonicalPath(workspaceRootPath) &&
                $0.workspaceRootContext?.workspaceID == group.id
        }))

        let rootGroup = try XCTUnwrap(viewModel.workspaceSidebarGroups.first(where: {
            canonicalPath($0.rootProject.path) == canonicalPath(fixture.repositoryURL.path)
        }))
        let sidebarWorktree = try XCTUnwrap(rootGroup.worktrees.first(where: {
            canonicalPath($0.path) == canonicalPath(expectedWorktreePath)
        }))
        XCTAssertTrue(sidebarWorktree.isOpen)
        XCTAssertFalse(sidebarWorktree.isActive)
    }

    func testClosingSyntheticOpenedProjectGroupClosesAlignmentWorktreeButKeepsWorkspaceRoot() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "develop")
        try fixture.commit(fileName: "README.md", content: "hello")

        let existingWorktreeURL = fixture.rootURL.appendingPathComponent("existing-feature-worktree", isDirectory: true)
        try fixture.git(
            in: fixture.repositoryURL,
            ["worktree", "add", existingWorktreeURL.path, "-b", "feature/payment", "develop"]
        )
        let expectedWorktreePath = existingWorktreeURL.resolvingSymlinksInPath().path

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            name: "支付链路",
            targetBranch: "feature/payment",
            projectPaths: [fixture.repositoryURL.path]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)
        let member = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)
        viewModel.openWorkspaceAlignmentMember(member)

        let workspaceRootPath = try XCTUnwrap(viewModel.openWorkspaceSessions.first(where: {
            $0.isQuickTerminal && $0.workspaceRootContext?.workspaceID == group.id
        })?.projectPath)

        viewModel.activateWorkspaceProject(fixture.repositoryURL.path)
        XCTAssertEqual(
            canonicalPath(try XCTUnwrap(viewModel.activeWorkspaceProjectPath)),
            canonicalPath(expectedWorktreePath)
        )

        viewModel.closeWorkspaceProject(fixture.repositoryURL.path)

        XCTAssertFalse(viewModel.openWorkspaceSessions.contains(where: {
            canonicalPath($0.projectPath) == canonicalPath(expectedWorktreePath)
        }))
        XCTAssertTrue(viewModel.openWorkspaceSessions.contains(where: {
            canonicalPath($0.projectPath) == canonicalPath(workspaceRootPath) &&
                $0.workspaceRootContext?.workspaceID == group.id
        }))
        XCTAssertEqual(canonicalPath(try XCTUnwrap(viewModel.activeWorkspaceProjectPath)), canonicalPath(workspaceRootPath))
    }

    func testOpeningRootProjectAfterAlignmentWorktreeDoesNotReownOrCloseAlignmentSession() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "develop")
        try fixture.commit(fileName: "README.md", content: "hello")

        let existingWorktreeURL = fixture.rootURL.appendingPathComponent("existing-feature-worktree", isDirectory: true)
        try fixture.git(
            in: fixture.repositoryURL,
            ["worktree", "add", existingWorktreeURL.path, "-b", "feature/payment", "develop"]
        )
        let expectedWorktreePath = existingWorktreeURL.resolvingSymlinksInPath().path

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            name: "支付链路",
            targetBranch: "feature/payment",
            projectPaths: [fixture.repositoryURL.path]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)
        let member = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)
        viewModel.openWorkspaceAlignmentMember(member)

        let workspaceRootPath = try XCTUnwrap(viewModel.openWorkspaceSessions.first(where: {
            $0.isQuickTerminal && $0.workspaceRootContext?.workspaceID == group.id
        })?.projectPath)

        viewModel.enterWorkspace(fixture.repositoryURL.path)

        XCTAssertEqual(viewModel.openWorkspaceSessions.count, 3)
        XCTAssertTrue(viewModel.openWorkspaceRootProjectPaths.contains(fixture.repositoryURL.path))

        let alignmentWorktreeSession = try XCTUnwrap(viewModel.openWorkspaceSessions.first(where: {
            canonicalPath($0.projectPath) == canonicalPath(expectedWorktreePath)
        }))
        XCTAssertEqual(alignmentWorktreeSession.workspaceAlignmentGroupID, group.id)
        XCTAssertEqual(canonicalPath(alignmentWorktreeSession.rootProjectPath), canonicalPath(fixture.repositoryURL.path))

        let rootGroup = try XCTUnwrap(viewModel.workspaceSidebarGroups.first(where: {
            canonicalPath($0.rootProject.path) == canonicalPath(fixture.repositoryURL.path)
        }))
        let sidebarWorktree = try XCTUnwrap(rootGroup.worktrees.first(where: {
            canonicalPath($0.path) == canonicalPath(expectedWorktreePath)
        }))
        XCTAssertTrue(sidebarWorktree.isOpen)
        XCTAssertFalse(sidebarWorktree.isActive)

        viewModel.closeWorkspaceProject(fixture.repositoryURL.path)

        XCTAssertFalse(viewModel.openWorkspaceSessions.contains(where: {
            canonicalPath($0.projectPath) == canonicalPath(fixture.repositoryURL.path) &&
                $0.workspaceRootContext == nil
        }))
        XCTAssertTrue(viewModel.openWorkspaceSessions.contains(where: {
            canonicalPath($0.projectPath) == canonicalPath(expectedWorktreePath) &&
                $0.workspaceAlignmentGroupID == group.id
        }))
        XCTAssertTrue(viewModel.openWorkspaceSessions.contains(where: {
            canonicalPath($0.projectPath) == canonicalPath(workspaceRootPath) &&
                $0.workspaceRootContext?.workspaceID == group.id
        }))
        XCTAssertEqual(canonicalPath(try XCTUnwrap(viewModel.activeWorkspaceProjectPath)), canonicalPath(expectedWorktreePath))
    }

    func testMemberSpecificTargetBranchOverridesLegacyGroupTargetBranch() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            name: "混合协同",
            targetBranch: "",
            projectPaths: [fixture.repositoryURL.path],
            members: [
                WorkspaceAlignmentMemberDefinition(
                    projectPath: fixture.repositoryURL.path,
                    targetBranch: "main"
                )
            ]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)

        let member = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)
        XCTAssertEqual(member.targetBranch, "main")
        XCTAssertEqual(member.status, .aligned)
        XCTAssertEqual(member.openTarget, .project(projectPath: fixture.repositoryURL.path))
    }

    private func assertWorktreeOpenTarget(
        _ target: WorkspaceAlignmentOpenTarget,
        rootProjectPath: String,
        worktreePath: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .worktree(actualRootProjectPath, actualWorktreePath) = target else {
            XCTFail("期望 worktree open target，实际为 \(target)", file: file, line: line)
            return
        }
        XCTAssertEqual(actualRootProjectPath, rootProjectPath, file: file, line: line)
        XCTAssertEqual(canonicalPath(actualWorktreePath), canonicalPath(worktreePath), file: file, line: line)
    }
}

private enum GitWorkspaceAlignmentFixtureError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message):
            message
        }
    }
}

private struct GitWorkspaceAlignmentFixture {
    let rootURL: URL
    let homeURL: URL
    let repositoryURL: URL

    static func make() throws -> GitWorkspaceAlignmentFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-workspace-alignment-\(UUID().uuidString)", isDirectory: true)
        let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        let repositoryURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        return GitWorkspaceAlignmentFixture(rootURL: rootURL, homeURL: homeURL, repositoryURL: repositoryURL)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func initializeRepository(defaultBranch: String) throws {
        try git(in: repositoryURL, ["init", "-b", defaultBranch])
        try git(in: repositoryURL, ["config", "user.name", "DevHaven Tests"])
        try git(in: repositoryURL, ["config", "user.email", "devhaven-tests@example.com"])
    }

    func commit(fileName: String, content: String) throws {
        let fileURL = repositoryURL.appendingPathComponent(fileName)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        try git(in: repositoryURL, ["add", fileName])
        try git(in: repositoryURL, ["commit", "-m", "init"])
    }

    @MainActor
    func makeViewModel() -> NativeAppViewModel {
        NativeAppViewModel(
            store: LegacyCompatStore(homeDirectoryURL: homeURL),
            worktreeService: NativeGitWorktreeService(homeDirectoryURL: homeURL)
        )
    }

    func makeProject() -> Project {
        let now = Date().timeIntervalSinceReferenceDate
        return Project(
            id: UUID().uuidString,
            name: repositoryURL.lastPathComponent,
            path: repositoryURL.path,
            tags: [],
            runConfigurations: [],
            worktrees: [],
            mtime: now,
            size: 0,
            checksum: UUID().uuidString,
            isGitRepository: true,
            gitCommits: 1,
            gitLastCommit: now,
            created: now,
            checked: now
        )
    }

    @discardableResult
    func git(in directoryURL: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directoryURL

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let message = [stdoutText, stderrText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "未知错误"
            throw GitWorkspaceAlignmentFixtureError.commandFailed("git \(arguments.joined(separator: " ")) 失败：\(message)")
        }
        return stdoutText
    }
}

private func readWorkspaceManifest(at workspaceRootPath: String) throws -> WorkspaceAlignmentRootManifest {
    let manifestURL = URL(fileURLWithPath: workspaceRootPath, isDirectory: true)
        .appendingPathComponent("WORKSPACE.json")
    let manifestData = try Data(contentsOf: manifestURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(WorkspaceAlignmentRootManifest.self, from: manifestData)
}

private func canonicalPath(_ path: String) -> String {
    NSString(string: path).resolvingSymlinksInPath
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
