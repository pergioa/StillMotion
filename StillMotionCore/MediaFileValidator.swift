// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sergio Abreo Alvarez

import Foundation

public enum MediaValidationError: LocalizedError, Equatable {
    case unsupportedExtension(String)
    case fileMissing
    case notRegularFile
    case fileTooLarge(maximumBytes: Int64)
    case notPlayable
    case noVideoTrack

    public var errorDescription: String? {
        switch self {
        case .unsupportedExtension:
            return "Choose an MP4, MOV, or M4V video."
        case .fileMissing:
            return "The selected video could not be found."
        case .notRegularFile:
            return "The selected item is not a regular file."
        case let .fileTooLarge(maximumBytes):
            return "The video is larger than \(maximumBytes / 1_073_741_824) GB."
        case .notPlayable:
            return "AVFoundation cannot play this video. It may be corrupt or use an unsupported codec."
        case .noVideoTrack:
            return "The selected file does not contain a video track."
        }
    }
}

public enum MediaFileValidator {
    public static let supportedExtensions: Set<String> = ["mp4", "mov", "m4v"]
    public static let maximumFileSize: Int64 = 1_073_741_824

    public static func validateFileMetadata(extension fileExtension: String, size: Int64, isRegularFile: Bool) throws {
        guard supportedExtensions.contains(fileExtension.lowercased()) else {
            throw MediaValidationError.unsupportedExtension(fileExtension)
        }
        guard isRegularFile else {
            throw MediaValidationError.notRegularFile
        }
        guard size <= maximumFileSize else {
            throw MediaValidationError.fileTooLarge(maximumBytes: maximumFileSize)
        }
    }
}
