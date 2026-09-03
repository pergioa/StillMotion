// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sergio Abreo Alvarez

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import StillMotionCore
#endif

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var policy: PlaybackPolicy
    @Published private(set) var availableDisplays: [DisplayDescriptor] = []
    @Published private(set) var selectedVideoURLs: [String: URL] = [:]
    @Published private(set) var originalVideoFilenames: [String: String] = [:]
    @Published private(set) var previewFrameURLs: [String: URL] = [:]
    @Published private(set) var fullScreenDisplayIDs: Set<String> = []
    @Published private(set) var isRestoringVideos = true
    @Published private(set) var busyDisplayIDs: Set<String> = []

    private let mediaService: MediaImportService
    private let wallpaperCoordinator: WallpaperCoordinator
    private let fullScreenDetector: FullScreenDetector
    private let systemActivityObserver: SystemActivityObserver
    private let defaults: UserDefaults
    private var started = false
    private var restorationStarted = false

    private enum DefaultsKey {
        static let manuallyPaused = "manuallyPaused"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mediaService = MediaImportService(defaults: defaults)
        wallpaperCoordinator = WallpaperCoordinator()
        fullScreenDetector = FullScreenDetector()
        systemActivityObserver = SystemActivityObserver()

        var initialPolicy = PlaybackPolicy()
        initialPolicy.isManuallyPaused = defaults.bool(forKey: DefaultsKey.manuallyPaused)
        policy = initialPolicy

        fullScreenDetector.onChange = { [weak self] displayIDs in
            self?.setFullScreenDisplays(displayIDs)
        }
        systemActivityObserver.onChange = { [weak self] isInactive in
            self?.setSystemInactive(isInactive)
        }
        wallpaperCoordinator.onDisplaysChanged = { [weak self] displays in
            self?.updateDisplays(displays)
        }
        wallpaperCoordinator.onPreviewFramesChanged = { [weak self] frameURLs in
            self?.previewFrameURLs = frameURLs
        }

        Task { @MainActor [weak self] in
            self?.start()
        }
    }

    var hasMedia: Bool {
        availableDisplays.contains { selectedVideoURLs[$0.id] != nil }
    }

    var statusText: String {
        switch policy.effectiveState {
        case .noMedia:
            return "No Background Selected"
        case .playing:
            return "Playing"
        case .pausedByUser, .pausedForSystem:
            return "Paused"
        case .pausedForFullScreen:
            return hasPlayingMedia ? "Partially Paused" : "Paused — Full-Screen App"
        }
    }

    var hasPlayingMedia: Bool {
        policy.shouldPlayIgnoringFullScreen && availableDisplays.contains { display in
            selectedVideoURLs[display.id] != nil && !fullScreenDisplayIDs.contains(display.id)
        }
    }

    var menuBarSymbolName: String {
        Self.menuBarSymbolName(for: policy)
    }

    static func menuBarSymbolName(for policy: PlaybackPolicy) -> String {
        policy.hasMedia && !policy.shouldPlay
            ? "rectangle.stack.fill.badge.minus"
            : "rectangle.stack.fill"
    }

    func videoFilename(for displayID: String) -> String? {
        originalVideoFilenames[displayID] ?? selectedVideoURLs[displayID]?.lastPathComponent
    }

    func previewFrameURL(for displayID: String) -> URL? {
        previewFrameURLs[displayID]
    }

    func isUpdatingBackground(for displayID: String) -> Bool {
        busyDisplayIDs.contains(displayID)
    }

    func isBackgroundActionDisabled(for _: String) -> Bool {
        isRestoringVideos || !busyDisplayIDs.isEmpty
    }

    func chooseVideo(for displayID: String) {
        guard !isBackgroundActionDisabled(for: displayID) else { return }
        guard let display = availableDisplays.first(where: { $0.id == displayID }) else { return }
        busyDisplayIDs.insert(displayID)
        let panel = NSOpenPanel()
        panel.title = "Choose a Background for \(display.name)"
        panel.prompt = "Choose Background"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["mp4", "mov", "m4v"].compactMap { UTType(filenameExtension: $0) }

        NSApplication.shared.activate()
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                guard response == .OK, let url = panel.url else {
                    self.busyDisplayIDs.remove(displayID)
                    return
                }
                await self.importVideo(from: url, for: displayID)
            }
        }
    }

    func toggleManualPlayback() {
        guard policy.hasMedia else { return }
        policy.isManuallyPaused.toggle()
        defaults.set(policy.isManuallyPaused, forKey: DefaultsKey.manuallyPaused)
        updateFullScreenDetection()
        applyPlaybackPolicy()
    }

    func revealVideo(for displayID: String) {
        guard let url = selectedVideoURLs[displayID] else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func removeVideo(for displayID: String) {
        guard !isBackgroundActionDisabled(for: displayID) else { return }
        busyDisplayIDs.insert(displayID)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { busyDisplayIDs.remove(displayID) }
            do {
                try await mediaService.removeVideo(for: displayID)
                selectedVideoURLs.removeValue(forKey: displayID)
                originalVideoFilenames.removeValue(forKey: displayID)
                wallpaperCoordinator.removeMedia(for: displayID)
                try? await evictStaleWallpaperFrames()
                updateMediaPolicy()
            } catch {
                present(error: error, title: "Unable to Remove Video")
            }
        }
    }

    private func start() {
        guard !started else { return }
        started = true

        wallpaperCoordinator.start()
        fullScreenDetector.start()
        systemActivityObserver.start()

        beginRestoringVideosIfPossible()
    }

    private func restoreVideos() async {
        defer { isRestoringVideos = false }
        do {
            let mainDisplayID = availableDisplays.first(where: \.isMain)?.id ?? availableDisplays.first?.id
            let result = try await mediaService.restoredVideoURLs(defaultDisplayID: mainDisplayID)
            selectedVideoURLs = result.videosByDisplayID
            originalVideoFilenames = result.originalFilenamesByDisplayID
            await wallpaperCoordinator.setMediaURLs(result.videosByDisplayID)
            updateMediaPolicy()

            let activeFrameNames = Set(result.videosByDisplayID.values.map(systemWallpaperFrameName))
            try? await mediaService.evictStaleWallpaperFrames(activeFrameNames: activeFrameNames)

            if !result.failures.isEmpty {
                let details = result.failures.map { failure in
                    let displayName = availableDisplays.first(where: { $0.id == failure.displayID })?.name
                        ?? "Disconnected Display"
                    return "\(displayName): \(failure.message)"
                }.joined(separator: "\n")
                present(message: details, title: "Some Videos Could Not Be Restored")
            }
        } catch {
            present(error: error, title: "Unable to Restore Videos")
        }
    }

    private func importVideo(from url: URL, for displayID: String) async {
        defer { busyDisplayIDs.remove(displayID) }
        do {
            let importedVideo = try await mediaService.importVideo(from: url, for: displayID)
            await installVideo(importedVideo, for: displayID)
        } catch {
            present(error: error, title: "Unable to Use Video")
        }
    }

    private func installVideo(_ importedVideo: MediaImportService.ImportedVideo, for displayID: String) async {
        selectedVideoURLs[displayID] = importedVideo.url
        originalVideoFilenames[displayID] = importedVideo.originalFilename
        await wallpaperCoordinator.setMedia(url: importedVideo.url, for: displayID)
        if let replacedManagedFilename = importedVideo.replacedManagedFilename {
            try? await mediaService.removeManagedVideoIfUnassigned(replacedManagedFilename)
        }
        try? await evictStaleWallpaperFrames()
        updateMediaPolicy()
    }

    private func updateDisplays(_ displays: [DisplayDescriptor]) {
        guard displays != availableDisplays else { return }
        availableDisplays = displays
        beginRestoringVideosIfPossible()
        updateMediaPolicy()
    }

    private func beginRestoringVideosIfPossible() {
        guard started, !restorationStarted, !availableDisplays.isEmpty else { return }
        restorationStarted = true
        Task { @MainActor [weak self] in
            await self?.restoreVideos()
        }
    }

    private func updateMediaPolicy() {
        policy.hasMedia = hasMedia
        policy.isFullScreenVisible = !affectedFullScreenDisplayIDs.isEmpty
        updateFullScreenDetection()
        applyPlaybackPolicy()
    }

    private func setFullScreenDisplays(_ displayIDs: Set<String>) {
        guard fullScreenDisplayIDs != displayIDs else { return }
        fullScreenDisplayIDs = displayIDs
        policy.isFullScreenVisible = !affectedFullScreenDisplayIDs.isEmpty
        applyPlaybackPolicy()
    }

    private func setSystemInactive(_ isInactive: Bool) {
        guard policy.isSystemInactive != isInactive else { return }
        policy.isSystemInactive = isInactive
        updateFullScreenDetection()
        applyPlaybackPolicy()
    }

    private func updateFullScreenDetection() {
        fullScreenDetector.setEnabled(hasMedia && !policy.isSystemInactive && !policy.isManuallyPaused)
    }

    private func applyPlaybackPolicy() {
        wallpaperCoordinator.setPlayback(
            globallyAllowed: policy.shouldPlayIgnoringFullScreen,
            fullScreenDisplayIDs: fullScreenDisplayIDs
        )
    }

    private var affectedFullScreenDisplayIDs: Set<String> {
        let displaysWithMedia = Set(availableDisplays.compactMap { display in
            selectedVideoURLs[display.id] == nil ? nil : display.id
        })
        return fullScreenDisplayIDs.intersection(displaysWithMedia)
    }

    private func evictStaleWallpaperFrames() async throws {
        let activeFrameNames = Set(selectedVideoURLs.values.map(systemWallpaperFrameName))
        try await mediaService.evictStaleWallpaperFrames(activeFrameNames: activeFrameNames)
    }

    private func present(error: Error, title: String) {
        NSApplication.shared.activate()
        let alert = NSAlert(error: error)
        alert.alertStyle = .warning
        alert.messageText = title
        alert.runModal()
    }

    private func present(message: String, title: String) {
        NSApplication.shared.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
