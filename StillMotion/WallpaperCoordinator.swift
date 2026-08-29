import AppKit
import AVFoundation

func systemWallpaperFrameName(for videoURL: URL) -> String {
    videoURL.lastPathComponent + ".jpg"
}

@MainActor
final class WallpaperCoordinator {
    var onDisplaysChanged: (([DisplayDescriptor]) -> Void)?
    var onPreviewFramesChanged: (([String: URL]) -> Void)?

    private let systemWallpaperFrames = SystemWallpaperFrameStore()
    private var sessions: [String: DisplayPlaybackSession] = [:]
    private var frameURLsByDisplayID: [String: URL] = [:]
    private var systemWallpaperTasks: [String: Task<Void, Never>] = [:]
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var mediaURLsByDisplayID: [String: URL] = [:]
    private var globallyAllowsPlayback = false
    private var fullScreenDisplayIDs: Set<String> = []

    func start() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshScreens()
            }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshScreens()
            }
        }
        refreshScreens()
    }

    func setMediaURLs(_ mediaURLs: [String: URL]) async {
        systemWallpaperTasks.values.forEach { $0.cancel() }
        systemWallpaperTasks.removeAll()
        let previousMediaURLs = mediaURLsByDisplayID
        mediaURLsByDisplayID = mediaURLs

        let changedDisplayIDs = Set(previousMediaURLs.keys).union(mediaURLs.keys).filter {
            previousMediaURLs[$0] != mediaURLs[$0]
        }
        for displayID in changedDisplayIDs {
            setPreviewFrameURL(nil, for: displayID)
        }
        refreshScreens(synchronizeSystemWallpaper: false)

        for (displayID, mediaURL) in mediaURLs {
            do {
                let frameURL = try await systemWallpaperFrames.frameURL(for: mediaURL)
                guard mediaURLsByDisplayID[displayID] == mediaURL else { continue }
                setPreviewFrameURL(frameURL, for: displayID)
                if let screen = NSScreen.screens.first(where: { $0.persistentDisplayID == displayID }) {
                    try applySystemWallpaper(frameURL, to: screen)
                }
            } catch {
                NSLog("Unable to prepare the system wallpaper for display %@: %@", displayID, error.localizedDescription)
            }
        }
        refreshScreens(synchronizeSystemWallpaper: false)
    }

    func setMedia(url: URL, for displayID: String) async {
        systemWallpaperTasks.removeValue(forKey: displayID)?.cancel()
        mediaURLsByDisplayID[displayID] = url
        setPreviewFrameURL(nil, for: displayID)
        refreshScreens(synchronizeSystemWallpaper: false)

        do {
            let frameURL = try await systemWallpaperFrames.frameURL(for: url)
            guard mediaURLsByDisplayID[displayID] == url else { return }
            setPreviewFrameURL(frameURL, for: displayID)
            if let screen = NSScreen.screens.first(where: { $0.persistentDisplayID == displayID }) {
                try applySystemWallpaper(frameURL, to: screen)
            }
        } catch {
            NSLog("Unable to prepare the system wallpaper for display %@: %@", displayID, error.localizedDescription)
        }

        guard mediaURLsByDisplayID[displayID] == url else { return }
        refreshScreens(synchronizeSystemWallpaper: false)
    }

    func removeMedia(for displayID: String) {
        mediaURLsByDisplayID.removeValue(forKey: displayID)
        setPreviewFrameURL(nil, for: displayID)
        systemWallpaperTasks.removeValue(forKey: displayID)?.cancel()
        sessions.removeValue(forKey: displayID)?.close()
    }

    func setPlayback(globallyAllowed: Bool, fullScreenDisplayIDs: Set<String>) {
        guard
            globallyAllowsPlayback != globallyAllowed ||
            self.fullScreenDisplayIDs != fullScreenDisplayIDs
        else {
            return
        }
        globallyAllowsPlayback = globallyAllowed
        self.fullScreenDisplayIDs = fullScreenDisplayIDs
        for (displayID, session) in sessions {
            session.setPlaying(shouldPlay(on: displayID))
        }
    }

    private func refreshScreens(synchronizeSystemWallpaper: Bool = true) {
        let screensByID = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            screen.persistentDisplayID.map { ($0, screen) }
        })
        let desiredIDs = Set(screensByID.keys).intersection(mediaURLsByDisplayID.keys)
        let removedIDs = Set(sessions.keys).subtracting(desiredIDs)
        removedIDs.forEach { id in
            sessions.removeValue(forKey: id)?.close()
        }

        for displayID in desiredIDs {
            guard let screen = screensByID[displayID], let mediaURL = mediaURLsByDisplayID[displayID] else {
                continue
            }
            if let session = sessions[displayID] {
                session.update(screen: screen)
                if session.mediaURL != mediaURL {
                    let previousPlayer = session.player
                    session.load(
                        url: mediaURL,
                        placeholderURL: frameURLsByDisplayID[displayID],
                        shouldPlay: shouldPlay(on: displayID),
                        previousPlayer: previousPlayer
                    )
                }
            } else {
                let session = DisplayPlaybackSession(screen: screen)
                sessions[displayID] = session
                session.load(
                    url: mediaURL,
                    placeholderURL: frameURLsByDisplayID[displayID],
                    shouldPlay: shouldPlay(on: displayID),
                    previousPlayer: nil
                )
            }
        }
        if synchronizeSystemWallpaper {
            synchronizeSystemWallpapers(screensByID: screensByID)
        }
        onDisplaysChanged?(DisplayDescriptor.currentDisplays())
    }

    private func shouldPlay(on displayID: String) -> Bool {
        globallyAllowsPlayback && !fullScreenDisplayIDs.contains(displayID)
    }

    private func synchronizeSystemWallpapers(screensByID: [String: NSScreen]) {
        let desiredIDs = Set(screensByID.keys).intersection(mediaURLsByDisplayID.keys)
        for displayID in Set(systemWallpaperTasks.keys).subtracting(desiredIDs) {
            systemWallpaperTasks.removeValue(forKey: displayID)?.cancel()
        }

        for displayID in desiredIDs {
            guard let screen = screensByID[displayID], let mediaURL = mediaURLsByDisplayID[displayID] else {
                continue
            }
            synchronizeSystemWallpaper(for: displayID, screen: screen, mediaURL: mediaURL)
        }
    }

    private func synchronizeSystemWallpaper(for displayID: String, screen: NSScreen, mediaURL: URL) {
        systemWallpaperTasks[displayID]?.cancel()
        systemWallpaperTasks[displayID] = Task { [weak self, systemWallpaperFrames] in
            do {
                let frameURL = try await systemWallpaperFrames.frameURL(for: mediaURL)
                try Task.checkCancellation()
                guard let self, self.mediaURLsByDisplayID[displayID] == mediaURL else { return }
                self.setPreviewFrameURL(frameURL, for: displayID)
                try Self.applySystemWallpaper(frameURL, to: screen)
            } catch is CancellationError {
                return
            } catch {
                NSLog("Unable to synchronize the system wallpaper for display %@: %@", displayID, error.localizedDescription)
            }
        }
    }

    private func setPreviewFrameURL(_ frameURL: URL?, for displayID: String) {
        guard frameURLsByDisplayID[displayID] != frameURL else { return }
        frameURLsByDisplayID[displayID] = frameURL
        sessions[displayID]?.setPlaceholder(imageURL: frameURL)
        onPreviewFramesChanged?(frameURLsByDisplayID)
    }

    private static func applySystemWallpaper(_ frameURL: URL, to screen: NSScreen) throws {
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true,
            .fillColor: NSColor.black
        ]
        try NSWorkspace.shared.setDesktopImageURL(frameURL, for: screen, options: options)
    }

    private func applySystemWallpaper(_ frameURL: URL, to screen: NSScreen) throws {
        try Self.applySystemWallpaper(frameURL, to: screen)
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        systemWallpaperTasks.values.forEach { $0.cancel() }
    }
}

private actor SystemWallpaperFrameStore {
    private let fileManager = FileManager.default

    func frameURL(for videoURL: URL) async throws -> URL {
        let directory = try framesDirectory()
        let frameURL = directory.appendingPathComponent(systemWallpaperFrameName(for: videoURL))
        if fileManager.fileExists(atPath: frameURL.path) {
            return frameURL
        }

        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds
        let captureSeconds = durationSeconds.isFinite && durationSeconds > 0
            ? min(1, durationSeconds * 0.1)
            : 0
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let result = try await generator.image(
            at: CMTime(seconds: captureSeconds, preferredTimescale: 600)
        )
        let bitmap = NSBitmapImageRep(cgImage: result.image)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw FrameError.encodingFailed
        }
        try data.write(to: frameURL, options: .atomic)
        return frameURL
    }

    private func framesDirectory() throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL
            .appendingPathComponent("StillMotion", isDirectory: true)
            .appendingPathComponent("System Wallpapers", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private enum FrameError: LocalizedError {
        case encodingFailed

        var errorDescription: String? {
            "The video frame could not be encoded as a desktop image."
        }
    }
}

@MainActor
private final class DisplayPlaybackSession {
    private let videoView: VideoWallpaperView
    private let window: WallpaperWindow
    fileprivate var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var wantsPlayback = false
    private(set) var mediaURL: URL?

    init(screen: NSScreen) {
        videoView = VideoWallpaperView(frame: screen.frame)
        window = WallpaperWindow(screen: screen, contentView: videoView)
        window.orderFrontRegardless()
    }

    func load(url: URL, placeholderURL: URL?, shouldPlay: Bool, previousPlayer: AVPlayer?) {
        mediaURL = url
        wantsPlayback = shouldPlay

        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        queuePlayer.volume = 0
        queuePlayer.actionAtItemEnd = .none
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = false
        let newLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)

        player = queuePlayer
        looper = newLooper

        videoView.install(player: queuePlayer)
        videoView.setPlaceholder(imageURL: placeholderURL)
        previousPlayer?.pause()
        if let old = previousPlayer as? AVQueuePlayer { old.removeAllItems() }

        if shouldPlay {
            queuePlayer.play()
        }
    }

    func setPlaying(_ playing: Bool) {
        wantsPlayback = playing
        if playing {
            player?.play()
        } else {
            player?.pause()
        }
    }

    func setPlaceholder(imageURL: URL?) {
        videoView.setPlaceholder(imageURL: imageURL)
    }

    func update(screen: NSScreen) {
        guard window.frame != screen.frame else { return }
        window.setFrame(screen.frame, display: true)
    }

    func close() {
        wantsPlayback = false
        player?.pause()
        videoView.install(player: nil)
        looper = nil
        player?.removeAllItems()
        player = nil
        mediaURL = nil
        window.orderOut(nil)
        window.close()
    }
}
