// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sergio Abreo Alvarez

import AppKit

@MainActor
final class SystemActivityObserver {
    var onChange: ((Bool) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var isSleeping = false
    private var areScreensSleeping = false
    private var isSessionActive = true
    private var lastResult: Bool?

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter

        observe(NSWorkspace.willSleepNotification) { observer in observer.isSleeping = true }
        observe(NSWorkspace.didWakeNotification) { observer in observer.isSleeping = false }
        observe(NSWorkspace.screensDidSleepNotification) { observer in observer.areScreensSleeping = true }
        observe(NSWorkspace.screensDidWakeNotification) { observer in observer.areScreensSleeping = false }
        observe(NSWorkspace.sessionDidResignActiveNotification) { observer in observer.isSessionActive = false }
        observe(NSWorkspace.sessionDidBecomeActiveNotification) { observer in observer.isSessionActive = true }

        reportIfChanged()

        func observe(_ name: Notification.Name, change: @escaping (SystemActivityObserver) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    change(self)
                    self.reportIfChanged()
                }
            })
        }
    }

    private func reportIfChanged() {
        let isInactive = isSleeping || areScreensSleeping || !isSessionActive
        guard isInactive != lastResult else { return }
        lastResult = isInactive
        onChange?(isInactive)
    }

    deinit {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }
}
