import XCTest

final class WorkspaceProjectPickerViewTests: XCTestCase {
    func testProjectPickerRequestsInitialSearchFocus() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains("@FocusState private var isSearchFieldFocused: Bool"),
            "打开项目弹窗应显式维护搜索框焦点，避免默认 key view 漂到关闭按钮"
        )
        XCTAssertTrue(
            source.contains(".focused($isSearchFieldFocused)"),
            "打开项目弹窗的搜索框应绑定 FocusState，确保默认焦点落在输入框"
        )
        XCTAssertTrue(
            source.contains(".onAppear {\n            requestInitialSearchFocus()\n        }"),
            "打开项目弹窗出现时应主动请求搜索框焦点"
        )
        XCTAssertTrue(
            source.contains("private func requestInitialSearchFocus() {\n        DispatchQueue.main.async {\n            isSearchFieldFocused = true\n        }\n    }"),
            "打开项目弹窗应异步把第一焦点切到搜索框，避免被 SwiftUI 初始 key view 覆盖"
        )
    }

    func testProjectPickerCloseButtonDoesNotStealFocus() throws {
        let source = try String(contentsOf: sourceFileURL(), encoding: .utf8)

        XCTAssertTrue(
            source.contains(".focusable(false)"),
            "打开项目弹窗的关闭按钮不应抢走默认焦点"
        )
    }

    private func sourceFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DevHavenApp/WorkspaceProjectPickerView.swift")
    }
}
