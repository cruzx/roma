import CoreGraphics
import XCTest
@testable import Roam

final class StickerBoardStoreTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("roam-sticker-test-\(UUID().uuidString)")
    }

    private var cutout: StickerCutout {
        // A valid transparent 1 × 1 PNG; the board stores the original bytes unchanged.
        StickerCutout(
            pngData: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")!,
            contours: [[StickerOutlinePoint(x: 0, y: 0), StickerOutlinePoint(x: 1, y: 0), StickerOutlinePoint(x: 1, y: 1)]],
            aspectRatio: 1
        )
    }

    @MainActor func testStickerAndTextSurviveRelaunchWithOrderAndGeometry() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        let photoID = try XCTUnwrap(store.addSticker(cutout, at: CGPoint(x: 0.2, y: 0.7)))
        let textID = try XCTUnwrap(store.addText("旅途记忆", at: CGPoint(x: 0.8, y: 0.3), color: "#FFFFFF", fontSize: 34))
        var photo = try XCTUnwrap(store.items.first { $0.id == photoID })
        photo.borderStyle = .dashed
        photo.scale = 1.7
        photo.rotation = -25
        store.update(photo)
        store.bringToFront(photoID)
        XCTAssertEqual(store.items.map(\.id), [textID, photoID])
        let restored = StickerBoardStore(directory: directory)
        XCTAssertEqual(restored.items, store.items)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(restored.imageURL(for: photo))), cutout.pngData)
        XCTAssertNil(restored.error)
    }

    @MainActor func testRemoveThenUndoPreservesImageAndOriginalStackPosition() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        let id = try XCTUnwrap(store.addSticker(cutout))
        store.addText("文字", at: CGPoint(x: 0.5, y: 0.5), color: "#1D1D1F", fontSize: 28)
        let original = store.items
        let file = try XCTUnwrap(store.imageURL(for: original[0]))
        store.remove(id)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertTrue(store.canUndoRemoval)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        store.undoLastRemoval()
        XCTAssertEqual(store.items, original)
        XCTAssertFalse(store.canUndoRemoval)
        XCTAssertEqual(StickerBoardStore(directory: directory).items, original)
    }

    @MainActor func testLegacyVersionsWithoutBorderColorDefaultToWhiteWithoutRewritingFiles() throws {
        for version in [1, 2] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = StickerBoardStore(directory: directory)
            let photoID = try XCTUnwrap(source.addSticker(cutout, at: CGPoint(x: 0.2, y: 0.7)))
            source.addText("旧画布", at: CGPoint(x: 0.8, y: 0.3), color: "#1D1D1F", fontSize: 28)
            source.moveViewport(to: StickerCanvasViewport(x: -3, y: 5))
            for var item in source.items {
                item.borderColor = "#A1B2C3"
                item.borderStyle = .dashed
                source.update(item)
            }
            let expectedItems = source.items.map { item in
                var item = item
                item.borderColor = nil
                return item
            }
            let photo = try XCTUnwrap(source.items.first { $0.id == photoID })
            let imageURL = try XCTUnwrap(source.imageURL(for: photo))
            let documentURL = directory.appendingPathComponent("board.json")
            var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: documentURL)) as? [String: Any])
            var items = try XCTUnwrap(document["items"] as? [[String: Any]])
            for index in items.indices {
                XCTAssertNotNil(items[index].removeValue(forKey: "borderColor"))
                XCTAssertNil(items[index]["borderColor"], "The legacy fixture must truly omit the new field")
            }
            document["items"] = items
            document["version"] = version
            if version == 1 { document.removeValue(forKey: "viewport") }
            let legacy = try JSONSerialization.data(withJSONObject: document, options: .sortedKeys)
            try legacy.write(to: documentURL, options: .atomic)

            let restored = StickerBoardStore(directory: directory)
            XCTAssertNil(restored.error, "Version \(version) should still load")
            XCTAssertEqual(restored.items, expectedItems)
            XCTAssertTrue(restored.items.allSatisfy { $0.borderColor == nil && $0.borderColorHex == "#FFFFFF" })
            XCTAssertEqual(restored.viewport, version == 1 ? StickerCanvasViewport() : source.viewport)
            XCTAssertEqual(try Data(contentsOf: documentURL), legacy, "Loading must not eagerly rewrite metadata")
            XCTAssertEqual(try Data(contentsOf: imageURL), cutout.pngData)
        }
    }

    @MainActor func testPerStickerBorderColorsAndStylesSurviveReloadAndRemovalUndoWithOriginalPixels() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        let firstID = try XCTUnwrap(store.addSticker(cutout, at: CGPoint(x: 0.2, y: 0.7)))
        let secondID = try XCTUnwrap(store.addSticker(cutout, at: CGPoint(x: 0.8, y: 0.3)))
        var first = try XCTUnwrap(store.items.first { $0.id == firstID })
        first.borderColor = " \n#a1B2c3\t"
        first.borderStyle = .dashed
        store.update(first)
        var second = try XCTUnwrap(store.items.first { $0.id == secondID })
        second.borderColor = "#D05E35"
        second.borderStyle = .solid
        store.update(second)

        XCTAssertEqual(store.items.map(\.borderColor), ["#A1B2C3", "#D05E35"])
        XCTAssertEqual(store.items.map(\.borderColorHex), ["#A1B2C3", "#D05E35"])
        XCTAssertEqual(store.items.map(\.borderStyle), [.dashed, .solid])
        let expectedItems = store.items
        let imageURLs = try store.items.map { try XCTUnwrap(store.imageURL(for: $0)) }
        let restored = StickerBoardStore(directory: directory)
        XCTAssertNil(restored.error)
        XCTAssertEqual(restored.items, expectedItems)

        restored.remove(firstID)
        XCTAssertEqual(restored.items.map(\.id), [secondID])
        XCTAssertTrue(restored.canUndoRemoval)
        for imageURL in imageURLs { XCTAssertEqual(try Data(contentsOf: imageURL), cutout.pngData) }
        restored.undoLastRemoval()
        XCTAssertFalse(restored.canUndoRemoval)
        XCTAssertEqual(restored.items, expectedItems)
        XCTAssertEqual(StickerBoardStore(directory: directory).items, expectedItems)
        for imageURL in imageURLs { XCTAssertEqual(try Data(contentsOf: imageURL), cutout.pngData) }
    }

    @MainActor func testInvalidBorderColorsLoadAsWhiteAndPersistCanonicalFallbackOnEdit() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = StickerBoardStore(directory: directory)
        source.addSticker(cutout)
        let photo = try XCTUnwrap(source.items.first)
        let imageURL = try XCTUnwrap(source.imageURL(for: photo))
        let documentURL = directory.appendingPathComponent("board.json")
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: documentURL)) as? [String: Any])
        var items = try XCTUnwrap(document["items"] as? [[String: Any]])
        let invalidColors = ["", "#FFF", "#12345678", "#GG0000", "123456", "red", "#１２３４５６"]

        for invalidColor in invalidColors {
            items[0]["borderColor"] = invalidColor
            document["items"] = items
            let original = try JSONSerialization.data(withJSONObject: document, options: .sortedKeys)
            try original.write(to: documentURL, options: .atomic)
            let restored = StickerBoardStore(directory: directory)
            XCTAssertNil(restored.error, "An invalid optional color must not make the board unreadable")
            XCTAssertEqual(restored.items.first?.borderColor, "#FFFFFF")
            XCTAssertEqual(restored.items.first?.borderColorHex, "#FFFFFF")
            XCTAssertEqual(try Data(contentsOf: documentURL), original, "Normalization must not eagerly rewrite metadata")

            var edited = try XCTUnwrap(restored.items.first)
            edited.x = 0.25
            edited.borderColor = invalidColor
            restored.update(edited)
            let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: documentURL)) as? [String: Any])
            let savedItems = try XCTUnwrap(saved["items"] as? [[String: Any]])
            XCTAssertEqual(savedItems[0]["borderColor"] as? String, "#FFFFFF")
            XCTAssertEqual(StickerBoardStore(directory: directory).items, restored.items)
            XCTAssertEqual(try Data(contentsOf: imageURL), cutout.pngData)
        }
    }

    @MainActor func testBrokenMetadataIsNotOverwrittenAndCanBeReloadedAfterRecovery() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        store.addText("原来的文字", at: CGPoint(x: 0.5, y: 0.5), color: "#1D1D1F", fontSize: 28)
        let file = directory.appendingPathComponent("board.json")
        let original = try Data(contentsOf: file)
        let broken = Data("broken document".utf8)
        try broken.write(to: file, options: .atomic)
        let reloaded = StickerBoardStore(directory: directory)
        XCTAssertNotNil(reloaded.error)
        XCTAssertNil(reloaded.addSticker(cutout))
        XCTAssertEqual(try Data(contentsOf: file), broken)
        XCTAssertTrue(reloaded.items.isEmpty)
        try original.write(to: file, options: .atomic)
        reloaded.reload()
        XCTAssertNil(reloaded.error)
        XCTAssertEqual(reloaded.items, store.items)
        XCTAssertNotNil(reloaded.addText("恢复后添加", at: CGPoint(x: 0.5, y: 0.5), color: "#1D1D1F", fontSize: 28))
    }

    @MainActor func testMetadataWriteFailureDoesNotPublishOrLeaveANewImage() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        store.addText("已保存", at: CGPoint(x: 0.5, y: 0.5), color: "#1D1D1F", fontSize: 28)
        let original = store.items
        let metadata = directory.appendingPathComponent("board.json")
        try FileManager.default.removeItem(at: metadata)
        // A nonempty directory blocks atomic replacement without requiring filesystem permissions.
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: metadata.appendingPathComponent("sentinel"))
        XCTAssertNil(store.addSticker(cutout))
        XCTAssertEqual(store.items, original)
        XCTAssertNotNil(store.error)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(names.contains { $0.hasSuffix(".png") })
        try FileManager.default.removeItem(at: metadata)
        XCTAssertNotNil(store.addSticker(cutout))
        XCTAssertNil(store.error)
    }

    @MainActor func testWorldCoordinatesRemainUnboundedWithinSafetyLimits() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        store.addText("位置", at: CGPoint(x: -4, y: 9), color: "#1D1D1F", fontSize: 28)
        var item = try XCTUnwrap(store.items.first)
        XCTAssertEqual(item.x, -4)
        XCTAssertEqual(item.y, 9)
        item.scale = .infinity
        item.rotation = .nan
        item.x = .nan
        item.y = -0.2
        store.update(item)
        XCTAssertEqual(store.items.first?.scale, 1)
        XCTAssertEqual(store.items.first?.rotation, 0)
        XCTAssertEqual(store.items.first?.x, 0.5)
        XCTAssertEqual(store.items.first?.y, -0.2)
        item = try XCTUnwrap(store.items.first)
        item.scale = 7
        store.update(item)
        XCTAssertEqual(store.items.first?.scale, 3)
        item.scale = 0.1
        store.update(item)
        XCTAssertEqual(store.items.first?.scale, 0.35)
        item.x = -Double.greatestFiniteMagnitude
        item.y = Double.greatestFiniteMagnitude
        store.update(item)
        XCTAssertEqual(store.items.first?.x, -1_000_000)
        XCTAssertEqual(store.items.first?.y, 1_000_000)
        item.id = UUID()
        store.update(item)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(StickerBoardStore(directory: directory).items, store.items)
    }

    @MainActor func testVersionOneStartsAtOriginAndMigratesWithoutChangingItemsOrPixels() throws {
        struct LegacyDocument: Encodable {
            var version = 1
            var items: [StickerCanvasItem]
        }
        struct SavedDocument: Decodable {
            var version: Int
            var items: [StickerCanvasItem]
            var viewport: StickerCanvasViewport
        }
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var photo = StickerCanvasItem(kind: .image, x: 0.2, y: 0.7)
        photo.imageFile = "\(photo.id.uuidString).png"
        photo.contours = cutout.contours
        let items = [photo, StickerCanvasItem(kind: .text, x: 0.8, y: 0.3, text: "原画布")]
        let imageURL = directory.appendingPathComponent(try XCTUnwrap(photo.imageFile))
        let documentURL = directory.appendingPathComponent("board.json")
        let legacy = try JSONEncoder().encode(LegacyDocument(items: items))
        try cutout.pngData.write(to: imageURL)
        try legacy.write(to: documentURL)

        let store = StickerBoardStore(directory: directory)
        XCTAssertNil(store.error)
        XCTAssertEqual(store.viewport, StickerCanvasViewport())
        XCTAssertEqual(store.items, items)
        XCTAssertEqual(try Data(contentsOf: documentURL), legacy, "Loading must not eagerly rewrite legacy metadata")
        XCTAssertEqual(try Data(contentsOf: imageURL), cutout.pngData)

        let viewport = StickerCanvasViewport(x: -3.75, y: 5.25)
        store.moveViewport(to: viewport)
        let saved = try JSONDecoder().decode(SavedDocument.self, from: Data(contentsOf: documentURL))
        XCTAssertEqual(saved.version, 3)
        XCTAssertEqual(saved.items, items)
        XCTAssertEqual(saved.viewport, viewport)
        XCTAssertEqual(try Data(contentsOf: imageURL), cutout.pngData)
        let restored = StickerBoardStore(directory: directory)
        XCTAssertEqual(restored.items, items)
        XCTAssertEqual(restored.viewport, viewport)
    }

    @MainActor func testFarAwayItemsAndViewportSurviveEveryItemOperationAndRelaunch() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        let viewport = StickerCanvasViewport(x: -120.25, y: 875.75)
        store.moveViewport(to: viewport)
        XCTAssertEqual(StickerBoardStore(directory: directory).viewport, viewport, "An empty board can retain its viewport")
        let photoID = try XCTUnwrap(store.addSticker(cutout, at: CGPoint(x: -119.5, y: 876.25)))
        let textID = try XCTUnwrap(store.addText("远处的记忆", at: CGPoint(x: -120.1, y: 875.9), color: "#FFFFFF", fontSize: 34))
        var photo = try XCTUnwrap(store.items.first { $0.id == photoID })
        photo.x = 249_999.5
        photo.y = -500_000.25
        photo.borderStyle = .dashed
        store.update(photo)
        store.bringToFront(photoID)
        store.remove(photoID)
        store.undoLastRemoval()

        XCTAssertNil(store.error)
        XCTAssertEqual(store.items.map(\.id), [textID, photoID])
        XCTAssertEqual(store.items.last?.x, photo.x)
        XCTAssertEqual(store.items.last?.y, photo.y)
        XCTAssertEqual(store.viewport, viewport)
        let restored = StickerBoardStore(directory: directory)
        XCTAssertEqual(restored.items, store.items)
        XCTAssertEqual(restored.viewport, viewport)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(restored.imageURL(for: photo))), cutout.pngData)
    }

    @MainActor func testViewportRejectsNonfiniteValuesAndLimitsExtremeFiniteCoordinates() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        let original = StickerCanvasViewport(x: 7.5, y: -8.25)
        store.moveViewport(to: original)
        let documentURL = directory.appendingPathComponent("board.json")
        let saved = try Data(contentsOf: documentURL)
        let invalidPositions = [
            StickerCanvasViewport(x: .nan, y: 12),
            StickerCanvasViewport(x: 12, y: .nan),
            StickerCanvasViewport(x: .infinity, y: 12),
            StickerCanvasViewport(x: 12, y: -.infinity)
        ]
        for position in invalidPositions {
            store.moveViewport(to: position)
            XCTAssertEqual(store.viewport, original)
            XCTAssertNotNil(store.error)
            XCTAssertEqual(try Data(contentsOf: documentURL), saved)
        }
        store.moveViewport(to: StickerCanvasViewport(x: Double.greatestFiniteMagnitude, y: -Double.greatestFiniteMagnitude))
        let bounded = StickerCanvasViewport(x: 1_000_000, y: -1_000_000)
        XCTAssertEqual(store.viewport, bounded)
        XCTAssertNil(store.error)
        XCTAssertEqual(StickerBoardStore(directory: directory).viewport, bounded)
    }

    @MainActor func testViewportWriteFailureKeepsLastSavedStateAndCanBeRetried() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        XCTAssertNotNil(store.addSticker(cutout))
        let originalViewport = StickerCanvasViewport(x: -2, y: 3)
        store.moveViewport(to: originalViewport)
        let originalItems = store.items
        let imageURL = try XCTUnwrap(store.imageURL(for: XCTUnwrap(store.items.first)))
        let metadata = directory.appendingPathComponent("board.json")
        try FileManager.default.removeItem(at: metadata)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        let sentinel = metadata.appendingPathComponent("sentinel")
        try Data("keep".utf8).write(to: sentinel)

        let next = StickerCanvasViewport(x: 101, y: -202)
        store.moveViewport(to: next)
        XCTAssertEqual(store.viewport, originalViewport)
        XCTAssertEqual(store.items, originalItems)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
        XCTAssertEqual(try Data(contentsOf: imageURL), cutout.pngData)

        try FileManager.default.removeItem(at: metadata)
        store.moveViewport(to: next)
        XCTAssertNil(store.error)
        XCTAssertEqual(store.viewport, next)
        let restored = StickerBoardStore(directory: directory)
        XCTAssertEqual(restored.items, originalItems)
        XCTAssertEqual(restored.viewport, next)
        XCTAssertEqual(try Data(contentsOf: imageURL), cutout.pngData)
    }

    @MainActor func testUnsafeImagePathsAreNeverResolved() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        var item = StickerCanvasItem(kind: .image)
        item.imageFile = "../../other.png"
        XCTAssertNil(store.imageURL(for: item))
        item.imageFile = "/tmp/\(UUID().uuidString).png"
        XCTAssertNil(store.imageURL(for: item))
    }
}
