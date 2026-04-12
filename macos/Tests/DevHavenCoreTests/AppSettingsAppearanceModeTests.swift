import XCTest
import DevHavenCore

final class AppSettingsAppearanceModeTests: XCTestCase {
    func testDecodingFallsBackToSystemAppearanceModeWhenFieldMissing() throws {
        let json = """
        {
          "settings": {
            "terminalTheme": "DevHaven Dark"
          }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let state = try decoder.decode(AppStateFile.self, from: json)

        XCTAssertEqual(state.settings.appAppearanceMode, .system)
    }

    func testEncodingAndDecodingPreservesAppearanceMode() throws {
        let original = AppStateFile(
            settings: AppSettings(appAppearanceMode: .light)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AppStateFile.self, from: data)

        XCTAssertEqual(decoded.settings.appAppearanceMode, .light)
    }
}
