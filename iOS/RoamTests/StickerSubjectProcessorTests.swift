import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Roam

final class StickerSubjectProcessorTests: XCTestCase {
    func testTransparentPNGAndOutlineUseAlphaInsteadOfImageColour() throws {
        let image = try fixture(width: 200, height: 100) { x, y in
            guard (20..<80).contains(x), (10..<40).contains(y) else { return [0, 0, 0, 0] }
            // A strong internal colour edge must not produce a second contour.
            return x < 50 ? [0, 0, 0, 255] : [0, 255, 255, 255]
        }
        let sticker = try StickerSubjectProcessor.makeCutout(from: image)
        XCTAssertEqual(sticker.aspectRatio, 2)
        XCTAssertEqual(sticker.contours.count, 1)
        let outline = try XCTUnwrap(sticker.contours.first)
        XCTAssertEqual(try XCTUnwrap(outline.map(\.x).min()), 0.10, accuracy: 0.025)
        XCTAssertEqual(try XCTUnwrap(outline.map(\.x).max()), 0.40, accuracy: 0.025)
        // The rectangle is at the top of the image, not mirrored to the bottom.
        XCTAssertEqual(try XCTUnwrap(outline.map(\.y).min()), 0.10, accuracy: 0.025)
        XCTAssertEqual(try XCTUnwrap(outline.map(\.y).max()), 0.40, accuracy: 0.025)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(sticker.pngData as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.png.identifier)
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let pixels = try rgbaPixels(decoded)
        let alphas = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
        XCTAssertTrue(alphas.contains(0), "The exported sticker must retain transparent pixels.")
        XCTAssertTrue(alphas.contains(255), "The subject must remain opaque.")
    }

    func testContourIncludesSubjectTouchingImageEdgesAndInteriorHole() throws {
        let image = try fixture(width: 100, height: 100) { x, y in
            let insideHole = (30..<70).contains(x) && (30..<70).contains(y)
            return insideHole ? [0, 0, 0, 0] : [255, 180, 0, 255]
        }
        let sticker = try StickerSubjectProcessor.makeCutout(from: image)
        XCTAssertEqual(sticker.contours.count, 2)
        let points = sticker.contours.flatMap { $0 }
        XCTAssertTrue(points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        XCTAssertLessThan(try XCTUnwrap(points.map(\.x).min()), 0.02)
        XCTAssertGreaterThan(try XCTUnwrap(points.map(\.x).max()), 0.98)
    }

    func testEXIFOrientationIsAppliedAndLongEdgeIsLimited() throws {
        let original = try fixture(width: 1600, height: 800) { _, _ in [255, 80, 0, 255] }
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, original, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let normalized = try StickerSubjectProcessor.normalizedImage(from: data as Data)
        XCTAssertEqual(normalized.width, 512)
        XCTAssertEqual(normalized.height, 1024)
    }

    func testInvalidImageAndEmptyAlphaAreRejected() async {
        do {
            _ = try await StickerSubjectProcessor.cutout(from: Data("invalid image".utf8))
            XCTFail("Invalid image bytes must not create a sticker.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("无法读取"))
        }
        do {
            let empty = try fixture(width: 64, height: 64) { _, _ in [0, 0, 0, 0] }
            _ = try StickerSubjectProcessor.makeCutout(from: empty)
            XCTFail("An empty alpha mask must not create a sticker.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("轮廓"))
        }
    }

    private func fixture(width: Int, height: Int, pixel: (Int, Int) -> [UInt8]) throws -> CGImage {
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width { bytes.append(contentsOf: pixel(x, y)) }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
                                    bitsPerPixel: 32, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false,
                                    intent: .defaultIntent))
    }

    private func rgbaPixels(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress,
                                                 width: image.width, height: image.height,
                                                 bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                 space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }
}
