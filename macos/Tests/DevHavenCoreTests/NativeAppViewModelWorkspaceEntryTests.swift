import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelWorkspaceEntryTests: XCTestCase {
    func testEnterWorkspaceTracksActiveProjectAndCreatesSingleTabSinglePaneSession() {
        let diagnostics = DiagnosticsCapture()
        let viewModel = makeViewModel(diagnostics: diagnostics.diagnostics)
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.isDetailPanelPresented = true

        viewModel.enterWorkspace(project.path)

        XCTAssertEqual(viewModel.selectedProjectPath, project.path)
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, project.path)
        XCTAssertEqual(viewModel.activeWorkspaceProject?.path, project.path)
        XCTAssertIdentical(viewModel.activeWorkspaceController, viewModel.openWorkspaceSessions.first?.controller)
        XCTAssertFalse(viewModel.isDetailPanelPresented)
        XCTAssertEqual(viewModel.activeWorkspaceState?.tabs.count, 1)
        XCTAssertEqual(viewModel.activeWorkspaceState?.selectedTab?.leaves.count, 1)
        XCTAssertEqual(viewModel.activeWorkspaceLaunchRequest?.projectPath, project.path)
        XCTAssertEqual(
            diagnostics.events,
            [
                .entryRequested(
                    workspaceId: try! XCTUnwrap(viewModel.activeWorkspaceState?.workspaceId),
                    projectPath: project.path,
                    openSessionCount: 1,
                    tabCount: 1,
                    paneCount: 1
                ),
            ]
        )
    }

    func testOpenQuickTerminalCreatesQuickTerminalWorkspaceSessionAndSidebarGroup() {
        let viewModel = makeViewModel()
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        viewModel.isDetailPanelPresented = true

        viewModel.openQuickTerminal()

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [homePath])
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, homePath)
        XCTAssertEqual(viewModel.activeWorkspaceState?.projectPath, homePath)
        XCTAssertFalse(viewModel.isDetailPanelPresented)
        XCTAssertTrue(viewModel.openWorkspaceSessions.first?.isQuickTerminal ?? false)
        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.rootProject, .quickTerminal(at: homePath))
        XCTAssertTrue(viewModel.workspaceSidebarGroups.first?.worktrees.isEmpty ?? false)
    }

    func testCliSessionItemsReflectQuickTerminalSessionsInsteadOfVisibleProjects() {
        let viewModel = makeViewModel()
        let project = makeProject(
            id: "project-1",
            name: "Alpha",
            path: "/tmp/alpha",
            worktrees: [makeWorktree(path: "/tmp/alpha-feature", branch: "feature/demo")]
        )
        viewModel.snapshot.projects = [project]

        XCTAssertTrue(viewModel.cliSessionItems.isEmpty, "CLI 会话区块不应继续从普通项目 / worktree 派生")

        viewModel.openQuickTerminal()

        XCTAssertEqual(viewModel.cliSessionItems.count, 1)
        XCTAssertEqual(viewModel.cliSessionItems.first?.title, "快速终端")
        XCTAssertEqual(viewModel.cliSessionItems.first?.statusText, "已打开")

        viewModel.exitWorkspace()

        XCTAssertEqual(viewModel.cliSessionItems.count, 1)
        XCTAssertEqual(viewModel.cliSessionItems.first?.statusText, "可恢复")
    }


    func testEnteringMultipleProjectsKeepsOpenWorkspaceListAndActivatesLatestProject() {
        let viewModel = makeViewModel()
        let alpha = makeProject(id: "project-1", name: "Alpha", path: "/tmp/alpha")
        let beta = makeProject(id: "project-2", name: "Beta", path: "/tmp/beta")
        viewModel.snapshot.projects = [alpha, beta]

        viewModel.enterWorkspace(alpha.path)
        viewModel.enterWorkspace(beta.path)

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [alpha.path, beta.path])
        XCTAssertEqual(viewModel.openWorkspaceProjects.map(\.path), [alpha.path, beta.path])
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, beta.path)
        XCTAssertEqual(viewModel.activeWorkspaceProject?.path, beta.path)
        XCTAssertEqual(viewModel.activeWorkspaceState?.projectPath, beta.path)
    }

    func testEnteringAlreadyOpenedProjectDoesNotDuplicateWorkspaceSession() {
        let viewModel = makeViewModel()
        let alpha = makeProject(id: "project-1", name: "Alpha", path: "/tmp/alpha")
        let beta = makeProject(id: "project-2", name: "Beta", path: "/tmp/beta")
        viewModel.snapshot.projects = [alpha, beta]

        viewModel.enterWorkspace(alpha.path)
        viewModel.enterWorkspace(beta.path)
        viewModel.enterWorkspace(alpha.path)

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [alpha.path, beta.path])
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, alpha.path)
    }

    func testWorkspaceAvailableProjectsExcludeAlreadyOpenedSessions() {
        let viewModel = makeViewModel()
        let alpha = makeProject(id: "project-1", name: "Alpha", path: "/tmp/alpha")
        let beta = makeProject(id: "project-2", name: "Beta", path: "/tmp/beta")
        let gamma = makeProject(id: "project-3", name: "Gamma", path: "/tmp/gamma")
        viewModel.snapshot.projects = [alpha, beta, gamma]

        viewModel.enterWorkspace(alpha.path)
        viewModel.enterWorkspace(beta.path)

        XCTAssertEqual(viewModel.availableWorkspaceProjects.map(\.path), [gamma.path])
    }

    func testSelectingAnotherProjectWhileWorkspaceIsOpenKeepsOpenedSessionsAlive() {
        let viewModel = makeViewModel()
        let alpha = makeProject(id: "project-1", name: "Alpha", path: "/tmp/alpha")
        let beta = makeProject(id: "project-2", name: "Beta", path: "/tmp/beta")
        let gamma = makeProject(id: "project-3", name: "Gamma", path: "/tmp/gamma")
        viewModel.snapshot.projects = [alpha, beta, gamma]

        viewModel.enterWorkspace(alpha.path)
        viewModel.enterWorkspace(beta.path)

        viewModel.selectProject(gamma.path)

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [alpha.path, beta.path])
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, beta.path)
        XCTAssertEqual(viewModel.selectedProjectPath, gamma.path)
        XCTAssertTrue(viewModel.isDetailPanelPresented)
    }

    func testSwitchingActiveWorkspaceProjectPreservesEachProjectsTopology() throws {
        let viewModel = makeViewModel()
        let alpha = makeProject(id: "project-1", name: "Alpha", path: "/tmp/alpha")
        let beta = makeProject(id: "project-2", name: "Beta", path: "/tmp/beta")
        viewModel.snapshot.projects = [alpha, beta]

        viewModel.enterWorkspace(alpha.path)
        viewModel.createWorkspaceTab()
        viewModel.selectWorkspaceTab(try XCTUnwrap(viewModel.activeWorkspaceState?.tabs.first?.id))
        viewModel.splitWorkspaceFocusedPane(direction: .right)
        let alphaTabCount = viewModel.activeWorkspaceState?.tabs.count
        let alphaPaneCount = viewModel.activeWorkspaceState?.selectedTab?.leaves.count

        viewModel.enterWorkspace(beta.path)
        XCTAssertEqual(viewModel.activeWorkspaceState?.projectPath, beta.path)
        XCTAssertEqual(viewModel.activeWorkspaceState?.tabs.count, 1)
        XCTAssertEqual(viewModel.activeWorkspaceState?.selectedTab?.leaves.count, 1)

        viewModel.activateWorkspaceProject(alpha.path)
        XCTAssertEqual(viewModel.activeWorkspaceState?.projectPath, alpha.path)
        XCTAssertEqual(viewModel.activeWorkspaceState?.tabs.count, alphaTabCount)
        XCTAssertEqual(viewModel.activeWorkspaceState?.selectedTab?.leaves.count, alphaPaneCount)
    }

    func testClosingWorkspaceProjectFallsBackToRemainingProjectAndLastCloseExitsWorkspace() {
        let viewModel = makeViewModel()
        let alpha = makeProject(id: "project-1", name: "Alpha", path: "/tmp/alpha")
        let beta = makeProject(id: "project-2", name: "Beta", path: "/tmp/beta")
        viewModel.snapshot.projects = [alpha, beta]

        viewModel.enterWorkspace(alpha.path)
        viewModel.enterWorkspace(beta.path)

        viewModel.closeWorkspaceProject(beta.path)
        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [alpha.path])
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, alpha.path)
        XCTAssertEqual(viewModel.activeWorkspaceState?.projectPath, alpha.path)

        viewModel.closeWorkspaceProject(alpha.path)
        XCTAssertTrue(viewModel.openWorkspaceProjectPaths.isEmpty)
        XCTAssertTrue(viewModel.openWorkspaceProjects.isEmpty)
        XCTAssertNil(viewModel.activeWorkspaceProjectPath)
        XCTAssertNil(viewModel.activeWorkspaceState)
        XCTAssertFalse(viewModel.isWorkspacePresented)
    }

    func testWorkspaceTabAndPaneActionsMutateActiveWorkspaceState() throws {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        let firstTabID = try XCTUnwrap(viewModel.activeWorkspaceState?.selectedTab?.id)
        let firstPaneID = try XCTUnwrap(viewModel.activeWorkspaceState?.selectedPane?.id)

        viewModel.createWorkspaceTab()
        let secondTabID = try XCTUnwrap(viewModel.activeWorkspaceState?.selectedTab?.id)
        XCTAssertNotEqual(secondTabID, firstTabID)
        XCTAssertEqual(viewModel.activeWorkspaceState?.tabs.count, 2)

        viewModel.selectWorkspaceTab(firstTabID)
        viewModel.splitWorkspaceFocusedPane(direction: .right)
        XCTAssertEqual(viewModel.activeWorkspaceState?.selectedTab?.leaves.count, 2)
        XCTAssertNotEqual(viewModel.activeWorkspaceState?.selectedTab?.focusedPaneId, firstPaneID)

        let focusedPaneID = try XCTUnwrap(viewModel.activeWorkspaceState?.selectedTab?.focusedPaneId)
        viewModel.closeWorkspacePane(focusedPaneID)
        XCTAssertEqual(viewModel.activeWorkspaceState?.selectedTab?.leaves.count, 1)
        XCTAssertEqual(viewModel.activeWorkspaceState?.selectedTab?.focusedPaneId, firstPaneID)
    }

    func testExitWorkspacePreservesOpenSessionsForLaterReentry() {
        let viewModel = makeViewModel()
        let alpha = makeProject(id: "project-1", name: "Alpha", path: "/tmp/alpha")
        let beta = makeProject(id: "project-2", name: "Beta", path: "/tmp/beta")
        viewModel.snapshot.projects = [alpha, beta]

        viewModel.enterWorkspace(alpha.path)
        viewModel.enterWorkspace(beta.path)

        viewModel.exitWorkspace()

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [alpha.path, beta.path])
        XCTAssertNil(viewModel.activeWorkspaceProjectPath)
        XCTAssertNil(viewModel.activeWorkspaceState)
        XCTAssertFalse(viewModel.isWorkspacePresented)

        viewModel.selectProject(alpha.path)
        XCTAssertFalse(viewModel.isWorkspacePresented)
        XCTAssertTrue(viewModel.isDetailPanelPresented)

        viewModel.enterWorkspace(alpha.path)
        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [alpha.path, beta.path])
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, alpha.path)
        XCTAssertEqual(viewModel.activeWorkspaceState?.projectPath, alpha.path)
        XCTAssertTrue(viewModel.isWorkspacePresented)
    }

    func testExitWorkspaceKeepsSingleProjectSessionAvailableForReentry() {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        viewModel.exitWorkspace()

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [project.path])
        XCTAssertEqual(viewModel.openWorkspaceProjects.map(\.path), [project.path])
        XCTAssertNil(viewModel.activeWorkspaceProjectPath)
        XCTAssertNil(viewModel.activeWorkspaceProject)
        XCTAssertNil(viewModel.activeWorkspaceState)
        XCTAssertNil(viewModel.activeWorkspaceLaunchRequest)
        XCTAssertFalse(viewModel.isWorkspacePresented)
    }

    func testEnterOrResumeWorkspaceRestoresLastOpenSessionAfterExit() {
        let viewModel = makeViewModel()
        let alpha = makeProject(id: "project-1", name: "Alpha", path: "/tmp/alpha")
        let beta = makeProject(id: "project-2", name: "Beta", path: "/tmp/beta")
        viewModel.snapshot.projects = [alpha, beta]
        viewModel.enterWorkspace(alpha.path)
        viewModel.enterWorkspace(beta.path)
        viewModel.exitWorkspace()

        viewModel.enterOrResumeWorkspace()

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [alpha.path, beta.path])
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, beta.path)
        XCTAssertEqual(viewModel.activeWorkspaceState?.projectPath, beta.path)
        XCTAssertTrue(viewModel.isWorkspacePresented)
    }

    func testEnterOrResumeWorkspaceCreatesQuickTerminalWhenNoSessionExists() {
        let viewModel = makeViewModel()
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path

        viewModel.enterOrResumeWorkspace()

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [homePath])
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, homePath)
        XCTAssertEqual(viewModel.activeWorkspaceState?.projectPath, homePath)
        XCTAssertTrue(viewModel.openWorkspaceSessions.first?.isQuickTerminal ?? false)
        XCTAssertTrue(viewModel.isWorkspacePresented)
    }

    func testSplitActiveWorkspaceRightAddsPaneToSelectedTab() {
        let viewModel = makeViewModel()
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        viewModel.splitActiveWorkspaceRight()

        XCTAssertEqual(viewModel.activeWorkspaceState?.selectedTab?.leaves.count, 2)
    }

    func testOpenWorkspaceInTerminalRunsOpenCommandForActiveProjectPath() throws {
        let capture = CommandCapture()
        let viewModel = makeViewModel { executable, arguments in
            capture.executable = executable
            capture.arguments = arguments
        }
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        try viewModel.openActiveWorkspaceInTerminal()

        XCTAssertEqual(capture.executable, "/usr/bin/open")
        XCTAssertEqual(capture.arguments, ["-a", "Terminal", project.path])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testOpenWorkspaceInTerminalStoresErrorMessageWhenCommandFails() {
        let viewModel = makeViewModel { _, _ in
            throw TestTerminalRunnerError.launchFailed
        }
        let project = makeProject()
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        XCTAssertThrowsError(try viewModel.openActiveWorkspaceInTerminal())
        XCTAssertEqual(viewModel.errorMessage, "terminal launch failed")
    }

    func testOpenWorkspaceWorktreeCreatesVirtualSessionUnderRootProject() throws {
        let viewModel = makeViewModel(worktreeService: TestWorktreeService())
        let worktree = makeWorktree(path: "/tmp/devhaven-feature", branch: "feature/demo")
        let project = makeProject(worktrees: [worktree])
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        viewModel.openWorkspaceWorktree(worktree.path, from: project.path)

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [project.path, worktree.path])
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, worktree.path)
        XCTAssertEqual(viewModel.activeWorkspaceProject?.path, worktree.path)
        XCTAssertEqual(viewModel.activeWorkspaceProject?.id, "worktree:\(worktree.path)")
        XCTAssertEqual(viewModel.openWorkspaceRootProjectPaths, [project.path])
        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.worktrees.map(\.path), [worktree.path])
    }

    func testCreateWorkspaceWorktreeTracksCreatingProgressAndAutoOpensReadySession() async throws {
        let service = TestWorktreeService()
        service.managedPath = "/tmp/.devhaven/worktrees/devhaven/feature/auto-open"
        service.createResult = NativeWorktreeCreateResult(
            worktreePath: "/tmp/.devhaven/worktrees/devhaven/feature/auto-open",
            branch: "feature/auto-open",
            baseBranch: "develop",
            warning: nil
        )
        service.createProgress = [
            NativeWorktreeProgress(
                worktreePath: "/tmp/.devhaven/worktrees/devhaven/feature/auto-open",
                branch: "feature/auto-open",
                baseBranch: "develop",
                step: .checkingBranch,
                message: "执行中：校验分支与基线可用性..."
            ),
            NativeWorktreeProgress(
                worktreePath: "/tmp/.devhaven/worktrees/devhaven/feature/auto-open",
                branch: "feature/auto-open",
                baseBranch: "develop",
                step: .ready,
                message: "创建完成"
            ),
        ]
        let viewModel = makeViewModel(worktreeService: service)
        let project = makeProject(path: "/tmp/devhaven")
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        try await viewModel.createWorkspaceWorktree(
            from: project.path,
            branch: "feature/auto-open",
            createBranch: true,
            baseBranch: "develop",
            autoOpen: true
        )

        let tracked = try XCTUnwrap(viewModel.workspaceSidebarGroups.first?.worktrees.first)
        XCTAssertEqual(tracked.path, "/tmp/.devhaven/worktrees/devhaven/feature/auto-open")
        XCTAssertEqual(tracked.branch, "feature/auto-open")
        XCTAssertEqual(tracked.status, "ready")
        XCTAssertEqual(tracked.initStep, "ready")
        XCTAssertNil(viewModel.worktreeInteractionState)
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, tracked.path)
        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [project.path, tracked.path])
    }

    func testCreateWorkspaceWorktreeFailureMarksTrackedWorktreeAsFailedAndClearsInteractionLock() async throws {
        let service = TestWorktreeService()
        service.managedPath = "/tmp/.devhaven/worktrees/devhaven/feature/fail"
        service.createProgress = [
            NativeWorktreeProgress(
                worktreePath: "/tmp/.devhaven/worktrees/devhaven/feature/fail",
                branch: "feature/fail",
                baseBranch: "develop",
                step: .checkingBranch,
                message: "执行中：校验分支与基线可用性..."
            )
        ]
        service.createError = NativeWorktreeError.invalidBranch("分支不存在或不可用，请检查分支名称")
        let viewModel = makeViewModel(worktreeService: service)
        let project = makeProject(path: "/tmp/devhaven")
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        await XCTAssertThrowsErrorAsync {
            try await viewModel.createWorkspaceWorktree(
                from: project.path,
                branch: "feature/fail",
                createBranch: true,
                baseBranch: "develop",
                autoOpen: false
            )
        }

        let tracked = try XCTUnwrap(viewModel.workspaceSidebarGroups.first?.worktrees.first)
        XCTAssertEqual(tracked.status, "failed")
        XCTAssertEqual(tracked.initStep, "failed")
        XCTAssertEqual(tracked.initError, "分支不存在或不可用，请检查分支名称")
        XCTAssertNil(viewModel.worktreeInteractionState)
        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [project.path])
    }

    func testWorkspaceNotificationsTrackUnreadAndMoveNotifiedWorktreeToTop() throws {
        let viewModel = makeViewModel()
        let first = makeWorktree(path: "/tmp/devhaven-first", branch: "feature/first")
        let second = makeWorktree(path: "/tmp/devhaven-second", branch: "feature/second")
        let project = makeProject(worktrees: [first, second])
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)
        viewModel.openWorkspaceWorktree(first.path, from: project.path)
        viewModel.openWorkspaceWorktree(second.path, from: project.path)
        viewModel.activateWorkspaceProject(first.path)

        let secondController = try XCTUnwrap(
            viewModel.openWorkspaceSessions.first(where: { $0.projectPath == second.path })?.controller
        )
        let secondTabID = try XCTUnwrap(secondController.selectedTab?.id)
        let secondPaneID = try XCTUnwrap(secondController.selectedPane?.id)

        viewModel.recordWorkspaceNotification(
            projectPath: second.path,
            tabID: secondTabID,
            paneID: secondPaneID,
            title: "任务完成",
            body: "feature/second 已通过"
        )

        let group = try XCTUnwrap(viewModel.workspaceSidebarGroups.first)
        XCTAssertEqual(group.worktrees.map(\.path), [second.path, first.path])
        XCTAssertEqual(group.worktrees.first?.unreadNotificationCount, 1)
        XCTAssertEqual(group.worktrees.first?.notifications.first?.title, "任务完成")
        XCTAssertEqual(viewModel.workspaceAttentionState(for: second.path)?.unreadCount, 1)
    }

    func testFocusWorkspaceNotificationActivatesProjectSelectsTargetAndMarksNotificationRead() throws {
        let viewModel = makeViewModel()
        let worktree = makeWorktree(path: "/tmp/devhaven-focus", branch: "feature/focus")
        let project = makeProject(worktrees: [worktree])
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)
        viewModel.openWorkspaceWorktree(worktree.path, from: project.path)
        viewModel.activateWorkspaceProject(worktree.path)

        let controller = try XCTUnwrap(
            viewModel.openWorkspaceSessions.first(where: { $0.projectPath == worktree.path })?.controller
        )
        let originalTabID = try XCTUnwrap(controller.selectedTab?.id)
        let targetTab = controller.createTab()
        let targetPaneID = try XCTUnwrap(controller.selectedPane?.id)
        controller.selectTab(originalTabID)
        viewModel.activateWorkspaceProject(project.path)

        viewModel.recordWorkspaceNotification(
            projectPath: worktree.path,
            tabID: targetTab.id,
            paneID: targetPaneID,
            title: "测试完成",
            body: "请回到目标 pane"
        )
        let notification = try XCTUnwrap(viewModel.workspaceAttentionState(for: worktree.path)?.notifications.first)

        viewModel.focusWorkspaceNotification(notification)

        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, worktree.path)
        XCTAssertEqual(controller.selectedTabId, targetTab.id)
        XCTAssertEqual(controller.selectedPane?.id, targetPaneID)
        XCTAssertEqual(viewModel.workspaceAttentionState(for: worktree.path)?.unreadCount, 0)
        XCTAssertEqual(viewModel.workspaceAttentionState(for: worktree.path)?.notifications.first?.isRead, true)
    }

    func testWorkspaceTaskStatusReflectsRunningPanesInSidebar() throws {
        let viewModel = makeViewModel()
        let worktree = makeWorktree(path: "/tmp/devhaven-running", branch: "feature/running")
        let project = makeProject(worktrees: [worktree])
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)
        viewModel.openWorkspaceWorktree(worktree.path, from: project.path)

        let controller = try XCTUnwrap(
            viewModel.openWorkspaceSessions.first(where: { $0.projectPath == worktree.path })?.controller
        )
        let paneID = try XCTUnwrap(controller.selectedPane?.id)

        viewModel.updateWorkspaceTaskStatus(projectPath: worktree.path, paneID: paneID, status: .running)
        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.worktrees.first?.taskStatus, .running)

        viewModel.updateWorkspaceTaskStatus(projectPath: worktree.path, paneID: paneID, status: .idle)
        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.worktrees.first?.taskStatus, .idle)
    }

    func testDeleteWorkspaceWorktreeRemovesTrackedItemAndClosesOpenedSession() async throws {
        let service = TestWorktreeService()
        let worktree = makeWorktree(
            path: "/tmp/devhaven-feature",
            branch: "feature/delete",
            baseBranch: "develop",
            status: "ready",
            initStep: "ready"
        )
        let viewModel = makeViewModel(worktreeService: service)
        let project = makeProject(path: "/tmp/devhaven", worktrees: [worktree])
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)
        viewModel.openWorkspaceWorktree(worktree.path, from: project.path)

        try await viewModel.deleteWorkspaceWorktree(worktree.path, from: project.path)

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [project.path])
        XCTAssertTrue(viewModel.workspaceSidebarGroups.first?.worktrees.isEmpty ?? false)
        XCTAssertEqual(service.removedRequests.first?.worktreePath, worktree.path)
        XCTAssertTrue(service.removedRequests.first?.shouldDeleteBranch == true)
    }

    func testRefreshProjectWorktreesMergesGitStateIntoTrackedItems() async throws {
        let service = TestWorktreeService()
        service.listWorktreesResult = [
            NativeGitWorktree(path: "/tmp/devhaven-existing", branch: "feature/existing"),
            NativeGitWorktree(path: "/tmp/devhaven-new", branch: "feature/new"),
        ]
        let project = makeProject(
            path: "/tmp/devhaven",
            worktrees: [
                makeWorktree(
                    path: "/tmp/devhaven-existing",
                    branch: "feature/existing",
                    status: "failed",
                    initStep: "failed",
                    initError: "旧错误"
                )
            ]
        )
        let viewModel = makeViewModel(worktreeService: service)
        viewModel.snapshot.projects = [project]
        viewModel.enterWorkspace(project.path)

        try await viewModel.refreshProjectWorktrees(project.path)

        let worktrees = try XCTUnwrap(viewModel.workspaceSidebarGroups.first?.worktrees)
        XCTAssertEqual(worktrees.map(\.path), ["/tmp/devhaven-existing", "/tmp/devhaven-new"])
        XCTAssertEqual(worktrees.first?.status, "failed")
        XCTAssertEqual(worktrees.first?.initError, "旧错误")
        XCTAssertEqual(worktrees.last?.status, nil)
    }

    private func makeViewModel(
        diagnostics: WorkspaceLaunchDiagnostics = .shared,
        terminalCommandRunner: @escaping @Sendable (String, [String]) throws -> Void = { _, _ in },
        worktreeService: any NativeWorktreeServicing = NativeGitWorktreeService()
    ) -> NativeAppViewModel {
        NativeAppViewModel(
            store: LegacyCompatStore(homeDirectoryURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)),
            projectDocumentLoader: { _ in ProjectDocumentSnapshot(notes: nil, todoItems: [], readmeFallback: nil) },
            gitDailyCollector: { _, _ in [] },
            gitDailyCollectorAsync: { _, _, _ in [] },
            workspaceLaunchDiagnostics: diagnostics,
            terminalCommandRunner: terminalCommandRunner,
            worktreeService: worktreeService
        )
    }

    private func makeProject(
        id: String = "project-1",
        name: String = "DevHaven",
        path: String = "/tmp/devhaven",
        worktrees: [ProjectWorktree] = []
    ) -> Project {
        Project(
            id: id,
            name: name,
            path: path,
            tags: [],
            scripts: [],
            worktrees: worktrees,
            mtime: 1,
            size: 0,
            checksum: "checksum",
            gitCommits: 10,
            gitLastCommit: 1,
            gitLastCommitMessage: "feat: workspace",
            gitDaily: nil,
            created: 1,
            checked: 1
        )
    }

    private func makeWorktree(
        path: String,
        branch: String,
        baseBranch: String? = nil,
        status: String? = nil,
        initStep: String? = nil,
        initError: String? = nil
    ) -> ProjectWorktree {
        ProjectWorktree(
            id: "worktree:\(path)",
            name: URL(fileURLWithPath: path).lastPathComponent,
            path: path,
            branch: branch,
            baseBranch: baseBranch,
            inheritConfig: true,
            created: 1,
            status: status,
            initStep: initStep,
            initMessage: nil,
            initError: initError,
            initJobId: nil,
            updatedAt: 1
        )
    }
}

private final class CommandCapture: @unchecked Sendable {
    var executable: String?
    var arguments: [String] = []
}

private enum TestTerminalRunnerError: LocalizedError {
    case launchFailed

    var errorDescription: String? {
        switch self {
        case .launchFailed:
            return "terminal launch failed"
        }
    }
}

private final class TestWorktreeService: NativeWorktreeServicing, @unchecked Sendable {
    var managedPath = "/tmp/.devhaven/worktrees/devhaven/feature/demo"
    var listBranchesResult = [
        NativeGitBranch(name: "main", isMain: true),
        NativeGitBranch(name: "develop", isMain: false),
    ]
    var listWorktreesResult = [NativeGitWorktree]()
    var createProgress = [NativeWorktreeProgress]()
    var createResult = NativeWorktreeCreateResult(
        worktreePath: "/tmp/.devhaven/worktrees/devhaven/feature/demo",
        branch: "feature/demo",
        baseBranch: "develop",
        warning: nil
    )
    var createError: Error?
    var removedRequests = [NativeWorktreeRemoveRequest]()

    func managedWorktreePath(for sourceProjectPath: String, branch: String) throws -> String {
        managedPath
    }

    func currentBranch(at projectPath: String) throws -> String {
        "main"
    }

    func listBranches(at projectPath: String) throws -> [NativeGitBranch] {
        listBranchesResult
    }

    func listWorktrees(at projectPath: String) throws -> [NativeGitWorktree] {
        listWorktreesResult
    }

    func createWorktree(
        _ request: NativeWorktreeCreateRequest,
        progress: @escaping @Sendable (NativeWorktreeProgress) -> Void
    ) throws -> NativeWorktreeCreateResult {
        for update in createProgress {
            progress(update)
        }
        if let createError {
            throw createError
        }
        return createResult
    }

    func removeWorktree(_ request: NativeWorktreeRemoveRequest) throws -> NativeWorktreeRemoveResult {
        removedRequests.append(request)
        return NativeWorktreeRemoveResult(warning: nil)
    }
}

@MainActor
private final class DiagnosticsCapture {
    var events = [WorkspaceLaunchDiagnosticEvent]()

    lazy var diagnostics = WorkspaceLaunchDiagnostics(
        now: { 1_000 },
        logSink: { _ in },
        eventSink: { [weak self] event in
            self?.events.append(event)
        }
    )
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    _ expression: @escaping () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("预期抛出错误，但实际未抛出", file: file, line: line)
    } catch {
        // expected
    }
}
