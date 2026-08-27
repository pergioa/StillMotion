import AppKit
import CoreGraphics
#if SWIFT_PACKAGE
import StillMotionCore
#endif

@MainActor
final class FullScreenDetector {
    var onChange: ((Bool) -> Void)?

    private var workspaceObservers: [NSObjectProtocol] = []
    private var applicationObserver: NSObjectProtocol?
    private var timer: Timer?
    private var delayedEvaluation: DispatchWorkItem?
    private var lastResult: Bool?

    func start() {
        guard timer == nil else { return }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceObservers.append(
                workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.scheduleEvaluation()
                    }
                }
            )
        }

        applicationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleEvaluation()
            }
        }

        let pollingTimer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluateNow()
            }
        }
        RunLoop.main.add(pollingTimer, forMode: .common)
        timer = pollingTimer
        evaluateNow()
    }

    func evaluateNow() {
        delayedEvaluation?.cancel()
        delayedEvaluation = nil

        let isFullScreen = FullScreenWindowClassifier.containsFullScreenWindow(
            windows: currentWindows(),
            screenBounds: currentScreenBounds(),
            ownPID: ProcessInfo.processInfo.processIdentifier
        )
        guard isFullScreen != lastResult else { return }
        lastResult = isFullScreen
        onChange?(isFullScreen)
    }

    private func scheduleEvaluation() {
        evaluateNow()
        delayedEvaluation?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.evaluateNow()
        }
        delayedEvaluation = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func currentScreenBounds() -> [CGRect] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        }
    }

    private func currentWindows() -> [ObservedWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return rawWindows.compactMap { dictionary in
            guard
                let ownerName = dictionary[kCGWindowOwnerName as String] as? String,
                let ownerPID = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
                let layer = dictionary[kCGWindowLayer as String] as? NSNumber,
                let boundsDictionary = dictionary[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else {
                return nil
            }

            let isOnScreen = (dictionary[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true
            let alpha = (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return ObservedWindow(
                ownerName: ownerName,
                ownerPID: pid_t(ownerPID.int32Value),
                layer: layer.intValue,
                bounds: bounds,
                isOnScreen: isOnScreen,
                alpha: alpha
            )
        }
    }

    deinit {
        timer?.invalidate()
        delayedEvaluation?.cancel()
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        if let applicationObserver {
            NotificationCenter.default.removeObserver(applicationObserver)
        }
    }
}
