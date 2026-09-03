// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sergio Abreo Alvarez

#if canImport(XCTest)
import XCTest
@testable import StillMotion

final class WallpaperWindowTests: XCTestCase {
    func testSystemWallpaperFrameNamePreservesVideoExtension() {
        let videoURL = URL(fileURLWithPath: "/tmp/Background-123.mp4")

        XCTAssertEqual(systemWallpaperFrameName(for: videoURL), "Background-123.mp4.jpg")
    }

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
