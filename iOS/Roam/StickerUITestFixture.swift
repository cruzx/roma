#if DEBUG
import UIKit

@MainActor
enum StickerUITestFixture {
    static func seed(_ store: StickerBoardStore, populated: Bool = false) {
        guard store.items.isEmpty else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 320), format: format).image { _ in
            UIColor(red: 0.92, green: 0.44, blue: 0.10, alpha: 1).setStroke()
            let handle = UIBezierPath(roundedRect: CGRect(x: 107, y: 24, width: 86, height: 58), cornerRadius: 17)
            handle.lineWidth = 20
            handle.stroke()
            UIColor(red: 1.0, green: 0.59, blue: 0.13, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 48, y: 63, width: 204, height: 229), cornerRadius: 44).fill()
            UIColor(red: 0.87, green: 0.34, blue: 0.08, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 76, y: 185, width: 148, height: 75), cornerRadius: 22).fill()
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(x: 104, y: 106, width: 92, height: 46), cornerRadius: 13).fill()
            UIColor(red: 0.30, green: 0.19, blue: 0.12, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 124, y: 121, width: 9, height: 14)).fill()
            UIBezierPath(ovalIn: CGRect(x: 167, y: 121, width: 9, height: 14)).fill()
        }
        guard let cgImage = image.cgImage else { return }
        do {
            let cutout = try StickerSubjectProcessor.makeCutout(from: cgImage)
            store.addSticker(cutout, at: CGPoint(x: 0.5, y: 0.4))
            if populated {
                // Multiple pages exercise retained image/contour layers during fast browsing.
                for index in 0..<24 {
                    let page = Double(index / 4)
                    let column = Double(index % 2)
                    let row = Double((index % 4) / 2)
                    if let id = store.addSticker(cutout, at: CGPoint(x: page + 0.23 + column * 0.5,
                                                                   y: 0.24 + row * 0.42)),
                       var item = store.items.first(where: { $0.id == id }) {
                        item.scale = index.isMultiple(of: 3) ? 1.3 : 0.85
                        item.rotation = Double(index % 5 - 2) * 12
                        item.borderStyle = index.isMultiple(of: 2) ? .solid : .dashed
                        store.update(item)
                    }
                    if index.isMultiple(of: 4) {
                        store.addText("Travel memories \(index / 4 + 1)", at: CGPoint(x: page + 0.5, y: 0.49),
                                      color: "#1D1D1F", fontSize: 24)
                    }
                }
            }
        } catch {
            store.error = error.localizedDescription
        }
    }
}
#endif
