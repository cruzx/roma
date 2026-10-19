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
    @Published private(set) var active = false
    @Published private(set) var complimentary = false
    @Published private(set) var expires: Date?
    @Published var message = ""
    @Published private(set) var busy = false
    private var owner: String?
    @Published var showPurchaseIntentAccount = false
    private var intentListener: Task<Void, Never>?
    private var listener: Task<Void, Never>?
    init() {
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
            try await refresh()
        } catch { message = error.localizedDescription }
    }
    func refresh(transactionID: String? = nil) async throws {
        let account = AccountService.shared
        guard let user = account.session?.user.id else { reset(); return }
        if owner != user { reset() }
        do {
            let value = try await account.membership(transactionID: transactionID)
            guard account.session?.user.id == user else { reset(); throw AccountError.signedOut }
            owner = user; active = value.active; complimentary = value.complimentary == true; expires = value.expires
        } catch { active = false; throw error }
    }
    func requireAccess() async throws {
        try await refresh()
        guard active else { throw AccountError.membershipRequired }
    }
    private func accept(_ result: VerificationResult<StoreKit.Transaction>) async throws {
        guard case .verified(let transaction) = result else { throw MembershipError.unverified }
        guard transaction.productID == Self.productID else { return }
        guard let user = AccountService.shared.session?.user.id,
              transaction.appAccountToken == UUID(uuidString: user) else {
            throw MembershipError.otherAccount
        }
        try await refresh(transactionID: String(transaction.id))
        // Only finish after the server persisted and validated the transaction.
        await transaction.finish()
    }
    func purchase() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            guard let product, product.type == .autoRenewable,
                  product.subscription?.subscriptionPeriod.unit == .year,
                  product.subscription?.subscriptionPeriod.value == 1,
                  let user = AccountService.shared.session?.user.id,
                  let token = UUID(uuidString: user) else { throw MembershipError.unavailable }
            try await refresh() // Check server availability before asking Apple to charge.
            if active { message = "此账号已开通会员。"; return }
            switch try await product.purchase(options: [.appAccountToken(token)]) {
            case .success(let result): try await accept(result)
            case .pending: message = "付款待确认，完成后会自动更新会员状态。"
            case .userCancelled: break
            @unknown default: break
            }
        } catch { message = error.localizedDescription }
    }
    func restore() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            guard AccountService.shared.session != nil else { throw AccountError.signedOut }
            try await AppStore.sync()
            for await result in StoreKit.Transaction.currentEntitlements { try await accept(result) }
            try await refresh()
            message = active ? "会员已恢复。" : "未找到此漫游账号的有效订阅，请确认购买时的账号。"
        } catch { message = error.localizedDescription }
    }
}
enum MembershipError: LocalizedError {
    case unavailable, otherAccount, unverified
    var errorDescription: String? {
        switch self {
        case .unverified: return "无法验证 Apple 交易，请重试恢复购买。"
        case .unavailable: return "会员商品暂不可用，请稍后重试。"
        case .otherAccount: return "这笔购买属于另一个漫游账号，请登录购买时使用的邮箱。"
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
            if membership.active {
                Label(membership.complimentary ? "此账号免费使用同步" : "会员已开通", systemImage: "checkmark.seal.fill")
                if let date = membership.expires { Text("当前权益有效至 \(date.formatted(date: .abbreviated, time: .omitted))").font(.footnote) }
            } else if let product = membership.product {
                Button("按年订阅 · \(product.displayPrice)/年") { Task { await membership.purchase() } }
                    .disabled(membership.busy || account.session == nil)
            } else {
                Text("年费会员正在准备上架，暂时无法购买。实际价格以 App Store 显示为准。")
                    .font(.footnote)
            }
            if account.session == nil { Text("请先登录邮箱账号，再购买或恢复会员。").font(.footnote) }
            Text("会员绑定购买时的漫游邮箱账号，跨设备请使用同一账号。").font(.caption)
            DisclosureGroup("订阅管理与说明") {
            Button("恢复购买") { Task { await membership.restore() } }
                .disabled(membership.busy || account.session == nil)
            Link("管理或取消订阅", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            Text("按年自动续订，费用由 Apple 账号收取。可在 Apple 订阅设置中取消，取消后可用至当前付费周期结束。到期后停止账号同步，已有本机资料保留。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Link("使用条款", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("隐私政策", destination: URL(string: "https://roam-privacy-support.cruzxcx.chatgpt.site/")!)
            }.font(.caption)
            }
            if membership.busy { ProgressView() }
            if !membership.message.isEmpty { Text(membership.message).font(.footnote) }
        }
        .task(id: account.session?.user.id) { await membership.load() }
    }
}
