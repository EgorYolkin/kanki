import SwiftUI
import XCTest
@testable import Kanki

final class AppAppearanceTests: XCTestCase {
    func testRawValuesAndIdentifiers() {
        XCTAssertEqual(AppAppearance.allCases.map(\.rawValue), ["system", "light", "dark"])
        XCTAssertEqual(AppAppearance.allCases.map(\.id), ["system", "light", "dark"])
        XCTAssertEqual(AppAppearance(rawValue: "dark"), .dark)
        XCTAssertNil(AppAppearance(rawValue: "sepia"))
    }

    func testTitles() {
        XCTAssertEqual(AppAppearance.system.title, "Системное")
        XCTAssertEqual(AppAppearance.light.title, "Светлое")
        XCTAssertEqual(AppAppearance.dark.title, "Тёмное")
    }

    func testColorSchemes() {
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }
}
