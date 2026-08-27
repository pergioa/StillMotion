#if canImport(XCTest)
import XCTest
@testable import StillMotion

final class WallpaperWindowTests: XCTestCase {
    func testWallpaperUsesLevelImmediatelyAbovePublicDesktopLevel() {
        let level = WallpaperWindow.wallpaperLevel(desktopLevel: -100)

        XCTAssertEqual(level, -99)
        XCTAssertLessThan(level, -80)
    }

    func testWallpaperLevelPreservesNegativeDesktopLevel() {
        XCTAssertEqual(WallpaperWindow.wallpaperLevel(desktopLevel: -80), -79)
    }
}
#endif
