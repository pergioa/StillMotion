import AppKit
import SwiftUI

@main
struct StillMotionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            Text(model.statusText)

            ForEach(model.availableDisplays) { display in
                Text("\(display.name): \(model.videoFilename(for: display.id) ?? "No StillMotion Video")")
            }

            Divider()

            Menu("Choose Video…") {
                ForEach(model.availableDisplays) { display in
                    Button(display.name) {
                        model.chooseVideo(for: display.id)
                    }
                }
            }
            .disabled(model.availableDisplays.isEmpty)

            Button(model.playPauseTitle) {
                model.toggleManualPlayback()
            }
            .disabled(!model.hasMedia)

            if !model.displaysWithMedia.isEmpty {
                Menu("Reveal Video in Finder") {
                    ForEach(model.displaysWithMedia) { display in
                        Button(display.name) {
                            model.revealVideo(for: display.id)
                        }
                    }
                }

                Menu("Remove Background") {
                    ForEach(model.displaysWithMedia) { display in
                        Button(display.name) {
                            model.removeVideo(for: display.id)
                        }
                    }
                }
            }

            Divider()

            Button("Quit StillMotion") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: model.menuBarSymbolName)
                .accessibilityLabel("StillMotion: \(model.statusText)")
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
