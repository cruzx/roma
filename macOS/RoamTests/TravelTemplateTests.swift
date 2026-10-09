import XCTest
import UIKit
@testable import Roam

final class TravelTemplateTests: XCTestCase {
    func testBundledCatalogContainsAllDestinationsAndCompleteDays() throws {
        let templates = try TravelTemplateCatalog.result.get()
        XCTAssertEqual(Set(templates.map(\.destination)), Set(["北京", "上海", "广州", "京都", "神户", "富士山", "纽约", "巴黎", "伦敦", "大连"]))
        XCTAssertEqual(Set(templates.map(\.id)).count, 10)
        XCTAssertEqual(templates.reduce(0) { $0 + $1.days.count }, 36)
        for template in templates {
            XCTAssertFalse(template.cover.isEmpty)
            XCTAssertNotNil(UIImage(named: template.cover), template.destination + "缺少封面资源")
            XCTAssertNotNil(template.coverCredit)
            XCTAssertFalse(template.sources.isEmpty)
            XCTAssertTrue(template.sources.allSatisfy { $0.url.scheme == "https" })
            for day in template.days {
                XCTAssertFalse(day.title.isEmpty)
                XCTAssertEqual(Set(day.items.map(\.category)), Set(PlanCategory.allCases.filter { $0 != .expense }))
                XCTAssertTrue(day.items.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
            }
        }
    }

    func testLandmarkPhotosHaveBundledPreviewsAndAttribution() throws {
        let templates = try TravelTemplateCatalog.result.get()
        for template in templates {
            let photos = template.days.flatMap(\.items).compactMap(\.photo)
            XCTAssertFalse(photos.isEmpty, template.destination)
            for photo in photos {
                let full = try XCTUnwrap(UIImage(named: photo.asset), photo.asset)
                let thumbnail = try XCTUnwrap(UIImage(named: photo.thumbnail), photo.thumbnail)
                XCTAssertGreaterThan(max(full.size.width, full.size.height), 500)
                XCTAssertLessThanOrEqual(max(thumbnail.size.width, thumbnail.size.height), 400)
                XCTAssertFalse(photo.title.isEmpty)
                XCTAssertFalse(photo.author.isEmpty)
                XCTAssertFalse(photo.license.isEmpty)
                XCTAssertEqual(photo.sourceURL.scheme, "https")
                XCTAssertTrue(["https", "http"].contains(photo.licenseURL.scheme ?? ""))
            }
            let trip = template.makeTrip(startDate: Date())
            XCTAssertEqual(trip.days.flatMap(\.items).compactMap(\.photo), photos)
            XCTAssertEqual(try JSONDecoder().decode(Trip.self, from: JSONEncoder().encode(trip)), trip)
        }
    }

    func testExistingPlansWithoutBundledPhotosStillDecode() throws {
        let item = PlanItem(title: "原来的行程", detail: "内容不变", category: .explore)
        let data = try JSONEncoder().encode(item)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["photo"])
        let decoded = try JSONDecoder().decode(PlanItem.self, from: data)
        XCTAssertEqual(decoded, item)
        XCTAssertNil(decoded.photo)
    }

    func testCreationUsesChosenDateAndIndependentIdentities() throws {
        let template = try XCTUnwrap(TravelTemplateCatalog.result.get().first)
        let date = Trip.date("2027-12-30")
        let first = template.makeTrip(startDate: date)
        var second = template.makeTrip(startDate: date)
        XCTAssertEqual(first.startDate, Calendar.current.startOfDay(for: date))
        XCTAssertEqual(first.date(for: 3), Trip.date("2028-01-02"))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertTrue(Set(first.days.map(\.id)).isDisjoint(with: second.days.map(\.id)))
        XCTAssertTrue(Set(first.days.flatMap(\.items).map(\.id)).isDisjoint(with: second.days.flatMap(\.items).map(\.id)))
        second.days[0].items[0].title = "My edit"
        XCTAssertNotEqual(first.days[0].items[0].title, second.days[0].items[0].title)
        XCTAssertEqual(template.days[0].items[0].title, first.days[0].items[0].title)
        let encoded = try JSONEncoder().encode(first)
        XCTAssertEqual(try JSONDecoder().decode(Trip.self, from: encoded), first)
        XCTAssertTrue(first.days[0].items.contains { $0.category == .notes && $0.detail.contains(template.sources[0].url.absoluteString) })
    }

    @MainActor func testCopiesPersistWithoutReplacingExistingTrips() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = TravelStore(file: file, reset: true)
        let existing = store.trips
        let template = try XCTUnwrap(TravelTemplateCatalog.result.get().first)
        let copy = template.makeTrip(startDate: Date())
        store.trips.insert(copy, at: 0)
        XCTAssertEqual(Array(store.trips.dropFirst()), existing)
        XCTAssertEqual(TravelStore(file: file).trips, store.trips)
    }
}
