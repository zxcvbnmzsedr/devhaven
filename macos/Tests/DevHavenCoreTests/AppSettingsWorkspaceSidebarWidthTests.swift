import XCTest
@testable import DevHavenCore

final class AppSettingsWorkspaceSidebarWidthTests: XCTestCase {
    func testDefaultWorkspaceSidebarWidthUses280Points() {
        XCTAssertEqual(AppSettings().workspaceSidebarWidth, 280)
    }

    func testDecodingMissingWorkspaceSidebarWidthFallsBackTo280Points() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        XCTAssertEqual(settings.workspaceSidebarWidth, 280)
    }

    func testDecodingExplicitWorkspaceSidebarWidthPreservesValue() throws {
        let settings = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(
                """
                {
                  "workspaceSidebarWidth": 336
                }
                """.utf8
            )
        )

        XCTAssertEqual(settings.workspaceSidebarWidth, 336)
    }
}
