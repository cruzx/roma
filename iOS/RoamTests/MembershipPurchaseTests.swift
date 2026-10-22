import XCTest
import StoreKit
import StoreKitTest
@testable import Roam

@MainActor final class MembershipPurchaseTests: XCTestCase {
    private func session() throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Membership", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }
    func testPurchaseAndRestoreRequireNoEmailOrCloudConfiguration() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let account = AccountService(configuration: [:])
        let store = MembershipStore(account: account, purchaseProduct: { product in
            _ = try await session.buyProduct(identifier: product.id)
            let result = await Transaction.latest(for: product.id)
            return .success(try XCTUnwrap(result))
        })
        print("MEMBERSHIP: load")
        await store.load()
        print("MEMBERSHIP: loaded")
        XCTAssertNotNil(store.product)
        XCTAssertNil(account.session)
        XCTAssertFalse(account.configured)
        print("MEMBERSHIP: purchase")
        await store.purchase()
        print("MEMBERSHIP: purchased")
        XCTAssertTrue(store.purchased, store.message)
        XCTAssertFalse(store.active, "Apple purchase must not bypass server authorization for private data")
        XCTAssertNil(account.session)
        // A fresh membership store reads/restores the Apple entitlement without registering.
        var restoredAppStore = false
        let restored = MembershipStore(account: account, synchronizeAppStore: { restoredAppStore = true })
        await restored.load()
        XCTAssertTrue(restored.purchased, restored.message)
        print("MEMBERSHIP: restore")
        await restored.restore()
        print("MEMBERSHIP: restored")
        XCTAssertTrue(restored.purchased, restored.message)
        XCTAssertTrue(restoredAppStore)
        XCTAssertNil(account.session)
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == MembershipStore.productID {
                XCTAssertNil(transaction.appAccountToken)
            }
        }
    }
    func testRefundRemovesAppleEntitlementWhenSignedOut() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let transaction = try await session.buyProduct(identifier: MembershipStore.productID)
        let store = MembershipStore(account: AccountService(configuration: [:]))
        await store.load()
        XCTAssertTrue(store.purchased)
        try session.refundTransaction(identifier: UInt(transaction.id))
        await store.load()
        XCTAssertFalse(store.purchased)
        XCTAssertFalse(store.active)
    }
}
