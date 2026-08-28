import AVFoundation
import Foundation
#if SWIFT_PACKAGE
import StillMotionCore
#endif

actor MediaImportService {
    private let fileManager: FileManager
    private let defaults: UserDefaults

    private enum DefaultsKey {
        static let assignments = "importedVideoFilenamesByDisplay"
        static let originalFilenames = "originalVideoFilenamesByDisplay"
        static let legacyImportedFilename = "importedVideoFilename"
    }

    struct RestoreResult {
        let videosByDisplayID: [String: URL]
        let originalFilenamesByDisplayID: [String: String]
        let failures: [RestoreFailure]
    }

    struct ImportedVideo {
        let url: URL
        let originalFilename: String
        let replacedManagedFilename: String?
    }

    struct RestoreFailure {
        let displayID: String
        let message: String
    }

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.defaults = defaults
    }

    func importVideo(from sourceURL: URL, for displayID: String) async throws -> ImportedVideo {
        let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try await validateVideo(at: sourceURL)

        let directory = try applicationSupportDirectory()
        let stagingDirectory = directory.appendingPathComponent("Imports", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        let fileExtension = sourceURL.pathExtension.lowercased()
        let identifier = UUID().uuidString
        let stagingURL = stagingDirectory.appendingPathComponent(identifier).appendingPathExtension(fileExtension)
        let destinationURL = directory.appendingPathComponent("Background-\(identifier)").appendingPathExtension(fileExtension)

        do {
            try fileManager.copyItem(at: sourceURL, to: stagingURL)
            try await validateVideo(at: stagingURL)
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }

        var assignments = persistedAssignments()
        let replacedManagedFilename = assignments[displayID]
        var originalFilenames = persistedOriginalFilenames()
        originalFilenames[destinationURL.lastPathComponent] = sourceURL.lastPathComponent
        persist(
            originalFilenames: originalFilenames,
            retaining: Set(assignments.values).union([destinationURL.lastPathComponent])
        )
        assignments[displayID] = destinationURL.lastPathComponent
        persist(assignments: assignments)
        persist(originalFilenames: originalFilenames, retaining: Set(assignments.values))

        return ImportedVideo(
            url: destinationURL,
            originalFilename: sourceURL.lastPathComponent,
            replacedManagedFilename: replacedManagedFilename
        )
    }

    func evictStaleWallpaperFrames(activeFrameNames: Set<String>) async throws {
        let cacheBaseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let cacheDirectory = cacheBaseURL
            .appendingPathComponent("StillMotion", isDirectory: true)
            .appendingPathComponent("System Wallpapers", isDirectory: true)
        guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        var frameFiles: [URL] = []
        for url in contents where url.pathExtension.lowercased() == "jpg" {
            frameFiles.append(url)
        }

        var evictedCount = 0

        for url in frameFiles {
            guard !activeFrameNames.contains(url.lastPathComponent) else { continue }
            try fileManager.removeItem(at: url)
            NSLog("Evicted stale frame: %@", url.path)
            evictedCount += 1
        }

        if evictedCount > 0 {
            NSLog("Evicted %d stale cache frames", evictedCount)
        }
    }

    func restoredVideoURLs(defaultDisplayID: String?) async throws -> RestoreResult {
        let directory = try applicationSupportDirectory()
        var assignments = persistedAssignments()
        let originalFilenames = persistedOriginalFilenames()

        if assignments.isEmpty, let legacyFilename = defaults.string(forKey: DefaultsKey.legacyImportedFilename) {
            guard let defaultDisplayID else {
                return RestoreResult(
                    videosByDisplayID: [:],
                    originalFilenamesByDisplayID: [:],
                    failures: []
                )
            }
            assignments[defaultDisplayID] = legacyFilename
            persist(assignments: assignments)
        }

        var restored: [String: URL] = [:]
        var failures: [RestoreFailure] = []
        for (displayID, filename) in assignments {
            let url = directory.appendingPathComponent(filename)
            do {
                try await validateVideo(at: url)
                restored[displayID] = url
            } catch {
                assignments.removeValue(forKey: displayID)
                failures.append(RestoreFailure(displayID: displayID, message: error.localizedDescription))
            }
        }

        persist(assignments: assignments)
        persist(originalFilenames: originalFilenames, retaining: Set(assignments.values))
        removeOrphanedVideos(in: directory, retaining: Set(assignments.values))
        var restoredFilenames: [String: String] = [:]
        for displayID in restored.keys {
            guard let managedFilename = assignments[displayID] else { continue }
            restoredFilenames[displayID] = originalFilenames[managedFilename] ?? managedFilename
        }
        return RestoreResult(
            videosByDisplayID: restored,
            originalFilenamesByDisplayID: restoredFilenames,
            failures: failures
        )
    }

    func removeVideo(for displayID: String) throws {
        let directory = try applicationSupportDirectory()
        var assignments = persistedAssignments()
        guard let filename = assignments.removeValue(forKey: displayID) else { return }
        persist(assignments: assignments)
        persist(originalFilenames: persistedOriginalFilenames(), retaining: Set(assignments.values))
        if !assignments.values.contains(filename) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(filename))
        }
    }

    func removeManagedVideoIfUnassigned(_ filename: String) throws {
        guard !persistedAssignments().values.contains(filename) else { return }
        let directory = try applicationSupportDirectory()
        try? fileManager.removeItem(at: directory.appendingPathComponent(filename))
    }

    private func validateVideo(at url: URL) async throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw MediaValidationError.fileMissing
        }

        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        try MediaFileValidator.validateFileMetadata(
            extension: url.pathExtension,
            size: Int64(values.fileSize ?? 0),
            isRegularFile: values.isRegularFile == true
        )

        let asset = AVURLAsset(url: url)
        let isPlayable = try await asset.load(.isPlayable)
        guard isPlayable else {
            throw MediaValidationError.notPlayable
        }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else {
            throw MediaValidationError.noVideoTrack
        }
    }

    private func applicationSupportDirectory() throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL.appendingPathComponent("StillMotion", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func persistedAssignments() -> [String: String] {
        defaults.dictionary(forKey: DefaultsKey.assignments) as? [String: String] ?? [:]
    }

    private func persistedOriginalFilenames() -> [String: String] {
        defaults.dictionary(forKey: DefaultsKey.originalFilenames) as? [String: String] ?? [:]
    }

    private func persist(assignments: [String: String]) {
        defaults.set(assignments, forKey: DefaultsKey.assignments)
        defaults.removeObject(forKey: DefaultsKey.legacyImportedFilename)
    }

    private func persist(originalFilenames: [String: String], retaining managedFilenames: Set<String>) {
        defaults.set(
            originalFilenames.filter { managedFilenames.contains($0.key) },
            forKey: DefaultsKey.originalFilenames
        )
    }

    private func removeOrphanedVideos(in directory: URL, retaining filenames: Set<String>) {
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for url in contents where url.lastPathComponent.hasPrefix("Background-") {
            guard !filenames.contains(url.lastPathComponent) else { continue }
            try? fileManager.removeItem(at: url)
        }
    }
}
