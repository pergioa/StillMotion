// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sergio Abreo Alvarez

#if canImport(XCTest)
import XCTest
@testable import StillMotion

final class PlaybackPolicyTests: XCTestCase {
    func testNoMediaNeverPlays() {
        let policy = PlaybackPolicy()
        XCTAssertEqual(policy.effectiveState, .noMedia)
        XCTAssertFalse(policy.shouldPlay)
    }

    func testLoadedMediaPlaysWhenUnrestricted() {
        let policy = PlaybackPolicy(hasMedia: true)
        XCTAssertEqual(policy.effectiveState, .playing)
        XCTAssertTrue(policy.shouldPlay)
    }

    func testFullScreenPausesAndResumesWithoutChangingManualIntent() {
        var policy = PlaybackPolicy(hasMedia: true)
        policy.isFullScreenVisible = true
        XCTAssertEqual(policy.effectiveState, .pausedForFullScreen)
        XCTAssertFalse(policy.shouldPlay)
        XCTAssertFalse(policy.isManuallyPaused)

        policy.isFullScreenVisible = false
        XCTAssertEqual(policy.effectiveState, .playing)
        XCTAssertTrue(policy.shouldPlay)
    }

    func testFullScreenOnlyRestrictsTheAffectedDisplay() {
        let policy = PlaybackPolicy(hasMedia: true, isFullScreenVisible: true)

        XCTAssertTrue(policy.shouldPlayIgnoringFullScreen)
        XCTAssertFalse(policy.shouldPlay(onFullScreenDisplay: true))
        XCTAssertTrue(policy.shouldPlay(onFullScreenDisplay: false))
    }

    func testManualPauseSurvivesFullScreenTransition() {
        var policy = PlaybackPolicy(hasMedia: true, isManuallyPaused: true)
        policy.isFullScreenVisible = true
        policy.isFullScreenVisible = false
        XCTAssertEqual(policy.effectiveState, .pausedByUser)
        XCTAssertFalse(policy.shouldPlay)
    }

    func testSystemInactivityPausesPlayback() {
        let policy = PlaybackPolicy(hasMedia: true, isSystemInactive: true)
        XCTAssertEqual(policy.effectiveState, .pausedForSystem)
        XCTAssertFalse(policy.shouldPlay)
    }
}
#else
import Foundation
import StillMotionCore

@main
struct StillMotionLogicChecks {
    static func main() {
        checkPlaybackPolicy()
        checkFullScreenClassification()
        checkMediaValidation()
        print("StillMotion logic checks passed")
    }

    private static func checkPlaybackPolicy() {
        precondition(PlaybackPolicy().effectiveState == .noMedia)
        precondition(PlaybackPolicy(hasMedia: true).shouldPlay)

        var policy = PlaybackPolicy(hasMedia: true)
        policy.isFullScreenVisible = true
        precondition(policy.effectiveState == .pausedForFullScreen)
        policy.isManuallyPaused = true
        policy.isFullScreenVisible = false
        precondition(policy.effectiveState == .pausedByUser)
        policy.isSystemInactive = true
        precondition(!policy.shouldPlay)
    }

    private static func checkFullScreenClassification() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        func window(owner: String = "Example App", pid: pid_t = 123, bounds: CGRect) -> ObservedWindow {
            ObservedWindow(ownerName: owner, ownerPID: pid, layer: 0, bounds: bounds, isOnScreen: true, alpha: 1)
        }

        precondition(FullScreenWindowClassifier.isFullScreenWindow(window(bounds: screen), screenBounds: [screen], ownPID: 999))
        let insideTolerance = CGRect(x: 2.9, y: -2.9, width: 1725.1, height: 1119.9)
        precondition(FullScreenWindowClassifier.isFullScreenWindow(window(bounds: insideTolerance), screenBounds: [screen], ownPID: 999))
        let outsideTolerance = CGRect(x: 3.1, y: 0, width: 1728, height: 1117)
        precondition(!FullScreenWindowClassifier.isFullScreenWindow(window(bounds: outsideTolerance), screenBounds: [screen], ownPID: 999))
        precondition(!FullScreenWindowClassifier.isFullScreenWindow(window(owner: "Finder", bounds: screen), screenBounds: [screen], ownPID: 999))
        precondition(!FullScreenWindowClassifier.isFullScreenWindow(window(pid: 999, bounds: screen), screenBounds: [screen], ownPID: 999))
    }

    private static func checkMediaValidation() {
        try! MediaFileValidator.validateFileMetadata(extension: "MOV", size: 100, isRegularFile: true)
        try! MediaFileValidator.validateFileMetadata(
            extension: "mp4",
            size: MediaFileValidator.maximumFileSize,
            isRegularFile: true
        )

        do {
            try MediaFileValidator.validateFileMetadata(extension: "avi", size: 100, isRegularFile: true)
            preconditionFailure("Unsupported extension was accepted")
        } catch {
            precondition(error as? MediaValidationError == .unsupportedExtension("avi"))
        }

        do {
            try MediaFileValidator.validateFileMetadata(
                extension: "mp4",
                size: MediaFileValidator.maximumFileSize + 1,
                isRegularFile: true
            )
            preconditionFailure("Oversized media was accepted")
        } catch {
            precondition(error as? MediaValidationError == .fileTooLarge(maximumBytes: MediaFileValidator.maximumFileSize))
        }
    }
}
#endif
