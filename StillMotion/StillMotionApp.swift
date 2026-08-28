import AppKit
import Combine
import ImageIO
import SwiftUI

@main
struct StillMotionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

private struct StillMotionMenu: View {
    @ObservedObject var model: AppModel
    @State private var selectedDisplayID: String?

    private var selectedDisplay: DisplayDescriptor? {
        model.availableDisplays.first(where: { $0.id == selectedDisplayID })
            ?? model.availableDisplays.first(where: \.isMain)
            ?? model.availableDisplays.first
    }

    private var selectedVideoFilename: String? {
        guard let selectedDisplay else { return nil }
        return model.videoFilename(for: selectedDisplay.id)
    }

    private var statusColor: Color {
        switch model.policy.effectiveState {
        case .playing:
            return .green
        case .pausedForFullScreen:
            return .orange
        case .pausedByUser, .pausedForSystem:
            return .secondary
        case .noMedia:
            return .secondary
        }
    }

    private var statusDetail: String {
        switch model.policy.effectiveState {
        case .playing:
            return "Video backgrounds are moving"
        case .pausedByUser:
            return "Paused until you resume"
        case .pausedForFullScreen:
            return model.hasPlayingMedia
                ? "Paused only on displays with full-screen apps"
                : "Will resume after full screen"
        case .pausedForSystem:
            return "Waiting for the system to become active"
        case .noMedia:
            return "Choose a video to get started"
        }
    }

    private var playbackHeading: String {
        switch model.policy.effectiveState {
        case .playing:
            return "Backgrounds Playing"
        case .noMedia:
            return "Ready for a Background"
        case .pausedForFullScreen:
            return model.hasPlayingMedia ? "Full-Screen Pause" : "Backgrounds Paused"
        case .pausedByUser, .pausedForSystem:
            return "Backgrounds Paused"
        }
    }

    private var displayIDs: [String] {
        model.availableDisplays.map(\.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    playbackCard

                    if model.availableDisplays.isEmpty {
                        noDisplaysView
                    } else {
                        displaySelector
                        if let selectedDisplay {
                            backgroundCard(for: selectedDisplay)
                        }
                    }
                }
                .padding(16)
            }

            footer
        }
        .frame(width: 380, height: 560)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.06), .clear],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            }
        }
        .onAppear(perform: synchronizeSelection)
        .onChange(of: displayIDs) {
            synchronizeSelection()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.gradient)
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("StillMotion")
                    .font(.headline)
                Text("Desktop video controller")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusPill(text: model.statusText, color: statusColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var playbackCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(playbackHeading)
                    .font(.system(size: 15, weight: .semibold))
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: model.toggleManualPlayback) {
                ZStack {
                    Circle()
                        .fill(model.hasMedia ? Color.accentColor : Color.secondary.opacity(0.14))
                    Image(systemName: model.policy.isManuallyPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(model.hasMedia ? Color.white : Color.secondary)
                }
                .frame(width: 42, height: 42)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!model.hasMedia)
            .help(model.policy.isManuallyPaused ? "Resume all backgrounds" : "Pause all backgrounds")
            .accessibilityLabel(model.policy.isManuallyPaused ? "Resume all backgrounds" : "Pause all backgrounds")
            .keyboardShortcut("p", modifiers: .command)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.quaternary.opacity(0.55))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
    }

    private var displaySelector: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("DISPLAYS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                Spacer()
                Text("\(model.availableDisplays.count) connected")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.availableDisplays) { display in
                        DisplaySelectorButton(
                            display: display,
                            hasVideo: model.videoFilename(for: display.id) != nil,
                            isSelected: selectedDisplay?.id == display.id
                        ) {
                            selectedDisplayID = display.id
                        }
                    }
                }
            }
        }
    }

    private func backgroundCard(for display: DisplayDescriptor) -> some View {
        let hasVideo = selectedVideoFilename != nil
        let frameURL = model.previewFrameURL(for: display.id)

        return VStack(spacing: 0) {
            BackgroundPreview(
                frameURL: frameURL,
                hasVideo: hasVideo,
                isLoading: model.isRestoringVideos || model.isUpdatingBackground(for: display.id),
                videoDescription: videoDescription(selectedVideoFilename)
            )
            .id("\(display.id)|\(frameURL?.path ?? "")")
            .frame(height: 124)
            .padding(10)

            Divider()

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(displayTitle(display))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if display.isMain {
                            Text("MAIN")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                    }
                    if let selectedVideoFilename {
                        Text(selectedVideoFilename)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(selectedVideoFilename)
                    } else {
                        Text("Ready for a video background")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                Button {
                    model.chooseVideo(for: display.id)
                } label: {
                    if model.isUpdatingBackground(for: display.id) {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(
                            hasVideo ? "Change" : "Choose Video",
                            systemImage: hasVideo ? "arrow.triangle.2.circlepath" : "plus"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(model.isBackgroundActionDisabled(for: display.id))
                .keyboardShortcut("o", modifiers: .command)

                if hasVideo {
                    Menu {
                        Button {
                            model.revealVideo(for: display.id)
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                        }

                        Divider()

                        Button(role: .destructive) {
                            model.removeVideo(for: display.id)
                        } label: {
                            Label("Remove Background", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17))
                            .frame(width: 24, height: 24)
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(model.isBackgroundActionDisabled(for: display.id))
                    .help("More background actions")
                }
            }
            .padding(12)
        }
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.75),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        }
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var noDisplaysView: some View {
        VStack(spacing: 10) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Displays Available")
                .font(.headline)
            Text("StillMotion will update when a display is connected.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: model.toggleManualPlayback) {
                Label(
                    model.policy.isManuallyPaused ? "Resume All" : "Pause All",
                    systemImage: model.policy.isManuallyPaused ? "play.fill" : "pause.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!model.hasMedia)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(12)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func synchronizeSelection() {
        guard !displayIDs.isEmpty else {
            selectedDisplayID = nil
            return
        }
        if let selectedDisplayID, displayIDs.contains(selectedDisplayID) {
            return
        }
        selectedDisplayID = model.availableDisplays.first(where: \.isMain)?.id ?? displayIDs.first
    }

    private func displayTitle(_ display: DisplayDescriptor) -> String {
        display.name.replacingOccurrences(of: " (Main Display)", with: "")
    }

    private func videoDescription(_ filename: String?) -> String {
        guard let filename else { return "Video background" }
        let fileExtension = URL(fileURLWithPath: filename).pathExtension.uppercased()
        return fileExtension.isEmpty ? "Video background" : "\(fileExtension) video background"
    }
}

private struct BackgroundPreview: View {
    let frameURL: URL?
    let hasVideo: Bool
    let isLoading: Bool
    let videoDescription: String
    @State private var image: NSImage?
    @State private var loadFailed = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: hasVideo
                                ? [Color.indigo.opacity(0.72), Color.cyan.opacity(0.42)]
                                : [Color.secondary.opacity(0.18), Color.secondary.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let image, !isLoading {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.48)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    VStack {
                        HStack {
                            Spacer()
                            Text("STILL PREVIEW")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.42), in: Capsule())
                        }
                        Spacer()
                        HStack(spacing: 5) {
                            Image(systemName: "photo.fill")
                            Text(videoDescription)
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(9)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: hasVideo ? "play.display" : "display")
                            .font(.system(size: 38, weight: .light))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(hasVideo ? Color.white : Color.secondary)
                        Text(previewPlaceholderText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(hasVideo ? Color.white.opacity(0.9) : Color.secondary)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .task(id: "\(isLoading)|\(frameURL?.path ?? "")") {
            image = nil
            loadFailed = false
            guard !isLoading, let frameURL else { return }
            let cgImage: CGImage? = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(frameURL as CFURL, nil) else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 700
                ]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }.value
            guard !Task.isCancelled else { return }
            guard let cgImage else {
                loadFailed = true
                return
            }
            image = NSImage(cgImage: cgImage, size: .zero)
        }
    }

    private var previewPlaceholderText: String {
        guard hasVideo else { return "No background assigned" }
        return isLoading || (frameURL != nil && !loadFailed) ? "Preparing preview" : "Preview unavailable"
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.1), in: Capsule())
    }
}

private struct DisplaySelectorButton: View {
    let display: DisplayDescriptor
    let hasVideo: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "display")
                        .font(.system(size: 15, weight: .medium))
                    Circle()
                        .fill(hasVideo ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)
                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                        .offset(x: 2, y: 1)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(display.name.replacingOccurrences(of: " (Main Display)", with: ""))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(display.isMain ? "Main display" : (hasVideo ? "Background set" : "No background"))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.08))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select \(display.name)")
        .accessibilityValue(hasVideo ? "Background set" : "No background")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var modelObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 380, height: 560)
        popover.contentViewController = NSHostingController(rootView: StillMotionMenu(model: model))

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
        }
        updateStatusItem()

        modelObserver = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                self?.updateStatusItem()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: model.menuBarSymbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image
        button.toolTip = "StillMotion: \(model.statusText)"
        button.setAccessibilityLabel("StillMotion: \(model.statusText)")
    }
}
