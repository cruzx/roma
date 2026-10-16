import UIKit

/// Places only the new photo; manually arranged items retain their geometry.
enum StickerAutoLayout {
    struct Placement {
        let point: CGPoint
        let viewport: StickerCanvasViewport
    }
    static func imageSize(aspectRatio: Double, scale: Double, canvasSize: CGSize) -> CGSize {
        let longest = min(200, canvasSize.width * 0.48) * scale
        let aspect = max(0.1, aspectRatio)
        return aspect >= 1 ? CGSize(width: longest, height: longest / aspect) : CGSize(width: longest * aspect, height: longest)
    }
    static func bounds(_ item: StickerCanvasItem, canvasSize: CGSize) -> CGRect {
        let size: CGSize
        if item.kind == .image {
            let image = imageSize(aspectRatio: item.aspectRatio, scale: item.scale, canvasSize: canvasSize)
            size = CGSize(width: image.width + 16, height: image.height + 16)
        } else {
            let width = min(canvasSize.width * 0.84, 280 * item.scale)
            let font = UIFont(name: "Xiaolai", size: item.fontSize * item.scale) ?? .systemFont(ofSize: item.fontSize * item.scale)
            let measured = (item.text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
            size = CGSize(width: width + 20, height: ceil(measured.height) + 20)
        }
        let angle = item.rotation * .pi / 180
        let width = abs(cos(angle)) * size.width + abs(sin(angle)) * size.height
        let height = abs(sin(angle)) * size.width + abs(cos(angle)) * size.height
        return CGRect(x: item.x * canvasSize.width - width / 2, y: item.y * canvasSize.height - height / 2, width: width, height: height)
    }
    static func placement(aspectRatio: Double, items: [StickerCanvasItem], canvasSize: CGSize, viewport: StickerCanvasViewport) -> Placement? {
        guard canvasSize.width.isFinite, canvasSize.height.isFinite, canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let gap: CGFloat = 20
        let image = imageSize(aspectRatio: aspectRatio, scale: 1, canvasSize: canvasSize)
        let width = image.width + 16, height = image.height + 16
        let occupied = items.map { bounds($0, canvasSize: canvasSize).insetBy(dx: -gap / 2, dy: -gap / 2) }
        let left: CGFloat = viewport.x * canvasSize.width + gap
        let top: CGFloat = viewport.y * canvasSize.height + max(100, canvasSize.height * 0.18)
        let right: CGFloat = (viewport.x + 1) * canvasSize.width - gap
        let bottom = max(top + height, (viewport.y + 1) * canvasSize.height - 110)
        let xs = ([left] + occupied.map { $0.maxX + gap / 2 }).filter { $0 >= left && $0 + width <= right }.sorted()
        let ys = ([top] + occupied.map { $0.maxY + gap / 2 }).filter { $0 >= top && $0 + height <= bottom }.sorted()
        func result(x: CGFloat, y: CGFloat, reveal: Bool) -> Placement? {
            let center = CGPoint(x: (x + width / 2) / canvasSize.width, y: (y + height / 2) / canvasSize.height)
            guard abs(center.x) < 999_999, abs(center.y) < 999_999 else { return nil }
            return Placement(point: center, viewport: reveal ? StickerCanvasViewport(x: center.x - 0.5, y: viewport.y) : viewport)
        }
        for y in ys {
            for x in xs {
                let candidate = CGRect(x: x, y: y, width: width, height: height).insetBy(dx: -gap / 2, dy: -gap / 2)
                if !occupied.contains(where: { $0.intersects(candidate) }) { return result(x: x, y: y, reveal: false) }
            }
        }
        // This journal scrolls horizontally. Extend right and reveal the new photo.
        let x = max(left, (occupied.map(\.maxX).max() ?? left) + gap)
        return result(x: x, y: top, reveal: true)
    }
}
