// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sergio Abreo Alvarez

#if canImport(XCTest)
import CoreGraphics
import XCTest
@testable import StillMotion

final class FullScreenWindowClassifierTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    func testExactScreenBoundsAreFullScreen() {
        XCTAssertTrue(classify(makeWindow(bounds: screen)))
    }

    func testVisibleFrameSizedMaximizedWindowIsNotFullScreen() {
        XCTAssertFalse(classify(makeWindow(bounds: CGRect(x: 0, y: 25, width: 1728, height: 1068))))
    }

    func testPixelToleranceBoundary() {
        XCTAssertTrue(classify(makeWindow(bounds: CGRect(x: 2.9, y: -2.9, width: 1725.1, height: 1119.9))))
        XCTAssertFalse(classify(makeWindow(bounds: CGRect(x: 3.1, y: 0, width: 1728, height: 1117))))
    }

    func testSecondaryDisplayCanTriggerFullScreen() {
        let secondary = CGRect(x: 1728, y: -200, width: 2560, height: 1440)
        XCTAssertTrue(
            FullScreenWindowClassifier.containsFullScreenWindow(
                windows: [makeWindow(bounds: secondary)],
                screenBounds: [screen, secondary],
                ownPID: 999
            )
        )
    }

    func testReportsOnlyScreensContainingFullScreenWindows() {
        let secondary = CGRect(x: 1728, y: -200, width: 2560, height: 1440)
        let indexes = FullScreenWindowClassifier.fullScreenScreenIndexes(
            windows: [makeWindow(bounds: secondary)],
            screenBounds: [screen, secondary],
            ownPID: 999
        )

        XCTAssertEqual(indexes, [1])
    }

    func testReportsMultipleFullScreenDisplays() {
        let secondary = CGRect(x: 1728, y: -200, width: 2560, height: 1440)
        let indexes = FullScreenWindowClassifier.fullScreenScreenIndexes(
            windows: [makeWindow(bounds: screen), makeWindow(bounds: secondary)],
            screenBounds: [screen, secondary],
            ownPID: 999
        )

        XCTAssertEqual(indexes, [0, 1])
    }

    func testOwnAndIrrelevantWindowsAreExcluded() {
        XCTAssertFalse(classify(makeWindow(ownerPID: 999, bounds: screen)))
        for owner in ["Finder", "Dock", "Window Server", "Control Center", "SystemUIServer"] {
            XCTAssertFalse(classify(makeWindow(ownerName: owner, bounds: screen)), owner)
        }
    }

    func testNonzeroLayerAndOffscreenWindowsAreExcluded() {
        XCTAssertFalse(classify(makeWindow(layer: 1, bounds: screen)))
        XCTAssertFalse(classify(makeWindow(bounds: screen, isOnScreen: false)))
    }

    private func classify(_ window: ObservedWindow) -> Bool {
        FullScreenWindowClassifier.isFullScreenWindow(window, screenBounds: [screen], ownPID: 999)
    }

    private func makeWindow(
        ownerName: String = "Example App",
        ownerPID: pid_t = 123,
        layer: Int = 0,
        bounds: CGRect,
        isOnScreen: Bool = true
    ) -> ObservedWindow {
        ObservedWindow(
            ownerName: ownerName,
            ownerPID: ownerPID,
            layer: layer,
            bounds: bounds,
            isOnScreen: isOnScreen,
            alpha: 1
        )
    }
}
#endif
