import XCTest
import CoreLocation
@testable import Roam

final class TodayAndSearchTests: XCTestCase {
    @MainActor func testTodayUsesCalendarBoundariesAndExcludesInactiveTrips() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var trip = TravelStore.samples[0]
        trip.startDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 23, minute: 30))!
        trip.status = .planning
        XCTAssertEqual(trip.dayIndex(on: calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 0))!, calendar: calendar), 0)
        XCTAssertEqual(trip.dayIndex(on: calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 0))!, calendar: calendar), 1)
        XCTAssertNil(trip.dayIndex(on: calendar.date(byAdding: .day, value: -1, to: trip.startDate)!, calendar: calendar))
        XCTAssertNil(trip.dayIndex(on: calendar.date(byAdding: .day, value: trip.days.count, to: trip.startDate)!, calendar: calendar))
        trip.status = .completed
        XCTAssertNil(trip.dayIndex(on: trip.startDate, calendar: calendar))
        trip.status = .wish
        XCTAssertNil(trip.dayIndex(on: trip.startDate, calendar: calendar))
    }
    @MainActor func testCustomBackgroundAndResetPersistWithoutChangingTrips() {
        let store = HomeBackgroundStore(testing: true, reset: true)
        let photo = Data([1, 2, 3, 4])
        store.select(photo: photo)
        XCTAssertEqual(HomeBackgroundStore(testing: true).selection.photo, photo)
        store.select(asset: "bg-fuji")
        let restored = HomeBackgroundStore(testing: true)
        XCTAssertEqual(restored.selection.asset, "bg-fuji")
        XCTAssertNil(restored.selection.photo)
        store.select()
        XCTAssertNil(HomeBackgroundStore(testing: true).selection.asset)
    }
    func testJapaneseStationAndCityQueries() {
        for query in ["东京车站", "东京站", "東京駅", "Tokyo Station"] {
            XCTAssertTrue(PlaceSearchTerms.isStation(query))
            XCTAssertEqual(PlaceSearchTerms.stationBase(query, country: "JP"), "東京")
        }
        XCTAssertEqual(PlaceSearchTerms.local("日本桥", country: "JP"), "日本橋")
        XCTAssertEqual(PlaceSearchTerms.city("日本 东京9天规划", country: "JP"), "Tokyo")
    }
    @MainActor func testLiveTokyoStationSearchReturnsActualStation() async throws {
        let model = PlaceSearchModel()
        await model.configure("日本 东京9天规划")
        XCTAssertNotNil(model.area, model.message ?? "")
        await model.search("东京车站")
        let station = try XCTUnwrap(model.places.first(where: { $0.name == "東京駅" || $0.name == "东京站" || $0.name == "东京车站" }), model.message ?? "No station")
        let distance = CLLocation(latitude: station.latitude, longitude: station.longitude).distance(from: CLLocation(latitude: 35.681236, longitude: 139.767125))
        XCTAssertLessThan(distance, 600)
    }
}
