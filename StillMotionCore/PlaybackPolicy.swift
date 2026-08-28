import Foundation

public struct PlaybackPolicy: Equatable {
    public enum EffectiveState: Equatable {
        case noMedia
        case playing
        case pausedByUser
        case pausedForFullScreen
        case pausedForSystem
    }

    public var hasMedia: Bool
    public var isManuallyPaused: Bool
    public var isFullScreenVisible: Bool
    public var isSystemInactive: Bool

    public init(
        hasMedia: Bool = false,
        isManuallyPaused: Bool = false,
        isFullScreenVisible: Bool = false,
        isSystemInactive: Bool = false
    ) {
        self.hasMedia = hasMedia
        self.isManuallyPaused = isManuallyPaused
        self.isFullScreenVisible = isFullScreenVisible
        self.isSystemInactive = isSystemInactive
    }

    public var effectiveState: EffectiveState {
        guard hasMedia else { return .noMedia }
        if isManuallyPaused { return .pausedByUser }
        if isSystemInactive { return .pausedForSystem }
        if isFullScreenVisible { return .pausedForFullScreen }
        return .playing
    }

    public var shouldPlay: Bool {
        effectiveState == .playing
    }

    public var shouldPlayIgnoringFullScreen: Bool {
        hasMedia && !isManuallyPaused && !isSystemInactive
    }

    public func shouldPlay(onFullScreenDisplay: Bool) -> Bool {
        shouldPlayIgnoringFullScreen && !onFullScreenDisplay
    }
}
