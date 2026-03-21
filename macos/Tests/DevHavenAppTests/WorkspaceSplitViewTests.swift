import XCTest

final class WorkspaceSplitViewTests: XCTestCase {
    func testSplitViewExposesOptionalRatioChangeEndedCallback() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("let onRatioChangeEnded: ((Double) -> Void)?"),
            "可拖拽分栏应显式提供拖拽结束回调，供宿主持久化最终宽度"
        )
        XCTAssertTrue(
            source.contains(".onEnded { gesture in"),
            "分栏拖拽手势应在结束时触发回调"
        )
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceSplitView.swift")
    }
}
