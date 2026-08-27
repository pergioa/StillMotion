import CoreGraphics
import Foundation

public struct ObservedWindow: Equatable {
    public let ownerName: String
    public let ownerPID: pid_t
    public let layer: Int
    public let bounds: CGRect
    public let isOnScreen: Bool
    public let alpha: Double

    public init(ownerName: String, ownerPID: pid_t, layer: Int, bounds: CGRect, isOnScreen: Bool, alpha: Double) {
        self.ownerName = ownerName
        self.ownerPID = ownerPID
        self.layer = layer
        self.bounds = bounds
        self.isOnScreen = isOnScreen
        self.alpha = alpha
    }
}

public enum FullScreenWindowClassifier {
    public static let defaultTolerance: CGFloat = 3
    public static let excludedOwnerNames: Set<String> = [
        "control center",
        "dock",
        "finder",
        "loginwindow",
        "notification center",
        "spotlight",
        "systemuiserver",
        "window server"
    ]

    public static func containsFullScreenWindow(
        windows: [ObservedWindow],
        screenBounds: [CGRect],
        ownPID: pid_t,
        ownOwnerName: String = "StillMotion",
        tolerance: CGFloat = defaultTolerance
    ) -> Bool {
        windows.contains { window in
            isFullScreenWindow(
                window,
                screenBounds: screenBounds,
                ownPID: ownPID,
                ownOwnerName: ownOwnerName,
                tolerance: tolerance
            )
        }
    }

    public static func isFullScreenWindow(
        _ window: ObservedWindow,
        screenBounds: [CGRect],
        ownPID: pid_t,
        ownOwnerName: String = "StillMotion",
        tolerance: CGFloat = defaultTolerance
    ) -> Bool {
        guard window.isOnScreen, window.layer == 0, window.alpha > 0.01 else { return false }
        guard window.ownerPID != ownPID else { return false }

        let normalizedOwner = window.ownerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedOwner.isEmpty else { return false }
        guard normalizedOwner != ownOwnerName.lowercased() else { return false }
        guard !excludedOwnerNames.contains(normalizedOwner) else { return false }

        return screenBounds.contains { screen in
            approximatelyEqual(window.bounds, screen, tolerance: tolerance)
        }
    }

    public static func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance &&
            abs(lhs.minY - rhs.minY) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }
}
