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

    init(model: AppModel, initialDisplayID: String? = nil) {
        self.model = model
        _selectedDisplayID = State(initialValue: initialDisplayID)
    }

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

    private var displayIDs: [String] {
        model.availableDisplays.map(\.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.availableDisplays.isEmpty {
                        noDisplaysView
                    } else {
                        displaySelector
                        if let selectedDisplay {
                            backgroundSection(for: selectedDisplay)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 380, height: 430)
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
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.04, green: 0.59, blue: 1),
                                Color(red: 0.02, green: 0.36, blue: 0.96)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            Text("StillMotion")
                .font(.headline)

            Spacer()

            StatusPill(text: model.statusText, color: statusColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var displaySelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Displays", detail: "\(model.availableDisplays.count) connected")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())],
                spacing: 8
            ) {
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

    private func backgroundSection(for display: DisplayDescriptor) -> some View {
        let hasVideo = selectedVideoFilename != nil
        let frameURL = model.previewFrameURL(for: display.id)
        let actionsDisabled = model.isBackgroundActionDisabled(for: display.id)

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Background", detail: displayTitle(display))

            VStack(spacing: 0) {
                BackgroundPreview(
                    frameURL: frameURL,
                    hasVideo: hasVideo,
                    isLoading: model.isRestoringVideos || model.isUpdatingBackground(for: display.id)
                )
                .id("\(display.id)|\(frameURL?.path ?? "")")
                .frame(height: 118)
                .padding(10)

                Divider()

                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                        Image(systemName: hasVideo ? "film.fill" : "film")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(hasVideo ? Color.accentColor : Color.secondary)
                    }
                    .frame(width: 30, height: 30)

                    Text(selectedVideoFilename ?? "No background selected")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(selectedVideoFilename ?? "No background selected")
                        .layoutPriority(1)

                    Spacer(minLength: 4)

                    Button {
                        model.chooseVideo(for: display.id)
                    } label: {
                        Group {
                            if model.isUpdatingBackground(for: display.id) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                                    .frame(width: 96)
                            } else {
                                Text(hasVideo ? "Change Background" : "Choose Background")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(height: 28)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .disabled(actionsDisabled)
                    .opacity(actionsDisabled ? 0.5 : 1)
                    .keyboardShortcut("o", modifiers: .command)

                }
                .padding(10)
            }
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.75),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1))
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
            Spacer()
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
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

}

private struct BackgroundPreview: View {
    private static let imageCache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 8
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()

    let frameURL: URL?
    let hasVideo: Bool
    let isLoading: Bool
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
            if let cachedImage = Self.imageCache.object(forKey: frameURL as NSURL) {
                image = cachedImage
                return
            }
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
            let decodedImage = NSImage(cgImage: cgImage, size: .zero)
            let imageCost = cgImage.bytesPerRow * cgImage.height
            Self.imageCache.setObject(decodedImage, forKey: frameURL as NSURL, cost: imageCost)
            image = decodedImage
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
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
                        Image(systemName: display.symbolName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    }
                    .frame(width: 30, height: 30)

                    Text(display.name.replacingOccurrences(of: " (Main Display)", with: ""))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                HStack(spacing: 5) {
                    Text(display.isBuiltIn ? "Built-in display" : "External display")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    if display.isMain {
                        Text("MAIN")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }

                HStack(spacing: 5) {
                    Circle()
                        .fill(hasVideo ? Color.green : Color.secondary.opacity(0.65))
                        .frame(width: 5, height: 5)
                    Text(hasVideo ? "Background set" : "No background")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(hasVideo ? Color.primary : Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select \(display.name)")
        .accessibilityValue(hasVideo ? "Background set" : "No background")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var modelObserver: AnyCancellable?
    private var lastStatusItemState: (symbolName: String, statusText: String)?
    private var contextualDisplayID: String?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 430)
        popover.contentViewController = NSHostingController(rootView: StillMotionMenu(model: model))

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleStatusItemClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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

    @objc private func handleStatusItemClick() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            closePopover()
            showStatusMenu(relativeTo: button)
            return
        }

        if popover.isShown {
            closePopover()
        } else {
            let displayID = button.window?.screen?.persistentDisplayID
            popover.contentViewController = NSHostingController(
                rootView: StillMotionMenu(model: model, initialDisplayID: displayID)
            )
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            installOutsideClickMonitors()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitors()
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            guard let self, self.popover.isShown else { return event }
            let clickedWindow = event.window
            let popoverWindow = self.popover.contentViewController?.view.window
            let statusItemWindow = self.statusItem.button?.window
            if clickedWindow !== popoverWindow && clickedWindow !== statusItemWindow {
                self.closePopover()
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
        removeOutsideClickMonitors()
    }

    private func removeOutsideClickMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func showStatusMenu(relativeTo button: NSStatusBarButton) {
        contextualDisplayID = button.window?.screen?.persistentDisplayID
            ?? model.availableDisplays.first(where: \.isMain)?.id
            ?? model.availableDisplays.first?.id

        let hasBackground = contextualDisplayID.flatMap(model.videoFilename(for:)) != nil
        let backgroundActionsDisabled = contextualDisplayID.map(model.isBackgroundActionDisabled(for:)) ?? true
        let menu = NSMenu()
        menu.autoenablesItems = false

        let playbackItem = NSMenuItem(
            title: model.policy.isManuallyPaused ? "Play Backgrounds" : "Pause Backgrounds",
            action: #selector(togglePlaybackFromStatusMenu),
            keyEquivalent: ""
        )
        playbackItem.target = self
        playbackItem.image = NSImage(
            systemSymbolName: model.policy.isManuallyPaused ? "play.fill" : "pause.fill",
            accessibilityDescription: nil
        )
        playbackItem.isEnabled = model.hasMedia
        menu.addItem(playbackItem)
        menu.addItem(.separator())

        let revealItem = NSMenuItem(
            title: "Reveal Background in Finder",
            action: #selector(revealBackgroundFromStatusMenu),
            keyEquivalent: ""
        )
        revealItem.target = self
        revealItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        revealItem.isEnabled = hasBackground && !backgroundActionsDisabled
        menu.addItem(revealItem)

        let removeItem = NSMenuItem(
            title: "Remove Background",
            action: #selector(removeBackgroundFromStatusMenu),
            keyEquivalent: ""
        )
        removeItem.target = self
        removeItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        removeItem.isEnabled = hasBackground && !backgroundActionsDisabled
        menu.addItem(removeItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit StillMotion",
            action: #selector(quitFromStatusMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func togglePlaybackFromStatusMenu() {
        model.toggleManualPlayback()
    }

    @objc private func revealBackgroundFromStatusMenu() {
        guard let contextualDisplayID else { return }
        model.revealVideo(for: contextualDisplayID)
    }

    @objc private func removeBackgroundFromStatusMenu() {
        guard let contextualDisplayID else { return }
        model.removeVideo(for: contextualDisplayID)
    }

    @objc private func quitFromStatusMenu() {
        NSApplication.shared.terminate(nil)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let state = (symbolName: model.menuBarSymbolName, statusText: model.statusText)
        if let lastStatusItemState,
           lastStatusItemState.symbolName == state.symbolName,
           lastStatusItemState.statusText == state.statusText
        {
            return
        }
        lastStatusItemState = state

        let image = NSImage(systemSymbolName: state.symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image
        button.toolTip = "StillMotion: \(state.statusText)"
        button.setAccessibilityLabel("StillMotion: \(state.statusText)")
    }
}
