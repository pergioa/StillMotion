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

    private let mediaService: MediaImportService
    private let wallpaperCoordinator: WallpaperCoordinator
    private let fullScreenDetector: FullScreenDetector
    private let systemActivityObserver: SystemActivityObserver
    private let defaults: UserDefaults
    private var started = false

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

        fullScreenDetector.onChange = { [weak self] isFullScreenVisible in
            self?.setFullScreenVisible(isFullScreenVisible)
        }
        systemActivityObserver.onChange = { [weak self] isInactive in
            self?.setSystemInactive(isInactive)
        }
        wallpaperCoordinator.onDisplaysChanged = { [weak self] displays in
            self?.updateDisplays(displays)
        }

        Task { @MainActor [weak self] in
            self?.start()
        }
    }

    var hasMedia: Bool {
        !selectedVideoURLs.isEmpty
    }

    var displaysWithMedia: [DisplayDescriptor] {
        availableDisplays.filter { selectedVideoURLs[$0.id] != nil }
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
            return "Paused — Full-Screen App"
        }
    }

    var playPauseTitle: String {
        policy.isManuallyPaused ? "Play" : "Pause"
    }

    var menuBarSymbolName: String {
        policy.shouldPlay ? "play.rectangle.fill" : "pause.rectangle.fill"
    }

    func videoFilename(for displayID: String) -> String? {
        selectedVideoURLs[displayID]?.lastPathComponent
    }

    func chooseVideo(for displayID: String) {
        guard let display = availableDisplays.first(where: { $0.id == displayID }) else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a Video for \(display.name)"
        panel.prompt = "Choose Video"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["mp4", "mov", "m4v"].compactMap { UTType(filenameExtension: $0) }

        NSApplication.shared.activate()
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.importVideo(from: url, for: displayID)
            }
        }
    }

    func toggleManualPlayback() {
        guard policy.hasMedia else { return }
        policy.isManuallyPaused.toggle()
        defaults.set(policy.isManuallyPaused, forKey: DefaultsKey.manuallyPaused)
        applyPlaybackPolicy()
    }

    func revealVideo(for displayID: String) {
        guard let url = selectedVideoURLs[displayID] else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func removeVideo(for displayID: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await mediaService.removeVideo(for: displayID)
                selectedVideoURLs.removeValue(forKey: displayID)
                wallpaperCoordinator.removeMedia(for: displayID)
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

        Task { @MainActor [weak self] in
            await self?.restoreVideos()
        }
    }

    private func restoreVideos() async {
        do {
            let mainDisplayID = availableDisplays.first(where: \.isMain)?.id ?? availableDisplays.first?.id
            let result = try await mediaService.restoredVideoURLs(defaultDisplayID: mainDisplayID)
            selectedVideoURLs = result.videosByDisplayID
            await wallpaperCoordinator.setMediaURLs(result.videosByDisplayID)
            updateMediaPolicy()

            let activeBasenames = Set(result.videosByDisplayID.values.map { url in
                String(url.lastPathComponent.dropLast(4))
            })
            try? await mediaService.evictStaleWallpaperFrames(activeFrameNames: activeBasenames)

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
        do {
            let importedURL = try await mediaService.importVideo(from: url, for: displayID)
            await installVideo(at: importedURL, for: displayID)
        } catch {
            present(error: error, title: "Unable to Use Video")
        }
    }

    private func installVideo(at url: URL, for displayID: String) async {
        await wallpaperCoordinator.setMedia(url: url, for: displayID)
        selectedVideoURLs[displayID] = url
        updateMediaPolicy()
    }

    private func updateDisplays(_ displays: [DisplayDescriptor]) {
        guard displays != availableDisplays else { return }
        availableDisplays = displays
    }

    private func updateMediaPolicy() {
        policy.hasMedia = hasMedia
        applyPlaybackPolicy()
    }

    private func setFullScreenVisible(_ isVisible: Bool) {
        guard policy.isFullScreenVisible != isVisible else { return }
        policy.isFullScreenVisible = isVisible
        applyPlaybackPolicy()
    }

    private func setSystemInactive(_ isInactive: Bool) {
        guard policy.isSystemInactive != isInactive else { return }
        if !isInactive {
            fullScreenDetector.evaluateNow()
        }
        policy.isSystemInactive = isInactive
        applyPlaybackPolicy()
    }

    private func applyPlaybackPolicy() {
        wallpaperCoordinator.setPlaying(policy.shouldPlay)
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
