import AppKit
import AVFoundation

@MainActor
final class WallpaperCoordinator {
    var onDisplaysChanged: (([DisplayDescriptor]) -> Void)?

    private let systemWallpaperFrames = SystemWallpaperFrameStore()
    private var sessions: [String: DisplayPlaybackSession] = [:]
    private var frameURLsByDisplayID: [String: URL] = [:]
    private var systemWallpaperTasks: [String: Task<Void, Never>] = [:]
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var mediaURLsByDisplayID: [String: URL] = [:]
    private var shouldPlay = false

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
        var preparedFrameURLs: [String: URL] = [:]
        for (displayID, mediaURL) in mediaURLs {
            do {
                let frameURL = try await systemWallpaperFrames.frameURL(for: mediaURL)
                preparedFrameURLs[displayID] = frameURL
                if let screen = NSScreen.screens.first(where: { $0.persistentDisplayID == displayID }) {
                    try applySystemWallpaper(frameURL, to: screen)
                }
            } catch {
                NSLog("Unable to prepare the system wallpaper for display %@: %@", displayID, error.localizedDescription)
            }
        }
        frameURLsByDisplayID = preparedFrameURLs
        mediaURLsByDisplayID = mediaURLs
        for (displayID, session) in sessions {
            guard let url = mediaURLs[displayID] else {
                sessions.removeValue(forKey: displayID)?.close()
                continue
            }
            if session.mediaURL != url {
                let previousPlayer = session.player
                session.load(
                    url: url,
                    placeholderURL: frameURLsByDisplayID[displayID],
                    initialTime: .zero,
                    shouldPlay: shouldPlay,
                    previousPlayer: previousPlayer
                )
            }
        }
        refreshScreens(synchronizeSystemWallpaper: false)
    }

    func setMedia(url: URL, for displayID: String) async {
        systemWallpaperTasks.removeValue(forKey: displayID)?.cancel()
        var preparedFrameURL: URL?
        if let screen = NSScreen.screens.first(where: { $0.persistentDisplayID == displayID }) {
            do {
                 let frameURL = try await systemWallpaperFrames.frameURL(for: url)
                preparedFrameURL = frameURL
                try applySystemWallpaper(frameURL, to: screen)
            } catch {
                NSLog("Unable to prepare the system wallpaper for display %@: %@", displayID, error.localizedDescription)
            }
        }

        frameURLsByDisplayID[displayID] = preparedFrameURL
        mediaURLsByDisplayID[displayID] = url
        refreshScreens(synchronizeSystemWallpaper: false)
    }

    func removeMedia(for displayID: String) {
        mediaURLsByDisplayID.removeValue(forKey: displayID)
        frameURLsByDisplayID.removeValue(forKey: displayID)
        systemWallpaperTasks.removeValue(forKey: displayID)?.cancel()
        sessions.removeValue(forKey: displayID)?.close()
    }

    func setPlaying(_ playing: Bool) {
        shouldPlay = playing
        sessions.values.forEach { $0.setPlaying(playing) }
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
                        initialTime: .zero,
                        shouldPlay: shouldPlay,
                        previousPlayer: previousPlayer
                    )
                }
            } else {
                let session = DisplayPlaybackSession(screen: screen)
                sessions[displayID] = session
                session.load(
                    url: mediaURL,
                    placeholderURL: frameURLsByDisplayID[displayID],
                    initialTime: .zero,
                    shouldPlay: shouldPlay,
                    previousPlayer: nil
                )
            }
        }
        if synchronizeSystemWallpaper {
            synchronizeSystemWallpapers(screensByID: screensByID)
        }
        onDisplaysChanged?(DisplayDescriptor.currentDisplays())
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
            systemWallpaperTasks[displayID]?.cancel()
            systemWallpaperTasks[displayID] = Task { [systemWallpaperFrames] in
                do {
                    let frameURL = try await systemWallpaperFrames.frameURL(for: mediaURL)
                    try Task.checkCancellation()
                    try Self.applySystemWallpaper(frameURL, to: screen)
                } catch is CancellationError {
                    return
                } catch {
                    NSLog("Unable to synchronize the system wallpaper for display %@: %@", displayID, error.localizedDescription)
                }
            }
        }
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
        let frameURL = directory
            .appendingPathComponent(videoURL.lastPathComponent)
            .appendingPathExtension("jpg")
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
    private var loadGeneration = 0
    private(set) var mediaURL: URL?

    init(screen: NSScreen) {
        videoView = VideoWallpaperView(frame: screen.frame)
        window = WallpaperWindow(screen: screen, contentView: videoView)
        window.orderFrontRegardless()
    }

    var currentTime: CMTime {
        guard let time = player?.currentTime(), time.isNumeric else { return .zero }
        return time
    }

    func load(url: URL, placeholderURL: URL?, initialTime: CMTime, shouldPlay: Bool, previousPlayer: AVPlayer?) {
        loadGeneration += 1
        let generation = loadGeneration
        mediaURL = url
        wantsPlayback = shouldPlay
        videoView.setPlaceholder(imageURL: placeholderURL)

        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        queuePlayer.volume = 0
        queuePlayer.actionAtItemEnd = .none
        let newLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)

        player = queuePlayer
        looper = newLooper

        var firstFrameReady = false
        let firstFrameReadySemaphore = DispatchSemaphore(value: 0)
        videoView.install(player: queuePlayer)

        queuePlayer.seek(to: initialTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self, finished else { return }
            DispatchQueue.main.async {
                guard
                    self.loadGeneration == generation,
                    self.player === queuePlayer
                else {
                    return
                }
                queuePlayer.preroll(atRate: 1) { [weak self] ready in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        guard self.loadGeneration == generation, self.player === queuePlayer else {
                            return
                        }
                        firstFrameReady = true
                        firstFrameReadySemaphore.signal()
                    }
                }
            }
        }

        let deadline = DispatchTime.now() + .seconds(5)
        let _ = firstFrameReadySemaphore.wait(timeout: deadline)

        if !firstFrameReady {
            NSLog("Video wallpaper at %@ failed to preroll", url.path)
        }

        previousPlayer?.pause()
        if let old = previousPlayer as? AVQueuePlayer { old.removeAllItems() }

        queuePlayer.seek(to: initialTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            DispatchQueue.main.async {
                guard
                    let self,
                    finished,
                    self.loadGeneration == generation,
                    self.player === queuePlayer,
                    self.wantsPlayback
                else {
                    return
                }
                queuePlayer.play()
            }
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

    func update(screen: NSScreen) {
        window.setFrame(screen.frame, display: true)
    }

    func close() {
        loadGeneration += 1
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
