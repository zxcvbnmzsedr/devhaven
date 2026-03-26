import XCTest

final class WorkspaceDiffNavigationBarViewTests: XCTestCase {
    func testNavigationBarShowsPreviousNextDifferenceAndCounters() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("Previous Difference"), "navigation bar 应提供 previous difference 入口")
        XCTAssertTrue(source.contains("Next Difference"), "navigation bar 应提供 next difference 入口")
        XCTAssertTrue(source.contains("navigatorState.currentDifferenceIndex"), "navigation bar 应展示当前差异序号")
        XCTAssertTrue(source.contains("navigatorState.currentRequestIndex"), "navigation bar 应展示当前文件序号")
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
