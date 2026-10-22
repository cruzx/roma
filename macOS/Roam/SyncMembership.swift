import StoreKit
import SwiftUI

struct SyncMembership: Decodable {
    let complimentary: Bool?
    let active: Bool
    let validUntil: Double?
    var expires: Date? { validUntil.map { Date(timeIntervalSince1970: $0) } }
}

@MainActor final class MembershipStore: ObservableObject {
    static let shared = MembershipStore()
    static let productID = "com.xiangchengjin.roam.sync.annual"
    @Published private(set) var product: Product?
    @Published private(set) var purchased = false
    @Published private(set) var purchaseExpires: Date?
    @Published private(set) var active = false
    @Published private(set) var complimentary = false
    @Published private(set) var expires: Date?
    @Published var message = ""
    @Published private(set) var busy = false
    private var owner: String?
    private let account: AccountService
    private let purchaseProduct: (Product) async throws -> Product.PurchaseResult
    private let synchronizeAppStore: () async throws -> Void
    @Published var showPurchaseIntentAccount = false
    private var intentListener: Task<Void, Never>?
    private var listener: Task<Void, Never>?
    init(account: AccountService? = nil,
         purchaseProduct: @escaping (Product) async throws -> Product.PurchaseResult = { try await $0.purchase() },
         synchronizeAppStore: @escaping () async throws -> Void = { try await AppStore.sync() }) {
        self.account = account ?? AccountService.shared
        self.purchaseProduct = purchaseProduct
        self.synchronizeAppStore = synchronizeAppStore
        intentListener = Task { [weak self] in
            for await intent in PurchaseIntent.intents {
                guard let self, intent.product.id == Self.productID else { continue }
                self.product = intent.product
                self.showPurchaseIntentAccount = true
            }
        }

        listener = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }
                do { try await self.accept(result) } catch { self.message = error.localizedDescription }
            }
        }
    }
    func reset() { owner = nil; active = false; complimentary = false; expires = nil }
    func load() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
            try await updateAppleEntitlements()
            try await refresh()
        } catch { message = error.localizedDescription }
    }
    func refresh(transactionID: String? = nil, signedTransaction: String? = nil) async throws {
        guard let user = account.session?.user.id else { reset(); return }
        if owner != user { reset() }
        do {
            let value = try await account.membership(transactionID: transactionID, signedTransaction: signedTransaction)
            guard account.session?.user.id == user else { reset(); throw AccountError.signedOut }
            owner = user; active = value.active; complimentary = value.complimentary == true; expires = value.expires
        } catch { active = false; complimentary = false; expires = nil; throw error }
    }
    func requireAccess() async throws {
        try await refresh()
        // Workspace reconciliation retries every 30 seconds. If payment succeeded
        // while offline, link its verified Apple entitlement when the server returns.
        if !active, account.session != nil { try await updateAppleEntitlements() }
        guard active else { throw AccountError.membershipRequired }
    }
    private func updateAppleEntitlements() async throws {
        var current: VerificationResult<StoreKit.Transaction>?
        purchased = false; purchaseExpires = nil
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID,
                  transaction.revocationDate == nil,
                  transaction.expirationDate.map({ $0 > Date() }) == true else { continue }
            if current == nil || transaction.expirationDate! > purchaseExpires! {
                current = result; purchased = true; purchaseExpires = transaction.expirationDate
            }
        }
        // Reading/restoring an Apple entitlement never requires an email account.
        // Link to the private cloud workspace only after the user chooses to sign in.
        if let current, account.session != nil { try await link(current) }
    }
    private func link(_ result: VerificationResult<StoreKit.Transaction>) async throws {
        guard case .verified(let transaction) = result else { throw MembershipError.unverified }
        if let token = transaction.appAccountToken,
           token != account.session.flatMap({ UUID(uuidString: $0.user.id) }) {
            throw MembershipError.otherAccount
        }
        try await refresh(transactionID: String(transaction.id), signedTransaction: result.jwsRepresentation)
    }
    private func accept(_ result: VerificationResult<StoreKit.Transaction>) async throws {
        guard case .verified(let transaction) = result else { throw MembershipError.unverified }
        guard transaction.productID == Self.productID else { return }
        // Deliver and finish the verified App Store entitlement even when signed out.
        // A subsequent login retries cloud linking from StoreKit's current entitlements.
        await transaction.finish()
        try await updateAppleEntitlements()
    }
    func purchase() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            guard let product, product.type == .autoRenewable,
                  product.subscription?.subscriptionPeriod.unit == .year,
                  product.subscription?.subscriptionPeriod.value == 1 else { throw MembershipError.unavailable }
            if purchased || active { message = AppLocalization.text("会员已开通，无需重复购买。"); return }
            // New purchases use Apple's identity. No email, session or cloud request is required.
            switch try await purchaseProduct(product) {
            case .success(let result):
                try await accept(result)
                message = account.session == nil ? AppLocalization.text("购买成功。可稍后选择邮箱登录，启用账号云同步。") : AppLocalization.text("购买成功。")
            case .pending: message = AppLocalization.text("付款待确认，完成后会自动更新会员状态。")
            case .userCancelled: break
            @unknown default: break
            }
        } catch { message = error.localizedDescription }
    }
    func restore() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            try await synchronizeAppStore()
            try await updateAppleEntitlements()
            if account.session != nil { try await refresh() }
            message = purchased || active ? AppLocalization.text("Apple 订阅已恢复。") : AppLocalization.text("未找到当前 Apple 账号的有效订阅。")
        } catch { message = error.localizedDescription }
    }

}
enum MembershipError: LocalizedError {
    case unavailable, otherAccount, unverified
    var errorDescription: String? {
        switch self {
        case .unverified: return AppLocalization.text("无法验证 Apple 交易，请重试恢复购买。")
        case .unavailable: return AppLocalization.text("会员商品暂不可用，请稍后重试。")
        case .otherAccount: return AppLocalization.text("这笔购买属于另一个漫游账号，请登录购买时使用的邮箱。")
        }
    }
}

struct SyncMembershipView: View {
    @ObservedObject private var membership = MembershipStore.shared
    @ObservedObject private var account = AccountService.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("账号同步会员").font(.headline)
            Text("行程文字与图片引用通过漫游账号同步，照片继续保存在 iCloud，需要相同 Apple ID。本地使用和原有 iCloud 同步免费。")
                .font(.footnote)
            if membership.active || membership.purchased {
                Label(AppLocalization.text(membership.complimentary ? "此账号免费使用同步" : "会员已开通"), systemImage: "checkmark.seal.fill")
                if let date = membership.expires ?? membership.purchaseExpires { Text(AppLocalization.format("当前权益有效至 %@", date.formatted(date: .abbreviated, time: .omitted))).font(.footnote) }
            } else if let product = membership.product {
                Button(AppLocalization.format("按年订阅 · %@/年", product.displayPrice)) { Task { await membership.purchase() } }
                    .disabled(membership.busy)
            } else {
                Text("年费会员正在准备上架，暂时无法购买。实际价格以 App Store 显示为准。")
                    .font(.footnote)
            }
            if account.session == nil { Text("购买和恢复购买无需邮箱注册。可稍后选择邮箱登录，启用账号云同步。").font(.footnote) }
            Text("Apple 订阅可在同一 Apple 账号的设备上恢复。选择启用邮箱云同步后，请使用同一漫游账号访问其资料。").font(.caption)
            Button("恢复购买") { Task { await membership.restore() } }
                .disabled(membership.busy)
            DisclosureGroup("订阅管理与说明") {
            Link("管理或取消订阅", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            Text("按年自动续订，费用由 Apple 账号收取。可在 Apple 订阅设置中取消，取消后可用至当前付费周期结束。到期后停止账号同步，已有本机资料保留。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Link("使用条款", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("隐私政策", destination: URL(string: "https://roam.iiife.com/")!)
            }.font(.caption)
            }
            if membership.busy { ProgressView() }
            if !membership.message.isEmpty { Text(membership.message).font(.footnote) }
        }
        .task(id: account.session?.user.id) { await membership.load() }
    }
}
