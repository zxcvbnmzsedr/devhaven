import XCTest
@testable import DevHavenApp

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
