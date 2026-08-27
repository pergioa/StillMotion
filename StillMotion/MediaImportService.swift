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
        static let legacyImportedFilename = "importedVideoFilename"
    }

    struct RestoreResult {
        let videosByDisplayID: [String: URL]
        let failures: [RestoreFailure]
    }

    struct RestoreFailure {
        let displayID: String
        let message: String
    }

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.defaults = defaults
    }

    func importVideo(from sourceURL: URL, for displayID: String) async throws -> URL {
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
        assignments[displayID] = destinationURL.lastPathComponent
        persist(assignments: assignments)

        return destinationURL
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
        let cacheSizeLimit: Int64 = 1_000_000_000

        var frameFiles: [(url: URL, date: Date?, size: Int64)] = []
        for url in contents where url.pathExtension.lowercased() == "jpg" {
            do {
                let attrs = try fileManager.attributesOfItem(atPath: url.path)
                let size = Int64(attrs[.size] as? Int64 ?? 0)
                let date = attrs[.modificationDate] as? Date
                frameFiles.append((url, date, size))
            } catch {
                continue
            }
        }

        var evictedCount = 0

        for info in frameFiles {
            guard !activeFrameNames.contains(info.url.lastPathComponent) else { continue }
            try fileManager.removeItem(at: info.url)
            NSLog("Evicted stale frame: %@", info.url.path)
            evictedCount += 1
        }

        let activeSize = frameFiles
            .filter { activeFrameNames.contains($0.url.lastPathComponent) }
            .reduce(Int64(0)) { $0 + $1.size }

        var totalCacheSize: Int64 = 0
        for info in frameFiles {
            totalCacheSize += info.size
        }

        if totalCacheSize - activeSize > cacheSizeLimit {
            var excess = totalCacheSize - activeSize - cacheSizeLimit
            for info in frameFiles.sorted(by: { (left, right) -> Bool in
                switch (left.date, right.date) {
                case (.some(let l), .some(let r)):
                    return l < r
                case (.some, .none):
                    return false
                case (.none, .some):
                    return true
                case (.none, .none):
                    return left.url.path < right.url.path
                }
            })
                where excess > 0 {
                guard !activeFrameNames.contains(info.url.lastPathComponent) else { continue }
                let size = info.size
                do {
                    try fileManager.removeItem(at: info.url)
                    NSLog("Evicted (cache limit): %@", info.url.path)
                    excess -= size
                    evictedCount += 1
                } catch {
                    NSLog("Failed to evict frame: %@", info.url.path)
                }
            }
        }

        if evictedCount > 0 {
            NSLog("Evicted %d stale cache frames", evictedCount)
        }
    }

    func restoredVideoURLs(defaultDisplayID: String?) async throws -> RestoreResult {
        let directory = try applicationSupportDirectory()
        var assignments = persistedAssignments()

        if assignments.isEmpty,
           let defaultDisplayID,
           let legacyFilename = defaults.string(forKey: DefaultsKey.legacyImportedFilename)
        {
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
        removeOrphanedVideos(in: directory, retaining: Set(assignments.values))
        return RestoreResult(videosByDisplayID: restored, failures: failures)
    }

    func removeVideo(for displayID: String) throws {
        let directory = try applicationSupportDirectory()
        var assignments = persistedAssignments()
        guard let filename = assignments.removeValue(forKey: displayID) else { return }
        persist(assignments: assignments)
        if !assignments.values.contains(filename) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(filename))
        }
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

    private func persist(assignments: [String: String]) {
        defaults.set(assignments, forKey: DefaultsKey.assignments)
        defaults.removeObject(forKey: DefaultsKey.legacyImportedFilename)
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
