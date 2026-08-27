import AppKit
import AVFoundation

final class WallpaperWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static func wallpaperLevel(desktopLevel: Int) -> Int {
        desktopLevel + 1
    }

    init(screen: NSScreen, contentView: VideoWallpaperView) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        level = NSWindow.Level(rawValue: Self.wallpaperLevel(desktopLevel: desktopLevel))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        titleVisibility = .hidden
        self.contentView = contentView
        setFrame(screen.frame, display: true)
    }
}

final class VideoWallpaperView: NSView {
    private let placeholderLayer = CALayer()
    private var playerLayer = AVPlayerLayer()
    private var playerReadyObservation: NSKeyValueObservation?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        placeholderLayer.backgroundColor = NSColor.black.cgColor
        placeholderLayer.contentsGravity = .resizeAspectFill
        configurePlayerLayer(playerLayer)
        layer?.addSublayer(placeholderLayer)
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPlaceholder(imageURL: URL?) {
        guard let imageURL, let image = NSImage(contentsOf: imageURL) else {
            placeholderLayer.contents = nil
            return
        }
        var imageRect = NSRect(origin: .zero, size: image.size)
        placeholderLayer.contents = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
    }

    func install(player: AVPlayer?) {
        playerReadyObservation?.invalidate()
        playerReadyObservation = nil

        playerLayer.removeFromSuperlayer()

        let replacementLayer = AVPlayerLayer(player: player)
        configurePlayerLayer(replacementLayer)
        replacementLayer.frame = bounds
        replacementLayer.isHidden = true
        layer?.addSublayer(replacementLayer)
        playerLayer.removeFromSuperlayer()
        playerLayer = replacementLayer

        guard player != nil else { return }
        playerReadyObservation = replacementLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                guard let self, self.playerLayer === layer else { return }
                layer.isHidden = false
                self.playerReadyObservation?.invalidate()
                self.playerReadyObservation = nil
            }
        }
    }

    private func configurePlayerLayer(_ layer: AVPlayerLayer) {
        layer.backgroundColor = NSColor.clear.cgColor
        layer.videoGravity = .resizeAspectFill
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placeholderLayer.frame = bounds
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
