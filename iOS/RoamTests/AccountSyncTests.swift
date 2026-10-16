import XCTest
@testable import Roam

final class AccountSyncTests: XCTestCase {
    func testAcknowledgeDoesNotDropEditsMadeDuringUpload() {
        var trip = Trip(destination: "东京", country: "日本", startDate: Date(), cover: "", days: [TravelDay()])
        var ledger = CloudLedger(); ledger.capture([trip])
        let uploading = ledger.library
        trip.destination = "离线后续修改"; ledger.capture([trip])
        ledger.acknowledge(uploading)
        XCTAssertTrue(ledger.pending.contains(trip.id.uuidString))
        XCTAssertEqual(ledger.library.visible.first?.destination, "离线后续修改")
    }
    func testAcknowledgeClearsOnlyConfirmedRevision() {
        let trip = Trip(destination: "东京", country: "日本", startDate: Date(), cover: "", days: [])
        var ledger = CloudLedger(); ledger.capture([trip]); ledger.acknowledge(ledger.library)
        XCTAssertTrue(ledger.pending.isEmpty); XCTAssertFalse(ledger.orderPending)
    }
    func testRejectsMismatchedTripIdentifier() {
        let trip = Trip(destination: "东京", country: "日本", startDate: Date(), cover: "", days: [])
        var library = CloudLibrary(); library.trips[UUID().uuidString] = CloudTripVersion(trip: trip)
        XCTAssertThrowsError(try library.validateAccountPayload())
    }
    func testRejectsNewerSchemaAndDuplicateOrder() {
        var library = CloudLibrary(); library.schema = 2
        XCTAssertThrowsError(try library.validateAccountPayload())
        library.schema = 1; library.order = ["same", "same"]
        XCTAssertThrowsError(try library.validateAccountPayload())
    }
    func testCorruptPayloadCannotBecomeEmptyLibrary() {
        let document = AccountDocument(revision: 4, payload: "invalid base64")
        XCTAssertThrowsError(try document.decode(CloudLibrary.self))
    }
    func testLocalDocumentRoundTripPreservesImagesAndDeletionHistory() throws {
        var trip = Trip(destination: "东京", country: "日本", startDate: Date(), cover: "", days: [])
        trip.coverPhoto = Data([1,2,3,4])
        var ledger = CloudLedger(); ledger.capture([trip])
        let document = AccountDocument(revision: 9, payload: try JSONEncoder().encode(ledger.library).base64EncodedString())
        XCTAssertEqual(try document.decode(CloudLibrary.self).visible, [trip])
        ledger.capture([])
        let deleted = AccountDocument(revision: 10, payload: try JSONEncoder().encode(ledger.library).base64EncodedString())
        XCTAssertNil(try deleted.decode(CloudLibrary.self).trips[trip.id.uuidString]?.trip)
    }
    @MainActor func testMissingConfigurationFailsClosed() async {
        let account = AccountService(configuration: [:])
        XCTAssertFalse(account.configured)
        do { try await account.sendCode(email: "example@example.com"); XCTFail("must not contact an unconfigured service") }
        catch { XCTAssertTrue(error is AccountError) }
    }
    @MainActor func testRejectsUnencryptedEndpoint() {
        let account = AccountService(configuration: ["URL":"http://example.com", "PublishableKey":"public"])
        XCTAssertFalse(account.configured)
    }
    @MainActor func testMigrationRejectsUnsafeAccountPath() {
        XCTAssertThrowsError(try AccountWorkspace.prepare(user: "../../outside", trips: [], trash: [], importLocal: false))
    }
    @MainActor func testEmailCannotSendBeforeSMTPIsReady() async {
        let service = AccountService(configuration: ["URL":"https://example.com", "PublishableKey":"public", "EmailLoginReady":"false"])
        XCTAssertTrue(service.configured)
        XCTAssertFalse(service.emailLoginReady)
        do { try await service.sendCode(email: "test@example.com"); XCTFail("Email must be gated") }
        catch { guard case AccountError.emailNotReady = error else { return XCTFail("Unexpected error") } }
    }

    @MainActor func testAutomaticImportNeverCopiesAnotherAccountsLibrary() {
        XCTAssertTrue(AccountWorkspace.shouldImportLocal(currentOwner: nil, firstImportOwner: nil, user: "A"))
        XCTAssertTrue(AccountWorkspace.shouldImportLocal(currentOwner: nil, firstImportOwner: "A", user: "A"))
        XCTAssertFalse(AccountWorkspace.shouldImportLocal(currentOwner: nil, firstImportOwner: "A", user: "B"))
        XCTAssertFalse(AccountWorkspace.shouldImportLocal(currentOwner: "A", firstImportOwner: nil, user: "B"))
        XCTAssertFalse(AccountWorkspace.shouldImportLocal(currentOwner: "A", firstImportOwner: "A", user: "A"))
    }

}
