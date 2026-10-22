import Foundation
import SwiftUI
import Security
import Combine

/// Namespace changes happen only after the old sync engines have drained.
@MainActor enum AccountWorkspace {
    static let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Roam")
    static var owner = UserDefaults.standard.string(forKey: "RoamAccountWorkspace")
    static var enabled: Bool { owner != nil }
    static var root: URL { owner.map { base.appendingPathComponent("Accounts/\($0)") } ?? base }

    static func shouldImportLocal(currentOwner: String?, firstImportOwner: String?, user: String) -> Bool {
        currentOwner == nil && (firstImportOwner == nil || firstImportOwner == user)
    }

    static func prepare(user: String, trips: [Trip], trash: [DeletedTrip], importLocal: Bool) throws {
        guard UUID(uuidString: user) != nil else { throw AccountError.invalidResponse }
        let fm = FileManager.default
        let target = base.appendingPathComponent("Accounts/\(user)")
        if !fm.fileExists(atPath: target.path) {
            let staging = base.appendingPathComponent("AccountMigration-\(UUID().uuidString)")
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: staging) }
            if importLocal {
                try JSONEncoder().encode(trips).write(to: staging.appendingPathComponent("trips.json"), options: .atomic)
                try JSONEncoder().encode(trash).write(to: staging.appendingPathComponent("trips-trash.json"), options: .atomic)
                let stickers = root.appendingPathComponent("Stickers")
                if fm.fileExists(atPath: stickers.path) {
                    let copy = staging.appendingPathComponent("Stickers")
                    try fm.copyItem(at: stickers, to: copy)
                    let board = copy.appendingPathComponent("board.json")
                    if fm.fileExists(atPath: board.path) {
                        guard var value = try JSONSerialization.jsonObject(with: Data(contentsOf: board)) as? [String: Any] else { throw AccountError.invalidResponse }
                        // Rebuild the account ledger from visible objects, never reuse iCloud ownership.
                        value["version"] = 2; value.removeValue(forKey: "cloud")
                        try JSONSerialization.data(withJSONObject: value).write(to: board, options: .atomic)
                    }
                }
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: staging, to: target)
        }
        UserDefaults.standard.set(user, forKey: "RoamAccountWorkspace")
    }
}

/// Rebuilds the entire model graph rather than changing paths underneath live stores.
@MainActor final class AccountWorkspaceState: ObservableObject {
    static let shared = AccountWorkspaceState()
    @Published private(set) var revision = 0
    @Published private(set) var switching = false

    private var checking = false

    func reconcile(store: TravelStore, expectedRevision: Int, stop: () async -> Void, resume: () -> Void) async {
        guard expectedRevision == revision, !checking, !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        let account = AccountService.shared
        let user = account.session?.user.id
        guard user != AccountWorkspace.owner else { return }
        checking = true
        defer { switching = false; checking = false }
        do {
            if user != nil { try await MembershipStore.shared.requireAccess() }
            guard account.session?.user.id == user else { return }
            switching = true
            await stop()
            guard account.session?.user.id == user else { resume(); return }
            if let user {
                guard store.saveError == nil else { throw AccountError.invalidResponse }
                // Import the original library only into the first account on this device.
                // Later accounts never inherit a previous account's private data.
                let defaults = UserDefaults.standard
                let firstOwner = defaults.string(forKey: "RoamLocalImportOwner")
                let importLocal = AccountWorkspace.shouldImportLocal(currentOwner: AccountWorkspace.owner, firstImportOwner: firstOwner, user: user)
                try AccountWorkspace.prepare(user: user, trips: store.trips, trash: store.deletedTrips, importLocal: importLocal)
                if importLocal { defaults.set(user, forKey: "RoamLocalImportOwner") }
            } else {
                UserDefaults.standard.removeObject(forKey: "RoamAccountWorkspace")
            }
            AccountWorkspace.owner = user
            revision += 1
            account.message = ""
        } catch {
            resume()
            account.message = error.localizedDescription
        }
    }
}

enum AccountError: LocalizedError {
    case membershipUnavailable, membershipRequired, unconfigured, emailNotReady, signedOut, conflict, invalidResponse, wrongAccount, server(Int), keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .membershipUnavailable: return "会员同步服务尚未开放，现有资料仍保存在本机。"
        case .membershipRequired: return "账号同步需要有效会员，本机资料已保留。请开通或恢复会员。"
        case .emailNotReady: return "账号云服务已连接，验证码邮件尚未配置，请稍后再试。"
        case .unconfigured: return "账号云服务尚未配置，当前数据仍保存在本机。"
        case .signedOut: return "请重新用邮箱验证码登录，离线更改仍保留。"
        case .conflict: return "另一台设备刚更新了数据，请重试同步。"
        case .invalidResponse: return "云端数据格式异常，已停止同步以保护本机数据。"
        case .wrongAccount: return "正在切换账号资料，请稍候。"
        case .server(413): return "云端存储容量或单次资料大小超限，本机更改已保留，请联系支持扩容。"
        case .server(let status): return status == 429 ? "操作太频繁，请稍后重试。" : "账号服务暂不可用（\(status)），本机数据已保留。"
        case .keychain: return "无法安全保存登录状态，请解锁设备后重试。"
        }
    }
}

struct AccountSession: Codable {
    struct User: Codable { var id: String; var email: String? }
    var access_token: String
    var refresh_token: String
    var expires_in: Double?
    var expires_at: Double?
    var user: User
    var expiry: Date { Date(timeIntervalSince1970: expires_at ?? 0) }
}

struct AccountDocument: Codable {
    var revision: Int
    var payload: String
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        guard let data = Data(base64Encoded: payload) else { throw AccountError.invalidResponse }
        return try JSONDecoder().decode(type, from: data)
    }
}

@MainActor final class AccountService: ObservableObject {
    static let shared = AccountService()
    @Published private(set) var session: AccountSession?
    @Published var message = ""
    @Published var busy = false
    private var refreshTask: Task<AccountSession, Error>?
    private var generation = 0
    private let service = "com.xiangchengjin.roam.account-session.v1"
    private let config: [String: String]
    private let network: URLSession
    var configured: Bool { endpoint != nil && !(config["PublishableKey"] ?? "").isEmpty }
    var emailLoginReady: Bool { configured && config["EmailLoginReady"] == "true" }
    private var endpoint: URL? {
        guard let text = config["URL"], let url = URL(string: text), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
    init(configuration: [String: String]? = nil, network: URLSession = .shared) {
        self.network = network
        if let configuration { config = configuration }
        else if ProcessInfo.processInfo.arguments.contains("--uitesting") && ProcessInfo.processInfo.arguments.contains("--account-unconfigured") { config = [:] }
        else { config = Bundle.main.url(forResource: "AccountConfig", withExtension: "plist")
            .flatMap { NSDictionary(contentsOf: $0) as? [String: String] } ?? [:] }
        var query = keyQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var data: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &data) == errSecSuccess, let bytes = data as? Data {
            session = try? JSONDecoder().decode(AccountSession.self, from: bytes)
        }
    }
    private var keyQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: config["URL"] ?? "unconfigured"]
    }
    private func save(_ value: AccountSession) throws {
        let data = try JSONEncoder().encode(value)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var result = SecItemUpdate(keyQuery as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound { result = SecItemAdd(keyQuery.merging(attributes) { _, new in new } as CFDictionary, nil) }
        guard result == errSecSuccess else { throw AccountError.keychain(result) }
        session = value
    }
    private func request(_ path: String, body: [String: Any], token: String? = nil) async throws -> Data {
        guard let endpoint, configured else { throw AccountError.unconfigured }
        let url = endpoint.appendingPathComponent(path.components(separatedBy: "?")[0])
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if let query = path.split(separator: "?", maxSplits: 1).dropFirst().first { components.percentEncodedQuery = String(query) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"; request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config["PublishableKey"], forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await network.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AccountError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 { throw AccountError.signedOut }
            if response.statusCode == 402 { throw AccountError.membershipRequired }
            if response.statusCode == 409 { throw AccountError.conflict }
            throw AccountError.server(response.statusCode)
        }
        return data
    }
    func sendCode(email: String) async throws {
        guard emailLoginReady else { throw configured ? AccountError.emailNotReady : AccountError.unconfigured }
        _ = try await request("auth/v1/otp", body: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "create_user": true])
    }
    func verify(email: String, code: String) async throws {
        let captured = generation
        let data = try await request("auth/v1/verify", body: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "token": code.trimmingCharacters(in: .whitespacesAndNewlines), "type": "email"])
        guard captured == generation else { throw CancellationError() }
        var value = try JSONDecoder().decode(AccountSession.self, from: data)
        guard UUID(uuidString: value.user.id) != nil else { throw AccountError.invalidResponse }
        value.expires_at = value.expires_at ?? Date().timeIntervalSince1970 + (value.expires_in ?? 3600)
        try save(value)
    }
    func credential() async throws -> AccountSession {
        guard let current = session else { throw AccountError.signedOut }
        guard current.expiry.timeIntervalSinceNow < 120 else { return current }
        if let refreshTask { return try await refreshTask.value }
        let captured = generation
        let task = Task { @MainActor in
            let data = try await self.request("auth/v1/token?grant_type=refresh_token", body: ["refresh_token": current.refresh_token])
            var next = try JSONDecoder().decode(AccountSession.self, from: data)
            guard captured == self.generation, next.user.id == current.user.id else { throw AccountError.signedOut }
            next.expires_at = next.expires_at ?? Date().timeIntervalSince1970 + (next.expires_in ?? 3600)
            try self.save(next)
            return next
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
    func signOut() async throws {
        // Revoke server sessions first. A failed request does not claim successful logout.
        let current = try await credential()
        _ = try await request("auth/v1/logout?scope=local", body: [:], token: current.access_token)
        generation += 1; refreshTask?.cancel(); refreshTask = nil
        let status = SecItemDelete(keyQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountError.keychain(status) }
        session = nil
        MembershipStore.shared.reset()
    }
    func deleteAccount() async throws {
        let current = try await credential()
        _ = try await request("rest/v1/rpc/roam_delete_account", body: [:], token: current.access_token)
        generation += 1; refreshTask?.cancel(); refreshTask = nil
        let status = SecItemDelete(keyQuery as CFDictionary)
        session = nil
        MembershipStore.shared.reset()
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountError.keychain(status) }
    }
    func checkOwner(_ user: String) throws {
        guard session?.user.id == user else { throw AccountError.signedOut }
        guard AccountWorkspace.owner == user else { throw AccountError.wrongAccount }
    }
    func membership(transactionID: String? = nil, signedTransaction: String? = nil) async throws -> SyncMembership {
        let current = try await credential()
        if transactionID == nil {
            let grantData = try await request("rest/v1/rpc/roam_complimentary_status", body: [:], token: current.access_token)
            guard session?.user.id == current.user.id else { throw AccountError.signedOut }
            let grant = try JSONDecoder().decode(SyncMembership.self, from: grantData)
            if grant.active && grant.complimentary == true { return grant }
        }
        var body: [String: Any] = transactionID.map { ["transactionId": $0] } ?? [:]
        if let signedTransaction { body["signedTransaction"] = signedTransaction }
        let data: Data
        do { data = try await request("functions/v1/roam-membership", body: body, token: current.access_token) }
        catch AccountError.server(404) { throw AccountError.membershipUnavailable }
        guard session?.user.id == current.user.id else { throw AccountError.signedOut }
        return try JSONDecoder().decode(SyncMembership.self, from: data)
    }
    func fetch(_ key: String) async throws -> AccountDocument? {
        try await MembershipStore.shared.requireAccess()
        let credential = try await credential(); try checkOwner(credential.user.id)
        let data = try await request("rest/v1/rpc/roam_read", body: ["document_key": key], token: credential.access_token)
        try checkOwner(credential.user.id)
        return try JSONDecoder().decode(AccountDocument?.self, from: data)
    }
    func put(_ key: String, data: Data, replacing revision: Int) async throws {
        try await MembershipStore.shared.requireAccess()
        let credential = try await credential(); try checkOwner(credential.user.id)
        _ = try await request("rest/v1/rpc/roam_write", body: ["document_key": key, "expected_revision": revision, "document_payload": data.base64EncodedString()], token: credential.access_token)
        try checkOwner(credential.user.id)
    }
}

struct AccountSyncSettings: View {
    @EnvironmentObject private var store: TravelStore
    @ObservedObject private var account = AccountService.shared
    @ObservedObject private var membership = MembershipStore.shared
    @State private var email = ""
    @State private var code = ""
    @State private var sentAt: Date?
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var confirmDeletion = false
    var body: some View {
        Section("邮箱账号同步") {
            SyncMembershipView()
            if !account.configured {
                Text("账号云服务尚未配置。部署后即可使用邮箱验证码登录；当前保存方式不变。")
            } else if !account.emailLoginReady {
                Text("账号云服务已连接，验证码邮件尚未配置，请稍后再试。")
            } else if let session = account.session {
                Text(session.user.email ?? "已登录")
                Text(membership.active ? "自动同步已开启" : "开通会员后，账号同步会自动开启。")
                Text("登录会员账号后自动同步，App 使用期间每 30 秒检查一次；离线更改会保存到本机，联网后自动重试。照片继续使用 iCloud。")
                    .font(.footnote).foregroundStyle(.secondary)
                DisclosureGroup("账号管理") {
                    Button("退出账号") { run { try await account.signOut() } }
                    Button("删除云端账号", role: .destructive) { confirmDeletion = true }
                }
            } else {
                Text("邮箱登录为可选项，用于启用账号云同步。购买或恢复会员无需登录。首次启用会保留原资料；照片需要相同 Apple ID。").font(.footnote)
                TextField("邮箱", text: $email).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("邮件验证码", text: $code).textContentType(.oneTimeCode)
                Button("发送验证码") { run { try await account.sendCode(email: email); sentAt = Date(); account.message = "验证码已发送，请查看邮箱。" } }
                    .disabled(!email.contains("@") || sentAt.map { now.timeIntervalSince($0) < 60 } == true)
                Button("登录 / 注册") { run { try await account.verify(email: email, code: code); account.message = "登录成功。" } }
                    .disabled(email.isEmpty || code.isEmpty)
            }
            if account.busy { ProgressView() }
            if !account.message.isEmpty { Text(account.message).font(.footnote) }

        }.disabled(account.busy)
        .onReceive(ticker) { now = $0 }
        .confirmationDialog("永久删除此账号及云端行程和手账文字？", isPresented: $confirmDeletion, titleVisibility: .visible) {
            Button("删除账号及云端资料", role: .destructive) {
                run { try await account.deleteAccount(); account.message = "云端账号已删除。本机副本仍保留，账号同步已停止。" }
            }
        } message: { Text("此操作无法撤销。不会删除本机副本或 iCloud 照片。删除账号不会取消 Apple 订阅，请在 Apple 订阅管理中另行管理续订。云端资料删除后无法恢复。") }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        account.busy = true
        Task { @MainActor in
            defer { account.busy = false }
            do { try await action() } catch { account.message = error.localizedDescription }
        }
    }
}
