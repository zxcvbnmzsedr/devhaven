import Foundation

func check(_ actual: String, _ expected: String) {
    guard actual == expected else {
        fatalError("Expected '\(expected)', got '\(actual)'; languages=\(Bundle.main.preferredLocalizations)")
    }
}

check(String(localized: "contextMenu.workspaceGroup.newEmpty", defaultValue: "New Empty Workspace Group"), "新建空工作区组")
check(String(localized: "contextMenu.pinWorkspace", defaultValue: "Pin Workspace"), "固定工作区")
check(String(localized: "notification.desktop.defaultTerminalTitle", defaultValue: "Terminal"), "终端")
check(String(localized: "settings.section.computerUse", defaultValue: "Computer Use"), "电脑操作")
check(String(localized: "settings.automation.rules", defaultValue: "Automation Rules"), "自动化规则")
check(String(format: String(localized: "Terminal %lld"), 1), "终端 1")
check(String(localized: "Split Right"), "向右分屏")
check(Bundle.main.localizedString(forKey: "workspaceColor.name.Red", value: "Red", table: nil), "红色")
check(Bundle.main.localizedString(forKey: "workspaceColor.name.My custom color", value: "My custom color", table: nil), "My custom color")
check(String(format: String(localized: "agentSession.web.log.sentCharsFormat"), 2), "已发送 2 个字符")

let frameworkURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CMUX_TEST_FRAMEWORK"]!)
let resources = frameworkURL.appendingPathComponent("Resources")
let bonsplit = Bundle(url: resources.appendingPathComponent("Bonsplit_Bonsplit.bundle"))!
check(bonsplit.localizedString(forKey: "tabContext.renameTab", value: "Rename Tab…", table: nil), "重命名标签页…")
check(bonsplit.localizedString(forKey: "tabContext.forkConversation.right", value: "Right Split", table: nil), "右侧分屏")
let settings = Bundle(url: resources.appendingPathComponent("CmuxSettingsUI_CmuxSettingsUI.bundle"))!
check(settings.localizedString(forKey: "settings.automation.rules", value: "Automation Rules", table: nil), "自动化规则")
print("PASS: main bundle, package bundles, Chinese plurals and tab menus (\(Bundle.main.bundleURL.path))")
