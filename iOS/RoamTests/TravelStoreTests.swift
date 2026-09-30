import XCTest
@testable import Roam

final class TravelStoreTests: XCTestCase {
    func testTransportNumberSurvivesJSONAndOlderItemsStillDecode() throws {
        var flight = PlanItem(title: "广州 → 东京", category: .transport)
        flight.transportMode = .flight
        flight.transportNumber = "CA1234"
        let encoded = try JSONEncoder().encode(flight)
        let restored = try JSONDecoder().decode(PlanItem.self, from: encoded)
        XCTAssertEqual(restored.transportMode, .flight)
        XCTAssertEqual(restored.transportNumber, "CA1234")
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "transportMode")
        legacy.removeValue(forKey: "transportNumber")
        let olderItem = try JSONDecoder().decode(PlanItem.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(olderItem.transportMode)
        XCTAssertNil(olderItem.transportNumber)
    }
    @MainActor func testMoveItemKeepsIdentityAndDoesNotDuplicate() async {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = TravelStore(file: file, reset: true)
        let trip = store.trips[0]
        let original = trip.days[0].items[0]
        var changed = original; changed.title = "Moved reservation"
        store.upsert(changed, tripID: trip.id, from: trip.days[0].id, to: trip.days[2].id)
        XCTAssertFalse(store.trips[0].days[0].items.contains { $0.id == original.id })
        XCTAssertEqual(store.trips[0].days[2].items.first { $0.id == original.id }?.title, changed.title)
        XCTAssertEqual(store.trips[0].days.flatMap(\.items).filter { $0.id == original.id }.count, 1)
        let reloaded = TravelStore(file: file)
        XCTAssertEqual(reloaded.trips, store.trips)
    }

    @MainActor func testMultipleNightsUseIndependentIDsAndDeleteIsScoped() async {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = TravelStore(file: file, reset: true)
        let trip = store.trips[0]
        let stay = PlanItem(title: "Three nights", category: .stay)
        store.upsert(stay, tripID: trip.id, from: nil, to: trip.days[1].id, through: trip.days[3].id)
        let copies = store.trips[0].days.flatMap(\.items).filter { $0.title == "Three nights" }
        XCTAssertEqual(copies.count, 3)
        XCTAssertEqual(Set(copies.map(\.id)).count, 3)
        store.removeItem(stay.id, tripID: trip.id, dayID: trip.days[1].id)
        XCTAssertEqual(store.trips[0].days.flatMap(\.items).filter { $0.title == "Three nights" }.count, 2)
        XCTAssertEqual(TravelStore(file: file).trips, store.trips)
    }

    @MainActor func testTripDatesCrossMonthBoundary() async {
        let trip = TravelStore.samples[0]
        let final = Calendar.current.dateComponents([.month, .day], from: trip.date(for: 8))
        XCTAssertEqual(final.month, 11)
        XCTAssertEqual(final.day, 1)
        XCTAssertEqual(trip.days.count, 9)
    }
    @MainActor func testLegacyTripsDecodeWithoutMapFields() throws {
        let trips = TravelStore.samples
        let data = try JSONEncoder().encode(trips)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        for t in json.indices {
            var days = json[t]["days"] as! [[String: Any]]
            for d in days.indices {
                days[d].removeValue(forKey: "routeOrder")
                var items = days[d]["items"] as! [[String: Any]]
                for i in items.indices { items[i].removeValue(forKey: "place") }
                days[d]["items"] = items
            }
            json[t]["days"] = days
        }
        let decoded = try JSONDecoder().decode([Trip].self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, trips)
    }

    @MainActor func testMapLocationAndRouteOrderPersistAfterMovingItems() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = TravelStore(file: file, reset: true)
        var trip = store.trips[0]
        let a = PlanItem(title: "A", category: .explore, place: PlanPlace(name: "A place", address: "Address", latitude: 35.68, longitude: 139.76))
        let b = PlanItem(title: "B", category: .food, place: PlanPlace(name: "B place", address: "", latitude: 35.67, longitude: 139.77))
        trip.days[0].items += [a, b]
        trip.days[0].routeOrder = [b.id, UUID(), a.id, b.id]
        store.update(trip)
        XCTAssertEqual(store.trips[0].days[0].routeItems.map(\.id), [b.id, a.id])
        XCTAssertEqual(TravelStore(file: file).trips[0].days[0].routeItems, [b, a])
        store.upsert(b, tripID: trip.id, from: trip.days[0].id, to: trip.days[1].id)
        XCTAssertEqual(store.trips[0].days[0].routeItems, [a])
        XCTAssertEqual(store.trips[0].days[1].routeItems, [b])
        XCTAssertEqual(TravelStore(file: file).trips, store.trips)
    }

    @MainActor func testMultipleWaypointsFlattenAndPreserveRouteSelection() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = TravelStore(file: file, reset: true)
        var trip = store.trips[0]
        let points = (0..<3).map { PlanWaypoint(place: PlanPlace(name: "Stop \($0)", address: "", latitude: 35 + Double($0) / 100, longitude: 139)) }
        let multi = PlanItem(title: "Three stops", category: .stay, places: points)
        trip.days[0].items = [multi]
        trip.days[0].routeOrder = [points[2].id, points[0].id, points[1].id]
        trip.days[0].excludedRouteIDs = [points[0].id]
        store.update(trip)
        let loaded = TravelStore(file: file).trips[0].days[0]
        XCTAssertEqual(loaded.routeItems.map(\.id), [points[2].id, points[0].id, points[1].id])
        XCTAssertEqual(loaded.routeItems.filter { !(loaded.excludedRouteIDs ?? []).contains($0.id) }.map(\.id), [points[2].id, points[1].id])
        store.upsert(multi, tripID: trip.id, from: trip.days[0].id, to: trip.days[0].id, through: trip.days[1].id)
        let copied = try XCTUnwrap(store.trips[0].days[1].items.last)
        XCTAssertEqual(copied.mapPlaces.map(\.place), points.map(\.place))
        XCTAssertTrue(Set(copied.mapPlaces.map(\.id)).isDisjoint(with: points.map(\.id)))
        let old = PlanItem(title: "Legacy", category: .food, place: points[0].place)
        let decoded = try JSONDecoder().decode(PlanItem.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(decoded.mapPlaces, [PlanWaypoint(id: old.id, place: points[0].place)])
    }

    @MainActor func testTokyoSearchReturnsJapanesePlacesForChineseQueries() async throws {
        XCTAssertEqual(PlaceSearchModel.countryCode(for: "日本 东京"), "JP")
        let model = PlaceSearchModel()
        await model.configure("日本 东京")
        let area = try XCTUnwrap(model.area)
        XCTAssertEqual(area.region.center.latitude, 35.68, accuracy: 0.3)
        XCTAssertEqual(area.region.center.longitude, 139.76, accuracy: 0.3)
        for query in ["池袋", "日本桥", "银座"] {
            model.invalidate()
            await model.suggest(query)
            XCTAssertFalse(model.places.isEmpty, query)
            for place in model.places {
                XCTAssertTrue(place.address.contains("日本"), place.address)
                XCTAssertEqual(place.latitude, 35.68, accuracy: 0.6)
                XCTAssertEqual(place.longitude, 139.76, accuracy: 0.7)
            }
        }
    }

    @MainActor func testTripReorderingPersistsAndKeepsEveryStatus() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = TravelStore(file: file, reset: true)
        let original = store.trips
        let first = original[0].id, last = original.last!.id
        XCTAssertTrue(store.reorderTrip(first, onto: last))
        XCTAssertEqual(store.trips.last?.id, first)
        XCTAssertEqual(store.trips.map(\.id), Array(original.dropFirst().map(\.id)) + [first])
        XCTAssertEqual(TravelStore(file: file).trips, store.trips)
        XCTAssertTrue(store.reorderTrip(first, onto: store.trips[0].id))
        XCTAssertEqual(store.trips, original)
        XCTAssertFalse(store.reorderTrip(first, onto: first))
        XCTAssertFalse(store.reorderTrip(UUID(), onto: first))
        XCTAssertEqual(store.trips, original)
    }

    @MainActor func testTrashPersistsRestoresExactTripAndExpiresAtThirtyDays() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("trips.json")
        let store = TravelStore(file: file, reset: true)
        let trip = store.trips[0]
        let now = Date()
        store.deleteTrip(trip.id, now: now)
        XCTAssertFalse(store.trips.contains { $0.id == trip.id })
        XCTAssertEqual(store.deletedTrips.first?.trip, trip)
        let loaded = TravelStore(file: file)
        XCTAssertEqual(loaded.deletedTrips.first?.trip, trip)
        loaded.restoreTrip(trip.id, now: now.addingTimeInterval(29 * 86400))
        XCTAssertEqual(loaded.trips.first, trip)
        XCTAssertTrue(loaded.deletedTrips.isEmpty)
        loaded.deleteTrip(trip.id, now: now)
        loaded.restoreTrip(trip.id, now: now.addingTimeInterval(30 * 86400))
        XCTAssertFalse(loaded.trips.contains { $0.id == trip.id })
        XCTAssertTrue(loaded.deletedTrips.isEmpty)
        XCTAssertTrue(TravelStore(file: file).deletedTrips.isEmpty)
    }

    @MainActor func testPermanentDeletionOnlyRemovesSelectedTrashEntry() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TravelStore(file: folder.appendingPathComponent("trips.json"), reset: true)
        let first = store.trips[0], second = store.trips[1]
        store.deleteTrip(first.id); store.deleteTrip(second.id)
        store.permanentlyDeleteTrip(first.id)
        XCTAssertEqual(store.deletedTrips.map(\.id), [second.id])
        XCTAssertFalse(store.trips.contains { $0.id == first.id })
    }

    @MainActor func testReorderDaysPreservesPlansAndReassignsDates() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("trips.json")
        let store = TravelStore(file: file, reset: true)
        let original = store.trips[0]
        let day = original.days[0]
        XCTAssertTrue(store.reorderDay(day.id, onto: original.days[2].id, tripID: original.id))
        let updated = store.trips[0]
        XCTAssertEqual(updated.days[2], day)
        XCTAssertEqual(updated.days[0], original.days[1])
        XCTAssertEqual(updated.date(for: 2), original.date(for: 2))
        XCTAssertEqual(updated.itemCount, original.itemCount)
        XCTAssertEqual(updated.days.count, original.days.count)
        XCTAssertEqual(TravelStore(file: file).trips[0], updated)
        XCTAssertFalse(store.reorderDay(day.id, onto: day.id, tripID: original.id))
    }

}
