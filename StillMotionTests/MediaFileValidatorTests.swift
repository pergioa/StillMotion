#if canImport(XCTest)
import XCTest
@testable import StillMotion

final class MediaFileValidatorTests: XCTestCase {
    func testSupportedExtensionsAreCaseInsensitive() throws {
        for fileExtension in ["mp4", "MOV", "M4v"] {
            XCTAssertNoThrow(
                try MediaFileValidator.validateFileMetadata(extension: fileExtension, size: 100, isRegularFile: true)
            )
        }
    }

    func testUnsupportedExtensionIsRejected() {
        XCTAssertThrowsError(
            try MediaFileValidator.validateFileMetadata(extension: "avi", size: 100, isRegularFile: true)
        ) { error in
            XCTAssertEqual(error as? MediaValidationError, .unsupportedExtension("avi"))
        }
    }

    func testMaximumFileSizeBoundary() throws {
        XCTAssertNoThrow(
            try MediaFileValidator.validateFileMetadata(
                extension: "mp4",
                size: MediaFileValidator.maximumFileSize,
                isRegularFile: true
            )
        )
        XCTAssertThrowsError(
            try MediaFileValidator.validateFileMetadata(
                extension: "mov",
                size: MediaFileValidator.maximumFileSize + 1,
                isRegularFile: true
            )
        )
    }

    func testDirectoryIsRejected() {
        XCTAssertThrowsError(
            try MediaFileValidator.validateFileMetadata(extension: "m4v", size: 100, isRegularFile: false)
        ) { error in
            XCTAssertEqual(error as? MediaValidationError, .notRegularFile)
        }
    }
}
#endif
