import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CoverPhotoError: LocalizedError {
    case invalid
    var errorDescription: String? { AppLocalization.text("无法读取这张照片，请换一张重试。") }
}
enum CoverPhotoCodec {
    static func compress(_ data: Data, maxPixelSize: Int = 1600, quality: Double = 0.78) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw CoverPhotoError.invalid }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw CoverPhotoError.invalid }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CoverPhotoError.invalid }
        return output as Data
    }
}
