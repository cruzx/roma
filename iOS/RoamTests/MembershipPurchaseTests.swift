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
        // StoreKit delivers refund notifications asynchronously after the test API returns.
        for _ in 0..<40 {
            await store.load()
            if !store.purchased { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(store.purchased)
        XCTAssertFalse(store.active)
    }
    func testCloudLinkRetriesAfterPaymentWithoutAnotherPurchase() async throws {
        let session = try session()
        defer { session.clearTransactions(); MembershipHTTPStub.handler = nil }
        _ = try await session.buyProduct(identifier: MembershipStore.productID)
        let user = UUID().uuidString
        var linked = false
        var failFirstLink = true
        var proofAttempts = 0
        MembershipHTTPStub.handler = { request in
            if request.url!.path.hasSuffix("/verify") {
                return (200, ["access_token":"test-only", "refresh_token":"test-only", "expires_at":Date().timeIntervalSince1970+3600, "user":["id":user,"email":"test@example.invalid"]])
            }
            if request.url!.path.hasSuffix("/roam-membership") {
                var data = request.httpBody ?? Data()
                if data.isEmpty, let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var bytes = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count)) }
                }
                let body = (try? JSONSerialization.jsonObject(with: data)) as? [String:Any] ?? [:]
                if let proof = body["signedTransaction"] as? String, !proof.isEmpty {
                    proofAttempts += 1
                    if failFirstLink { failFirstLink = false; return (503, ["error":"temporary test outage"]) }
                    linked = true
                }
                return (200, ["active":linked])
            }
            return (200, ["active":false])
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MembershipHTTPStub.self]
        let account = AccountService(configuration: ["URL":"https://membership-\(UUID().uuidString).invalid", "PublishableKey":"test-only", "EmailLoginReady":"true"], network: URLSession(configuration: config))
        try await account.verify(email: "test@example.invalid", code: "123456")
        let store = MembershipStore(account: account, purchaseProduct: { _ in XCTFail("Retry must not purchase again"); return .userCancelled })
        do { try await store.requireAccess(); XCTFail("Outage must fail closed") } catch { }
        XCTAssertTrue(store.purchased, "Apple entitlement survives cloud outage")
        XCTAssertFalse(store.active)
        try await store.requireAccess()
        XCTAssertTrue(store.active)
        XCTAssertEqual(proofAttempts, 2)
        try await account.signOut()
    }

}

private final class MembershipHTTPStub: URLProtocol {
    static var handler: ((URLRequest) -> (Int, [String:Any]))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        let (code, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
