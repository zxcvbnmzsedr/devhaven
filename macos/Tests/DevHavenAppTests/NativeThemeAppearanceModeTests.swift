import XCTest
import SwiftUI
import DevHavenCore
@testable import DevHavenApp

final class NativeThemeAppearanceModeTests: XCTestCase {
    func testPreferredColorSchemeForSystemReturnsNil() {
        XCTAssertNil(NativeTheme.preferredColorScheme(for: .system))
    }

    func testPreferredColorSchemeForLightReturnsLight() {
        XCTAssertEqual(NativeTheme.preferredColorScheme(for: .light), .light)
    }

    func testPreferredColorSchemeForDarkReturnsDark() {
        XCTAssertEqual(NativeTheme.preferredColorScheme(for: .dark), .dark)
    }
}
