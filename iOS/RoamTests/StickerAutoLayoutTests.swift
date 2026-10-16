import XCTest
@testable import Roam

final class StickerAutoLayoutTests: XCTestCase {
    func testRepeatedPhotosNeverOverlapIncludingRotatedScaledItems() throws {
        let size = CGSize(width: 390, height: 740)
        var items = [StickerCanvasItem(kind: .image, x: 0.5, y: 0.4, scale: 2, rotation: 45)]
        let original = items[0]
        var viewport = StickerCanvasViewport()
        for index in 0..<30 {
            let aspect = [0.2, 1.0, 4.0][index % 3]
            let placement = try XCTUnwrap(StickerAutoLayout.placement(aspectRatio: aspect, items: items, canvasSize: size, viewport: viewport))
            let item = StickerCanvasItem(kind: .image, x: placement.point.x, y: placement.point.y, aspectRatio: aspect)
            let frame = StickerAutoLayout.bounds(item, canvasSize: size)
            XCTAssertFalse(items.contains { StickerAutoLayout.bounds($0, canvasSize: size).intersects(frame) })
            XCTAssertGreaterThanOrEqual(placement.point.x - placement.viewport.x, 0)
            XCTAssertLessThanOrEqual(placement.point.x - placement.viewport.x, 1)
            items.append(item); viewport = placement.viewport
        }
        XCTAssertEqual(items[0], original)
    }
    func testFillsCurrentViewportAndAvoidsText() throws {
        let size = CGSize(width: 390, height: 740)
        let text = StickerCanvasItem(kind: .text, x: 4.5, y: 0.4, text: "旅行日记\n不要覆盖", fontSize: 40)
        let placement = try XCTUnwrap(StickerAutoLayout.placement(aspectRatio: 2, items: [text], canvasSize: size, viewport: .init(x: 4)))
        let item = StickerCanvasItem(kind: .image, x: placement.point.x, y: placement.point.y, aspectRatio: 2)
        XCTAssertFalse(StickerAutoLayout.bounds(text, canvasSize: size).intersects(StickerAutoLayout.bounds(item, canvasSize: size)))
        XCTAssertEqual(placement.viewport.x, 4)
    }
    func testInvalidCanvasDoesNotInsertAtDefaultOverlappingPosition() {
        XCTAssertNil(StickerAutoLayout.placement(aspectRatio: 1, items: [], canvasSize: .zero, viewport: .init()))
    }
}
