import XCTest
@testable import Roam

final class CloudLedgerTests: XCTestCase {
    func makeTrip(_ name: String) -> Trip {
        Trip(destination: name, country: "日本", startDate: Date(timeIntervalSince1970: 1000), cover: "", days: [TravelDay()])
    }
    func settled(_ trips: [Trip]) -> CloudLedger {
        var ledger = CloudLedger(); ledger.capture(trips); ledger.pending = []; ledger.orderPending = false; return ledger
    }
    func testIndependentDeviceEditsMergeWithoutLoss() {
        let a = makeTrip("东京"), b = makeTrip("京都")
        let base = settled([a,b])
        var phone = base, mac = base
        var changedA = a; changedA.days[0].title = "手机编辑"
        var changedB = b; changedB.days[0].title = "Mac 编辑"
        phone.capture([changedA,b]); mac.capture([a,changedB])
        XCTAssertEqual(phone.merge(mac.library), 0)
        XCTAssertEqual(phone.library.visible, [changedA,changedB])
    }
    func testSameTripConflictPreservesBothVersionsOnce() {
        let trip = makeTrip("东京"); let base = settled([trip])
        var phone = base, mac = base
        var a = trip, b = trip; a.days[0].title = "A"; b.days[0].title = "B"
        phone.capture([a]); mac.capture([b])
        XCTAssertEqual(phone.merge(mac.library), 1)
        XCTAssertEqual(Set(phone.library.visible.map { $0.days[0].title }), ["A","B"])
        XCTAssertEqual(phone.merge(mac.library), 0)
        XCTAssertEqual(phone.library.visible.count, 2)
    }
    func testDeletionIsNotResurrectedByUneditedDevice() {
        let trip = makeTrip("东京"); let base = settled([trip])
        var phone = base, mac = base
        phone.capture([])
        XCTAssertEqual(mac.merge(phone.library), 0)
        XCTAssertTrue(mac.library.visible.isEmpty)
    }
    func testDeletionVersusOfflineEditKeepsConflictCopy() {
        let trip = makeTrip("东京"); let base = settled([trip])
        var phone = base, mac = base
        var changed = trip; changed.days[0].title = "离线修改"
        phone.capture([]); mac.capture([changed])
        XCTAssertEqual(mac.merge(phone.library), 1)
        XCTAssertEqual(mac.library.visible.count, 1)
        XCTAssertEqual(mac.library.visible.first?.days[0].title, "离线修改")
        XCTAssertNotEqual(mac.library.visible.first?.id, trip.id)
    }
    func testRemoteSortAndFirstDeviceImport() throws {
        let a = makeTrip("东京"), b = makeTrip("京都")
        var phone = settled([a,b]); phone.capture([b,a])
        var fresh = CloudLedger(); fresh.merge(phone.library)
        XCTAssertEqual(fresh.library.visible, [b,a])
        let restored = try JSONDecoder().decode(CloudLedger.self, from: JSONEncoder().encode(fresh))
        XCTAssertEqual(restored.library.visible, [b,a])
    }
    func testSameContentDoesNotCreateDuplicateConflict() {
        let trip = makeTrip("东京")
        var phone = CloudLedger(), mac = CloudLedger()
        phone.capture([trip]); mac.capture([trip])
        XCTAssertEqual(phone.merge(mac.library), 0)
        XCTAssertEqual(phone.library.visible.count, 1)
    }
    func testTrashAndRestoreSynchronizeWithoutResurrection() throws {
        let trip = makeTrip("东京")
        let entry = DeletedTrip(trip: trip, deletedAt: Date())
        let base = settled([trip])
        var phone = base, mac = base
        phone.capture([], trash: [entry])
        mac.merge(try JSONDecoder().decode(CloudLibrary.self, from: JSONEncoder().encode(phone.library)))
        XCTAssertTrue(mac.library.visible.isEmpty)
        XCTAssertEqual(mac.library.trash, [entry])
        mac.pending = []; mac.orderPending = false
        phone.pending = []; phone.orderPending = false
        phone.capture([trip], trash: [])
        mac.merge(phone.library)
        XCTAssertEqual(mac.library.visible, [trip])
        XCTAssertTrue(mac.library.trash.isEmpty)
        phone.pending = []; phone.orderPending = false
        phone.capture([], trash: [entry])
        phone.pending = []; phone.orderPending = false
        phone.capture([], trash: [])
        mac.merge(phone.library)
        XCTAssertTrue(mac.library.visible.isEmpty)
        XCTAssertTrue(mac.library.trash.isEmpty)
        XCTAssertNil(mac.library.trips[trip.id.uuidString]?.archived)
    }

}
