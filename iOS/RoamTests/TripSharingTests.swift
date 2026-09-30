import XCTest
@testable import Roam

final class TripSharingTests: XCTestCase {
    @MainActor func testPackageRoundTripPreservesPlanAndMakesIndependentCopy() throws {
        var trip = TravelStore.samples[0]
        trip.coverPhoto = Data([1, 2, 3])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".roamtrip")
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder().encode(TripPackage(trip: trip)).write(to: url)
        let package = try TripPackage.read(url)
        XCTAssertEqual(package.trip, trip)
        let copy = package.importedCopy()
        XCTAssertNotEqual(copy.id, trip.id)
        XCTAssertEqual(copy.days, trip.days)
        XCTAssertEqual(copy.coverPhoto, trip.coverPhoto)
    }
    @MainActor func testUnsupportedAndMalformedFilesAreRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".roamtrip")
        defer { try? FileManager.default.removeItem(at: url) }
        var package = TripPackage(trip: TravelStore.samples[0]); package.version = 99
        try JSONEncoder().encode(package).write(to: url)
        XCTAssertThrowsError(try TripPackage.read(url))
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try TripPackage.read(url))
    }
}
