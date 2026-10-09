import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

struct StickerOutlinePoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
}

struct StickerCutout: Sendable {
    let pngData: Data
    let contours: [[StickerOutlinePoint]]
    let aspectRatio: Double
}

enum StickerSubjectError: LocalizedError {
    case unreadableImage
    case noSubject
    case recognitionUnavailable
    case cutoutFailed
    case outlineFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return AppLocalization.text("这张照片无法读取，请重新拍照或选择另一张照片。")
        case .noSubject:
            return AppLocalization.text("没有找到清晰的主体，请让人物或物品更突出后重试。")
        case .recognitionUnavailable:
            #if targetEnvironment(simulator)
            return AppLocalization.text("当前模拟器未能运行主体识别，请在 iPhone 真机上重试。")
            #else
            return AppLocalization.text("暂时无法识别照片主体，请换一张主体更清晰的照片重试。")
            #endif
        case .cutoutFailed:
            return AppLocalization.text("这次没能生成贴纸，请重新选择照片。")
        case .outlineFailed:
            return AppLocalization.text("没有找到清晰的主体轮廓，请换一张照片重试。")
        }
    }
}

enum StickerSubjectProcessor {
    static func cutout(from data: Data) async throws -> StickerCutout {
        let cancellation = StickerVisionCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try autoreleasepool {
                let image = try normalizedImage(from: data)
                try Task.checkCancellation()
                let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
                let request = VNGenerateForegroundInstanceMaskRequest()
                do {
                    try cancellation.perform(request, with: handler)
                } catch {
                    try Task.checkCancellation()
                    throw StickerSubjectError.recognitionUnavailable
                }
                guard let observation = request.results?.first,
                      !observation.allInstances.isEmpty else {
                    throw StickerSubjectError.noSubject
                }
                try Task.checkCancellation()
                let foreground: CVPixelBuffer
                do {
                    foreground = try observation.generateMaskedImage(
                        ofInstances: observation.allInstances,
                        from: handler,
                        croppedToInstancesExtent: true
                    )
                } catch {
                    try Task.checkCancellation()
                    throw StickerSubjectError.cutoutFailed
                }
                try Task.checkCancellation()
                let context = CIContext(options: [.cacheIntermediates: false])
                let result = CIImage(cvPixelBuffer: foreground)
                guard let cutout = context.createCGImage(result, from: result.extent,
                                                        format: .RGBA8,
                                                        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
                    throw StickerSubjectError.cutoutFailed
                }
                return try makeCutout(from: cutout, cancellation: cancellation)
            }
        }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
            cancellation.cancel()
        }
    }

    /// ImageIO applies EXIF rotation and mirroring before Vision sees the pixels.
    static func normalizedImage(from data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData,
                                                       [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary), image.width > 0, image.height > 0 else {
            throw StickerSubjectError.unreadableImage
        }
        return image
    }

    /// Also used with synthetic transparent images to test geometry without relying on ML output.
    static func makeCutout(from image: CGImage) throws -> StickerCutout {
        try makeCutout(from: image, cancellation: StickerVisionCancellation())
    }

    private static func makeCutout(from image: CGImage,
                                   cancellation: StickerVisionCancellation) throws -> StickerCutout {
        try Task.checkCancellation()
        let contours = try outlines(from: image, cancellation: cancellation)
        guard !contours.isEmpty else { throw StickerSubjectError.outlineFailed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw StickerSubjectError.cutoutFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw StickerSubjectError.cutoutFailed }
        try Task.checkCancellation()
        return StickerCutout(pngData: data as Data, contours: contours,
                             aspectRatio: Double(image.width) / Double(image.height))
    }

    private static func outlines(from image: CGImage,
                                 cancellation: StickerVisionCancellation) throws -> [[StickerOutlinePoint]] {
        let source = CIImage(cgImage: image)
        let width = Double(image.width)
        let height = Double(image.height)
        let padding = 6.0
        // Make RGB = alpha and alpha = 1. Internal colours and transparent RGB must
        // not contribute edges; Vision must receive an opaque white-on-black mask.
        let alpha = source.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
        let extent = source.extent.insetBy(dx: -padding, dy: -padding)
        let paddedMask = alpha.composited(over: CIImage(color: .black))
            .cropped(to: extent)
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.8])
            .cropped(to: extent)
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let mask = context.createCGImage(paddedMask, from: extent,
                                              format: .RGBA8,
                                              colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
            throw StickerSubjectError.outlineFailed
        }
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 1
        request.detectsDarkOnLight = false
        request.maximumImageDimension = 1040
        do {
            try cancellation.perform(request, with: VNImageRequestHandler(cgImage: mask, orientation: .up))
        } catch {
            try Task.checkCancellation()
            throw StickerSubjectError.outlineFailed
        }
        guard let observation = request.results?.first else { throw StickerSubjectError.outlineFailed }
        var result: [[StickerOutlinePoint]] = []
        func append(_ contour: VNContour) throws {
            try Task.checkCancellation()
            let polygon = (try? contour.polygonApproximation(epsilon: 0.0008)) ?? contour
            let points = polygon.normalizedPoints.map { point in
                StickerOutlinePoint(
                    x: min(1, max(0, (Double(point.x) * (width + padding * 2) - padding) / width)),
                    y: min(1, max(0, ((1 - Double(point.y)) * (height + padding * 2) - padding) / height))
                )
            }
            if points.count >= 3 {
                let twiceArea = points.indices.reduce(0.0) { sum, index in
                    let a = points[index]
                    let b = points[(index + 1) % points.count]
                    return sum + a.x * b.y - b.x * a.y
                }
                // Ignore tiny alpha speckles while retaining separate subjects and interior holes.
                if abs(twiceArea) * width * height / 2 >= 8 {
                    result.append(points)
                }
            }
            for child in contour.childContours { try append(child) }
        }
        for contour in observation.topLevelContours { try append(contour) }
        return result
    }
}

/// Cancels an in-flight synchronous Vision request when its enclosing Task is cancelled.
private final class StickerVisionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var current: VNRequest?
    private var cancelled = false

    func perform(_ request: VNRequest, with handler: VNImageRequestHandler) throws {
        lock.lock()
        let wasCancelled = cancelled
        if !wasCancelled { current = request }
        lock.unlock()
        guard !wasCancelled else { throw CancellationError() }
        defer {
            lock.lock()
            current = nil
            lock.unlock()
        }
        try handler.perform([request])
        try Task.checkCancellation()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let request = current
        lock.unlock()
        request?.cancel()
    }
}
