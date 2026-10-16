import XCTest
@testable import Roam
final class AccountPhotoTests: XCTestCase {
    func testMetadataStripsAllEmbeddedMediaAndRestoresFromCache() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let codec = AccountPhotoCodec(directory: folder)
        var item = PlanItem(title: "照片", category: .notes)
        item.photos = [Data([1,2]), Data([3,4])]
        item.linkPreview = LinkPreview(originalURL: URL(string: "https://example.com")!, title: "链接", imageData: Data([5,6]))
        let trip = Trip(destination: "东京", country: "日本", startDate: Date(), cover: "", coverPhoto: Data([7,8]), days: [TravelDay(items: [item])])
        let metadata = try codec.metadata(trip)
        XCTAssertNil(metadata.coverPhoto)
        XCTAssertNil(metadata.days[0].items[0].photos)
        XCTAssertNil(metadata.days[0].items[0].linkPreview?.imageData)
        XCTAssertEqual(AccountPhotoCodec.references(metadata).count, 4)
        var ledger = CloudLedger(); ledger.capture([metadata]); try ledger.library.validateAccountPayload()
        let restored = codec.hydrated(metadata)
        XCTAssertEqual(restored.coverPhoto, trip.coverPhoto)
        XCTAssertEqual(restored.days[0].items[0].photos, item.photos)
        XCTAssertEqual(restored.days[0].items[0].linkPreview?.imageData, item.linkPreview?.imageData)
        XCTAssertEqual(try codec.metadata(restored), metadata)
    }
    func testUnavailablePhotosSurviveTextEditAndReserialization() throws {
        let codec = AccountPhotoCodec(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let key = String(repeating: "a", count: 64)
        var trip = Trip(destination: "东京", country: "日本", startDate: Date(), cover: "", coverPhotoReference: key, days: [])
        trip = codec.hydrated(trip); trip.destination = "改文字"
        XCTAssertNil(trip.coverPhoto)
        XCTAssertEqual(try codec.metadata(trip).coverPhotoReference, key)
    }
    func testExplicitPhotoRemovalClearsReference() throws {
        let codec = AccountPhotoCodec(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let trip = Trip(destination: "东京", country: "日本", startDate: Date(), cover: "", days: [TravelDay(items: [PlanItem(title: "移除", category: .notes, photos: [])])])
        XCTAssertEqual(try codec.metadata(trip).days[0].items[0].photoReferences, [])
    }
    func testAccountPayloadRejectsInlinePhotosAndUnsafeReferences() {
        var trip = Trip(destination: "东京", country: "日本", startDate: Date(), cover: "", coverPhoto: Data([1]), days: [])
        var ledger = CloudLedger(); ledger.capture([trip])
        XCTAssertThrowsError(try ledger.library.validateAccountPayload())
        trip.coverPhoto = nil; trip.coverPhotoReference = "../../outside"; ledger.capture([trip])
        XCTAssertThrowsError(try ledger.library.validateAccountPayload())
    }
    func testTrashAlsoRejectsEmbeddedPhotos() {
        let trip = Trip(destination: "东京", country: "日本", startDate: Date(), cover: "", coverPhoto: Data([1]), days: [])
        var ledger = CloudLedger(); ledger.capture([], trash: [DeletedTrip(trip: trip, deletedAt: Date())])
        XCTAssertThrowsError(try ledger.library.validateAccountPayload())
    }
}
