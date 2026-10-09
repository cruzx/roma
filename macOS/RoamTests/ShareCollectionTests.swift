import XCTest
@testable import Roam

final class ShareCollectionTests: XCTestCase {
    func testInboxKeepsMultipleSharesAndAcknowledgesOne() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = CollectedNote(title: "小红书攻略", text: "周末路线 https://xhslink.com/example")
        let second = CollectedNote(title: "另一篇", text: "第二份分享")
        try ShareBridge.save(first, at: folder); try ShareBridge.save(second, at: folder)
        try ShareBridge.publish([], at: folder)
        XCTAssertEqual(Set(ShareBridge.pending(at: folder).map(\.id)), Set([first.id, second.id]))
        try ShareBridge.remove(first.id, at: folder)
        XCTAssertEqual(ShareBridge.pending(at: folder).map(\.id), [second.id])
        XCTAssertThrowsError(try ShareBridge.save(CollectedNote(title: "空", text: " \n"), at: folder))
    }
    @MainActor func testArchiveIsIdempotentAndPersistsOriginalText() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("trips.json")
        let store = TravelStore(file: file, reset: true)
        let trip = try XCTUnwrap(store.trips.first)
        let day = try XCTUnwrap(trip.days.first)
        let note = CollectedNote(title: "收藏攻略", text: "分享原文\nhttps://xhslink.com/example", tripID: trip.id, dayID: day.id)
        XCTAssertTrue(store.importCollectedNote(note, tripID: trip.id, dayID: day.id))
        XCTAssertTrue(store.importCollectedNote(note, tripID: trip.id, dayID: day.id))
        let restored = TravelStore(file: file)
        let items = restored.trips[0].days[0].items.filter { $0.id == note.id }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].category, .notes)
        XCTAssertEqual(items[0].detail, note.text)
        XCTAssertFalse(store.importCollectedNote(note, tripID: UUID(), dayID: UUID()))
    }
}
