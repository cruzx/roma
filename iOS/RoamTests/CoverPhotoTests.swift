import XCTest
import UIKit
@testable import Roam

final class CoverPhotoTests: XCTestCase {
    @MainActor func testPhotoResizesAndSurvivesCloudRoundTrip() throws {
        let original = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1800)).jpegData(withCompressionQuality: 1) { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1800))
        }
        let data = try CoverPhotoCodec.compress(original)
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 1600)
        var trip = TravelStore.samples[0]; trip.coverPhoto = data
        var ledger = CloudLedger(); ledger.capture([trip])
        let remote = try JSONDecoder().decode(CloudLibrary.self, from: JSONEncoder().encode(ledger.library))
        var receiver = CloudLedger(); receiver.merge(remote)
        XCTAssertEqual(receiver.library.visible.first?.coverPhoto, data)
        var legacy = trip; legacy.coverPhoto = nil
        XCTAssertNil(try JSONDecoder().decode(Trip.self, from: JSONEncoder().encode(legacy)).coverPhoto)
    }
    func testInvalidPhotoRejected() {
        XCTAssertThrowsError(try CoverPhotoCodec.compress(Data("not an image".utf8)))
    }
}
