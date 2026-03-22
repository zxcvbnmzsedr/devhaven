import XCTest
import DevHavenCore
@testable import DevHavenApp

final class WorkspaceNotificationPresenterTests: XCTestCase {
    func testSystemNotificationSupportRequiresAppBundleAndIdentifier() {
        XCTAssertTrue(
            WorkspaceNotificationPresenter.supportsSystemNotifications(
                bundleURL: URL(fileURLWithPath: "/Applications/DevHaven.app", isDirectory: true),
                bundleIdentifier: "com.devhaven.app"
            )
        )

        XCTAssertFalse(
            WorkspaceNotificationPresenter.supportsSystemNotifications(
                bundleURL: URL(fileURLWithPath: "/tmp/.build/debug/DevHavenApp", isDirectory: false),
                bundleIdentifier: "com.devhaven.app"
            )
        )

        XCTAssertFalse(
            WorkspaceNotificationPresenter.supportsSystemNotifications(
                bundleURL: URL(fileURLWithPath: "/tmp/DevHavenNativePackageTests.xctest", isDirectory: true),
                bundleIdentifier: "com.devhaven.tests"
            )
        )

        XCTAssertFalse(
            WorkspaceNotificationPresenter.supportsSystemNotifications(
                bundleURL: URL(fileURLWithPath: "/Applications/DevHaven.app", isDirectory: true),
                bundleIdentifier: nil
            )
        )
    }

    func testPresentationRouteFallsBackToSoundWhenSystemNotificationsUnsupported() {
        var settings = AppSettings(
            workspaceNotificationSoundEnabled: true,
            workspaceSystemNotificationsEnabled: true
        )

        XCTAssertEqual(
            WorkspaceNotificationPresenter.presentationRoute(
                settings: settings,
                supportsSystemNotifications: false
            ),
            .soundOnly
        )

        settings.workspaceNotificationSoundEnabled = false
        XCTAssertEqual(
            WorkspaceNotificationPresenter.presentationRoute(
                settings: settings,
                supportsSystemNotifications: false
            ),
            .none
        )

        XCTAssertEqual(
            WorkspaceNotificationPresenter.presentationRoute(
                settings: AppSettings(
                    workspaceNotificationSoundEnabled: false,
                    workspaceSystemNotificationsEnabled: true
                ),
                supportsSystemNotifications: true
            ),
            .systemNotification
        )
    }
}
