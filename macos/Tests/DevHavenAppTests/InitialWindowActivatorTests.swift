import XCTest
@testable import DevHavenApp

@MainActor
final class InitialWindowActivatorTests: XCTestCase {
    func testActivateIfNeededActivatesApplicationAndWindowOncePerWindowNumber() {
        let application = ApplicationSpy()
        let activator = InitialWindowActivator(application: application)
        let window = WindowSpy(windowNumber: 42)

        activator.activateIfNeeded(window: window)
        activator.activateIfNeeded(window: window)

        XCTAssertEqual(application.setRegularActivationPolicyCallCount, 1)
        XCTAssertEqual(application.activateIgnoringOtherAppsCallCount, 1)
        XCTAssertEqual(window.orderFrontRegardlessCallCount, 1)
        XCTAssertEqual(window.makeKeyCallCount, 1)
    }

    func testActivateIfNeededReactivatesWhenWindowChanges() {
        let application = ApplicationSpy()
        let activator = InitialWindowActivator(application: application)

        activator.activateIfNeeded(window: WindowSpy(windowNumber: 1))
        activator.activateIfNeeded(window: WindowSpy(windowNumber: 2))

        XCTAssertEqual(application.setRegularActivationPolicyCallCount, 2)
        XCTAssertEqual(application.activateIgnoringOtherAppsCallCount, 2)
    }
}

@MainActor
final class MainWindowRestorerTests: XCTestCase {
    func testShowMainWindowIfNeededRestoresTrackedMainWindowWhenAppHasNoVisibleWindows() {
        let window = RestorableWindowSpy(identifier: "main", isVisible: false, isMiniaturized: true)
        let application = RestorableApplicationSpy(windows: [window])
        let restorer = MainWindowRestorer()

        let restored = restorer.showMainWindowIfNeeded(application: application)

        XCTAssertTrue(restored)
        XCTAssertEqual(window.deminiaturizeCallCount, 1)
        XCTAssertEqual(window.makeKeyAndOrderFrontCallCount, 1)
        XCTAssertEqual(application.activateIgnoringOtherAppsCallCount, 1)
    }

    func testShowMainWindowIfNeededDoesNothingWhenVisibleWindowAlreadyExists() {
        let visibleWindow = RestorableWindowSpy(identifier: "main", isVisible: true, isMiniaturized: false)
        let hiddenWindow = RestorableWindowSpy(identifier: "secondary", isVisible: false, isMiniaturized: false)
        let application = RestorableApplicationSpy(windows: [visibleWindow, hiddenWindow])
        let restorer = MainWindowRestorer()

        let restored = restorer.showMainWindowIfNeeded(application: application)

        XCTAssertFalse(restored)
        XCTAssertEqual(visibleWindow.makeKeyAndOrderFrontCallCount, 0)
        XCTAssertEqual(hiddenWindow.makeKeyAndOrderFrontCallCount, 0)
        XCTAssertEqual(application.activateIgnoringOtherAppsCallCount, 0)
    }
}

@MainActor
final class MainWindowCloseConfirmationHandlerTests: XCTestCase {
    func testTrackedWindowCancelRejectsClose() {
        let prompt = ClosePromptSpy(shouldConfirm: false)
        let handler = MainWindowCloseConfirmationHandler(prompt: prompt)
        handler.track(windowNumber: 42)

        let shouldAllowClose = handler.shouldAllowClose(windowNumber: 42)

        XCTAssertFalse(shouldAllowClose)
        XCTAssertEqual(prompt.confirmCallCount, 1)
    }

    func testTrackedWindowConfirmAllowsClose() {
        let prompt = ClosePromptSpy(shouldConfirm: true)
        let handler = MainWindowCloseConfirmationHandler(prompt: prompt)
        handler.track(windowNumber: 7)

        let shouldAllowClose = handler.shouldAllowClose(windowNumber: 7)

        XCTAssertTrue(shouldAllowClose)
        XCTAssertEqual(prompt.confirmCallCount, 1)
    }

    func testUntrackedWindowFallsThroughWithoutPrompt() {
        let prompt = ClosePromptSpy(shouldConfirm: true)
        let handler = MainWindowCloseConfirmationHandler(prompt: prompt)
        handler.track(windowNumber: 1)

        let shouldAllowClose = handler.shouldAllowClose(windowNumber: 2)

        XCTAssertTrue(shouldAllowClose)
        XCTAssertEqual(prompt.confirmCallCount, 0)
    }
}

@MainActor
final class MainWindowClosePromptCopyTests: XCTestCase {
    func testHomepageWindowClosePromptUsesConciseCopy() {
        XCTAssertEqual(AppKitMainWindowClosePrompt.copy.title, "关闭 DevHaven？")
        XCTAssertEqual(AppKitMainWindowClosePrompt.copy.informativeText, "这会关闭主窗口。")
        XCTAssertEqual(AppKitMainWindowClosePrompt.copy.confirmButtonTitle, "关闭窗口")
        XCTAssertEqual(AppKitMainWindowClosePrompt.copy.cancelButtonTitle, "取消")
    }
}

final class MainWindowCloseShortcutPlannerTests: XCTestCase {
    func testPlannerClosesOverlayBeforeWorkspaceHierarchy() {
        let planner = MainWindowCloseShortcutPlanner()
        let action = planner.action(
            for: MainWindowCloseShortcutContext(
                isDashboardPresented: false,
                isSettingsPresented: true,
                isRecycleBinPresented: false,
                isDetailPanelPresented: true,
                workspace: MainWindowCloseShortcutWorkspaceContext(
                    selectedPaneID: "pane-1",
                    selectedTabID: "tab-1",
                    selectedTabPaneCount: 2,
                    tabCount: 3
                )
            )
        )

        XCTAssertEqual(action, .hideSettings)
    }

    func testPlannerClosesFocusedPaneBeforeClosingTab() {
        let planner = MainWindowCloseShortcutPlanner()
        let action = planner.action(
            for: MainWindowCloseShortcutContext(
                isDashboardPresented: false,
                isSettingsPresented: false,
                isRecycleBinPresented: false,
                isDetailPanelPresented: false,
                workspace: MainWindowCloseShortcutWorkspaceContext(
                    selectedPaneID: "pane-2",
                    selectedTabID: "tab-1",
                    selectedTabPaneCount: 2,
                    tabCount: 2
                )
            )
        )

        XCTAssertEqual(action, .closePane("pane-2"))
    }

    func testPlannerClosesSelectedDiffTabBeforePaneAndTerminalTab() {
        let planner = MainWindowCloseShortcutPlanner()
        let action = planner.action(
            for: MainWindowCloseShortcutContext(
                isDashboardPresented: false,
                isSettingsPresented: false,
                isRecycleBinPresented: false,
                isDetailPanelPresented: false,
                workspace: MainWindowCloseShortcutWorkspaceContext(
                    selectedPaneID: "pane-2",
                    selectedTabID: "tab-1",
                    selectedDiffTabID: "diff-1",
                    selectedTabPaneCount: 2,
                    tabCount: 2
                )
            )
        )

        XCTAssertEqual(action, .closeDiffTab("diff-1"))
    }

    func testPlannerClosesTabWhenSelectedTabHasSinglePaneButWorkspaceHasMultipleTabs() {
        let planner = MainWindowCloseShortcutPlanner()
        let action = planner.action(
            for: MainWindowCloseShortcutContext(
                isDashboardPresented: false,
                isSettingsPresented: false,
                isRecycleBinPresented: false,
                isDetailPanelPresented: false,
                workspace: MainWindowCloseShortcutWorkspaceContext(
                    selectedPaneID: "pane-1",
                    selectedTabID: "tab-2",
                    selectedTabPaneCount: 1,
                    tabCount: 3
                )
            )
        )

        XCTAssertEqual(action, .closeTab("tab-2"))
    }

    func testPlannerExitsWorkspaceWhenLastTabAndPaneWouldOtherwiseBeClosed() {
        let planner = MainWindowCloseShortcutPlanner()
        let action = planner.action(
            for: MainWindowCloseShortcutContext(
                isDashboardPresented: false,
                isSettingsPresented: false,
                isRecycleBinPresented: false,
                isDetailPanelPresented: false,
                workspace: MainWindowCloseShortcutWorkspaceContext(
                    selectedPaneID: "pane-1",
                    selectedTabID: "tab-1",
                    selectedTabPaneCount: 1,
                    tabCount: 1
                )
            )
        )

        XCTAssertEqual(action, .exitWorkspace)
    }

    func testPlannerRequestsWindowCloseOnlyWhenAlreadyAtHomepage() {
        let planner = MainWindowCloseShortcutPlanner()
        let action = planner.action(
            for: MainWindowCloseShortcutContext(
                isDashboardPresented: false,
                isSettingsPresented: false,
                isRecycleBinPresented: false,
                isDetailPanelPresented: false,
                workspace: nil
            )
        )

        XCTAssertEqual(action, .closeWindow)
    }
}

private final class ApplicationSpy: ApplicationActivating {
    private(set) var setRegularActivationPolicyCallCount = 0
    private(set) var activateIgnoringOtherAppsCallCount = 0

    func setRegularActivationPolicy() {
        setRegularActivationPolicyCallCount += 1
    }

    func activateIgnoringOtherApps() {
        activateIgnoringOtherAppsCallCount += 1
    }
}

private final class WindowSpy: WindowActivating {
    let windowNumber: Int
    private(set) var orderFrontRegardlessCallCount = 0
    private(set) var makeKeyCallCount = 0

    init(windowNumber: Int) {
        self.windowNumber = windowNumber
    }

    func orderFrontRegardless() {
        orderFrontRegardlessCallCount += 1
    }

    func makeKey() {
        makeKeyCallCount += 1
    }
}

private final class RestorableApplicationSpy: MainWindowRestoringApplication {
    let windows: [any MainWindowRestoringWindow]
    private(set) var activateIgnoringOtherAppsCallCount = 0

    init(windows: [any MainWindowRestoringWindow]) {
        self.windows = windows
    }

    func activateIgnoringOtherApps() {
        activateIgnoringOtherAppsCallCount += 1
    }
}

private final class RestorableWindowSpy: MainWindowRestoringWindow {
    let identifier: String?
    let isVisible: Bool
    let isMiniaturized: Bool
    private(set) var deminiaturizeCallCount = 0
    private(set) var makeKeyAndOrderFrontCallCount = 0

    init(identifier: String?, isVisible: Bool, isMiniaturized: Bool) {
        self.identifier = identifier
        self.isVisible = isVisible
        self.isMiniaturized = isMiniaturized
    }

    func deminiaturize() {
        deminiaturizeCallCount += 1
    }

    func makeKeyAndOrderFront() {
        makeKeyAndOrderFrontCallCount += 1
    }
}

private final class ClosePromptSpy: MainWindowClosePrompting {
    let shouldConfirm: Bool
    private(set) var confirmCallCount = 0

    init(shouldConfirm: Bool) {
        self.shouldConfirm = shouldConfirm
    }

    func confirmCloseMainWindow() -> Bool {
        confirmCallCount += 1
        return shouldConfirm
    }
}
