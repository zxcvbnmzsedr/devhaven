import XCTest
@testable import DevHavenCore

final class AppSettingsUpdatePreferencesTests: XCTestCase {
    func testDefaultsProvideStableChannelAndAutomaticChecks() {
        let settings = AppSettings()

        XCTAssertEqual(settings.updateChannel, .stable)
        XCTAssertTrue(settings.updateAutomaticallyChecks)
        XCTAssertFalse(settings.updateAutomaticallyDownloads)
        XCTAssertEqual(settings.workspaceOpenProjectShortcut.key.rawValue, "k")
        XCTAssertFalse(settings.workspaceOpenProjectShortcut.usesShift)
        XCTAssertFalse(settings.workspaceOpenProjectShortcut.usesOption)
        XCTAssertFalse(settings.workspaceOpenProjectShortcut.usesControl)
    }

    func testDecodingLegacySettingsFallsBackToUpdateDefaults() throws {
        let data = Data(
            """
            {
              \"editorOpenTool\": {\"commandPath\": \"\", \"arguments\": []},
              \"terminalOpenTool\": {\"commandPath\": \"\", \"arguments\": []},
              \"terminalUseWebglRenderer\": true,
              \"terminalTheme\": \"DevHaven Dark\",
              \"gitIdentities\": [],
              \"projectListViewMode\": \"card\",
              \"workspaceSidebarWidth\": 280,
              \"workspaceInAppNotificationsEnabled\": true,
              \"workspaceNotificationSoundEnabled\": true,
              \"workspaceSystemNotificationsEnabled\": false,
              \"moveNotifiedWorktreeToTop\": true,
              \"viteDevPort\": 1420,
              \"webEnabled\": true,
              \"webBindHost\": \"0.0.0.0\",
              \"webBindPort\": 3210
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.updateChannel, .stable)
        XCTAssertTrue(settings.updateAutomaticallyChecks)
        XCTAssertFalse(settings.updateAutomaticallyDownloads)
        XCTAssertEqual(settings.workspaceOpenProjectShortcut.key.rawValue, "k")
        XCTAssertFalse(settings.workspaceOpenProjectShortcut.usesShift)
        XCTAssertFalse(settings.workspaceOpenProjectShortcut.usesOption)
        XCTAssertFalse(settings.workspaceOpenProjectShortcut.usesControl)
    }
}
