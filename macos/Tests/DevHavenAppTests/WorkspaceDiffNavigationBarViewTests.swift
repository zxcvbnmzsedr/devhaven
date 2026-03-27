import XCTest

final class WorkspaceDiffNavigationBarViewTests: XCTestCase {
    func testNavigationBarShowsPreviousNextDifferenceAndCounters() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("Image(systemName: \"chevron.up\")"), "navigation bar 应把 previous difference 入口改成图标按钮")
        XCTAssertTrue(source.contains("Image(systemName: \"chevron.down\")"), "navigation bar 应把 next difference 入口改成图标按钮")
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Previous Difference\")"), "图标按钮仍应保留 previous difference 的可访问语义")
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Next Difference\")"), "图标按钮仍应保留 next difference 的可访问语义")
        XCTAssertTrue(source.contains("navigatorState.currentDifferenceIndex"), "navigation bar 应展示当前差异序号")
        XCTAssertTrue(source.contains("navigatorState.currentRequestIndex"), "navigation bar 应展示当前文件序号")
    }

    func testNavigationBarSupportsFilteringAvailableViewerModes() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("let availableViewerModes: [WorkspaceDiffViewerMode]"), "navigation bar 应显式接收当前文档支持的 viewer mode 集合")
        XCTAssertTrue(source.contains("if availableViewerModes.count > 1"), "当当前文档不支持切换时，navigation bar 不应继续展示无效 segmented control")
        XCTAssertTrue(source.contains("availableViewerModes.contains(.sideBySide)"), "navigation bar 应按支持集合决定是否展示并排模式")
        XCTAssertTrue(source.contains("availableViewerModes.contains(.unified)"), "navigation bar 应按支持集合决定是否展示统一模式")
    }

    func testNavigationBarDisablesButtonsFromProcessorState() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains(".disabled(!navigatorState.canGoPrevious)"), "previous difference 按钮禁用态必须来自 processor navigator state")
        XCTAssertTrue(source.contains(".disabled(!navigatorState.canGoNext)"), "next difference 按钮禁用态必须来自 processor navigator state")
        XCTAssertTrue(source.contains("onPreviousDifference"), "navigation bar 必须通过回调桥接 previous difference")
        XCTAssertTrue(source.contains("onNextDifference"), "navigation bar 必须通过回调桥接 next difference")
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceDiffNavigationBarView.swift")
    }
}
