import XCTest
import AppKit
@testable import DevHavenApp

@MainActor
final class DevHavenAppDelegateTests: XCTestCase {
    func testApplicationDidFinishLaunchingDisablesAutomaticWindowTabbing() {
        let original = NSWindow.allowsAutomaticWindowTabbing
        defer {
            NSWindow.allowsAutomaticWindowTabbing = original
        }

        NSWindow.allowsAutomaticWindowTabbing = true
        let delegate = DevHavenAppDelegate()
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertFalse(
            NSWindow.allowsAutomaticWindowTabbing,
            "DevHaven 启动后应禁用系统自动 window tabbing，避免 ⌘T 走到 macOS 原生窗口 tab。"
        )
    }
}
