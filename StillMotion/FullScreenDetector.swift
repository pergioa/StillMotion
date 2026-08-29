import AppKit
import CoreGraphics
#if SWIFT_PACKAGE
import StillMotionCore
#endif

@MainActor
final class FullScreenDetector {
    var onChange: ((Set<String>) -> Void)?

    private struct ScreenSnapshot {
        let id: String
        let bounds: CGRect
    }

    private var workspaceObservers: [NSObjectProtocol] = []
    private var applicationObserver: NSObjectProtocol?
    private var timer: Timer?
    private var delayedEvaluation: DispatchWorkItem?
    private var lastResult: Set<String>?
    private var screens: [ScreenSnapshot]?
    private var started = false
    private var isEnabled = false

    func start() {
        guard !started else { return }
        started = true

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
                self?.screens = nil
                self?.scheduleEvaluation()
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        delayedEvaluation?.cancel()
        delayedEvaluation = nil

        if enabled {
            let pollingTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.evaluateNow()
                }
            }
            pollingTimer.tolerance = 0.2
            RunLoop.main.add(pollingTimer, forMode: .common)
            timer = pollingTimer
            evaluateNow()
        } else {
            timer?.invalidate()
            timer = nil
            guard lastResult != [] else { return }
            lastResult = []
            onChange?([])
        }
    }

    func evaluateNow() {
        guard isEnabled else { return }
        delayedEvaluation?.cancel()
        delayedEvaluation = nil

        let screens = currentScreens()
        let fullScreenIndexes = FullScreenWindowClassifier.fullScreenScreenIndexes(
            windows: currentWindows(),
            screenBounds: screens.map(\.bounds),
            ownPID: ProcessInfo.processInfo.processIdentifier
        )
        let fullScreenDisplayIDs = Set(fullScreenIndexes.map { screens[$0].id })
        guard fullScreenDisplayIDs != lastResult else { return }
        lastResult = fullScreenDisplayIDs
        onChange?(fullScreenDisplayIDs)
    }

    private func scheduleEvaluation() {
        guard isEnabled else { return }
        evaluateNow()
        delayedEvaluation?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.evaluateNow()
        }
        delayedEvaluation = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func currentScreens() -> [ScreenSnapshot] {
        if let screens {
            return screens
        }
        let snapshots = NSScreen.screens.compactMap { screen -> ScreenSnapshot? in
            guard let displayID = screen.displayID, let persistentDisplayID = screen.persistentDisplayID else {
                return nil
            }
            return ScreenSnapshot(id: persistentDisplayID, bounds: CGDisplayBounds(displayID))
        }
        screens = snapshots
        return snapshots
    }

    private func currentWindows() -> [ObservedWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier

        return rawWindows.compactMap { dictionary in
            guard
                let ownerPID = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
                pid_t(ownerPID.int32Value) != ownPID,
                let layer = dictionary[kCGWindowLayer as String] as? NSNumber,
                layer.intValue == 0
            else {
                return nil
            }

            let isOnScreen = (dictionary[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true
            let alpha = (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard
                isOnScreen,
                alpha > 0.01,
                let ownerName = dictionary[kCGWindowOwnerName as String] as? String,
                let boundsDictionary = dictionary[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else {
                return nil
            }

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
