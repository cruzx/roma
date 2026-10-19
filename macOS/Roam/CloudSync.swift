import Foundation
import CloudKit
import SwiftUI

struct CloudTripVersion: Codable, Equatable {
    var trip: Trip?
    var revision: String = UUID().uuidString
    var parent: String?
    var archived: DeletedTrip? = nil
}

struct CloudLibrary: Codable {
    var schema = 1
    var trips: [String: CloudTripVersion] = [:]
    var order: [String] = []
    var orderRevision = UUID().uuidString

    func validateAccountPayload() throws {
        guard schema == 1, Set(order).count == order.count else { throw AccountError.invalidResponse }
        for (key, value) in trips {
            if let trip = value.trip ?? value.archived?.trip {
                guard trip.coverPhoto == nil, AccountPhotoCodec.references(trip).allSatisfy(AccountPhotoCodec.valid),
                      trip.days.flatMap({ $0.items }).allSatisfy({ $0.photos == nil && $0.linkPreview?.imageData == nil }) else { throw AccountError.invalidResponse }
            }
            guard UUID(uuidString: key) != nil, !value.revision.isEmpty,
                  value.trip == nil || value.archived == nil,
                  value.trip.map({ $0.id.uuidString == key }) ?? true,
                  value.archived.map({ $0.id.uuidString == key }) ?? true else { throw AccountError.invalidResponse }
        }
    }

    var visible: [Trip] {
        let keys = order + trips.keys.filter { !order.contains($0) }.sorted()
        var seen = Set<String>()
        return keys.compactMap { key in
            guard seen.insert(key).inserted else { return nil }
            return trips[key]?.trip
        }
    }
}

extension CloudLibrary {
    var trash: [DeletedTrip] {
        trips.values.compactMap { $0.archived }.filter { $0.expiresAt > Date() }.sorted { $0.deletedAt > $1.deletedAt }
    }
}

struct CloudLedger: Codable {
    var library = CloudLibrary()
    var pending = Set<String>()
    var orderPending = false
    var owner: String?

    mutating func acknowledge(_ outgoing: CloudLibrary) {
        for (key, version) in outgoing.trips where library.trips[key]?.revision == version.revision { pending.remove(key) }
        if library.orderRevision == outgoing.orderRevision { orderPending = false }
    }

    mutating func capture(_ trips: [Trip], trash: [DeletedTrip] = []) {
        let validTrash = trash.filter { $0.expiresAt > Date() }
        let ids = Set(trips.map { $0.id.uuidString } + validTrash.map { $0.id.uuidString })
        for trip in trips {
            let key = trip.id.uuidString
            if library.trips[key]?.trip != trip || library.trips[key]?.archived != nil {
                let previous = library.trips[key]
                library.trips[key] = CloudTripVersion(trip: trip, parent: pending.contains(key) ? previous?.parent : previous?.revision)
                pending.insert(key)
            }
        }
        for entry in validTrash {
            let key = entry.id.uuidString
            if library.trips[key]?.archived != entry || library.trips[key]?.trip != nil {
                let previous = library.trips[key]
                library.trips[key] = CloudTripVersion(trip: nil, parent: pending.contains(key) ? previous?.parent : previous?.revision, archived: entry)
                pending.insert(key)
            }
        }
        for key in Array(library.trips.keys) where !ids.contains(key) && (library.trips[key]?.trip != nil || library.trips[key]?.archived != nil) {
            let previous = library.trips[key]
            library.trips[key] = CloudTripVersion(trip: nil, parent: pending.contains(key) ? previous?.parent : previous?.revision)
            pending.insert(key)
        }
        let order = trips.map { $0.id.uuidString }
        if order != library.order {
            library.order = order; library.orderRevision = UUID().uuidString; orderPending = true
        }
    }

    // A stale device never overwrites another device's edit without preserving a copy.
    @discardableResult mutating func merge(_ remote: CloudLibrary) -> Int {
        var conflicts = 0
        for (key, incoming) in remote.trips {
            guard var local = library.trips[key] else { library.trips[key] = incoming; continue }
            if local.revision == incoming.revision { continue }
            if local.trip == incoming.trip && local.archived == incoming.archived { library.trips[key] = incoming; pending.remove(key); continue }
            if !pending.contains(key) { library.trips[key] = incoming; continue }
            if local.parent == incoming.revision { continue }
            if var preserved = incoming.trip ?? local.trip {
                preserved.id = UUID()
                preserved.destination = AppLocalization.format("%@（冲突副本）", preserved.destination)
                let copyID = preserved.id.uuidString
                library.trips[copyID] = CloudTripVersion(trip: preserved)
                library.order.append(copyID); pending.insert(copyID)
                conflicts += 1
            }
            // If a deletion and an edit collide, retain the edit as the copy above.
            if incoming.trip == nil { local.trip = nil; local.archived = incoming.archived }
            local.parent = incoming.revision
            library.trips[key] = local
        }
        if !orderPending {
            library.order = remote.order + library.order.filter { !remote.order.contains($0) }
            library.orderRevision = remote.orderRevision
        } else {
            library.order += remote.order.filter { !library.order.contains($0) }
        }
        return conflicts
    }
}

@MainActor
final class RoamCloudSync {
    static var isConfigured: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let value = Bundle.main.object(forInfoDictionaryKey: "RoamCloudEnabled")
        return (value as? Bool) == true || ["YES", "true", "1"].contains(value as? String ?? "")
        #endif
    }
    static let containerID = "iCloud.com.xiangchengjin.roam"
    private weak var store: TravelStore?
    private let ledgerFile: URL
    private var ledger: CloudLedger
    private var task: Task<Void, Never>?
    private var stopped = false
    private var syncing = false
    private var conflictCount = 0
    private var accountStorageOK = true
    private let accountPhotos = AccountPhotoStore()
    private var container: CKContainer?
    private let recordID = CKRecord.ID(recordName: "travel-library-v1")

    init(store: TravelStore, file: URL, hasExistingData: Bool) {
        self.store = store
        accountStorageOK = store.saveError == nil
        ledgerFile = file.deletingLastPathComponent().appendingPathComponent(AccountWorkspace.enabled ? "account-ledger-v1.json" : "icloud-ledger-v1.json")
        if let data = try? Data(contentsOf: ledgerFile), let saved = try? JSONDecoder().decode(CloudLedger.self, from: data) {
            ledger = saved
            if hasExistingData && (!AccountWorkspace.enabled || accountStorageOK) { captureAccountAware(store.trips, trash: store.deletedTrips) }
        } else {
            ledger = CloudLedger()
            if AccountWorkspace.enabled && FileManager.default.fileExists(atPath: ledgerFile.path) { accountStorageOK = false }
            if hasExistingData && (!AccountWorkspace.enabled || accountStorageOK) { captureAccountAware(store.trips, trash: store.deletedTrips) }
        }
        if AccountWorkspace.enabled {
            store.cloudStatus = "等待邮箱账号同步"
        } else if Self.isConfigured {
            container = CKContainer(identifier: Self.containerID)
            store.cloudStatus = "等待连接 iCloud"
        } else { store.cloudStatus = "iCloud 待配置开发者权限" }
    }

    private func captureAccountAware(_ trips: [Trip], trash: [DeletedTrip]) {
        guard AccountWorkspace.enabled else { ledger.capture(trips, trash: trash); return }
        do {
            let metadata = try trips.map { try accountPhotos.codec.metadata($0) }
            let archived = try trash.map { entry in
                var copy = entry; copy.trip = try accountPhotos.codec.metadata(entry.trip); return copy
            }
            ledger.capture(metadata, trash: archived)
        } catch { accountStorageOK = false; store?.cloudStatus = "照片本机缓存保存失败，账号同步已暂停" }
    }
    private func applyAccountLibrary() {
        let trips = ledger.library.visible.map { accountPhotos.codec.hydrated($0) }
        let trash = ledger.library.trash.map { entry in
            var copy = entry; copy.trip = accountPhotos.codec.hydrated(entry.trip); return copy
        }
        store?.applyCloudTrips(trips, trash: trash)
    }
    private func synchronizeAccountPhotos(user: String) async {
        let trips = ledger.library.trips.values.compactMap { $0.trip ?? $0.archived?.trip }
        let keys = trips.reduce(into: Set<String>()) { $0.formUnion(AccountPhotoCodec.references($1)) }
        do {
            try await accountPhotos.synchronize(keys, user: user)
            try AccountService.shared.checkOwner(user)
            applyAccountLibrary()
            if !keys.isEmpty { store?.cloudStatus += "；iCloud 照片已同步" }
        } catch {
            store?.cloudStatus += "；照片等待 iCloud（需相同 Apple ID，稍后自动重试）"
        }
    }

    func localChanged(_ trips: [Trip], trash: [DeletedTrip] = []) {
        captureAccountAware(trips, trash: trash)
        persist()
        if container != nil || AccountWorkspace.enabled { store?.cloudStatus = "更改已保存在本机，等待同步" }
    }

    func start() {
        stopped = false
        guard (container != nil || AccountWorkspace.enabled), task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.synchronize()
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: ledgerFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(ledger).write(to: ledgerFile, options: .atomic)
        } catch { if AccountWorkspace.enabled { accountStorageOK = false }; store?.cloudStatus = "同步记录保存失败，本机行程仍保留" }
    }

    func stopAndDrain() async {
        stopped = true
        task?.cancel(); task = nil
        while syncing { await Task.detached { try? await Task.sleep(for: .milliseconds(50)) }.value }
    }

    func synchronize() async {
        guard !stopped else { return }
        if AccountWorkspace.enabled { await synchronizeAccount(); return }
        guard let container, !syncing, let store else { return }
        store.purgeExpiredTrash()
        syncing = true
        defer { syncing = false }
        do {
            guard try await container.accountStatus() == .available else {
                store.cloudStatus = "请在系统设置登录 iCloud"; return
            }
            let owner = try await container.userRecordID().recordName
            guard ledger.owner == nil || ledger.owner == owner else {
                store.cloudStatus = "iCloud 账户已更换，同步已暂停以保护原账户数据"; return
            }
            ledger.owner = owner; persist()
            store.cloudStatus = "正在同步 iCloud…"
            let database = container.privateCloudDatabase
            for attempt in 0..<3 {
                let record: CKRecord
                do { record = try await database.record(for: recordID) }
                catch let error as CKError where error.code == .unknownItem { record = CKRecord(recordType: "RoamLibrary", recordID: recordID) }
                if let asset = record["payload"] as? CKAsset, let url = asset.fileURL {
                    let remote = try JSONDecoder().decode(CloudLibrary.self, from: Data(contentsOf: url))
                    guard remote.schema == 1 else { store.cloudStatus = "云端数据版本较新，请更新 App"; return }
                    conflictCount += ledger.merge(remote)
                    persist()
                    if ledger.library.visible != store.trips || ledger.library.trash != store.deletedTrips {
                        backup(store.trips)
                        store.applyCloudTrips(ledger.library.visible, trash: ledger.library.trash)
                    }
                }
                if ledger.pending.isEmpty && !ledger.orderPending {
                    store.cloudStatus = "iCloud 已同步"; store.cloudLastSync = Date(); return
                }
                // Snapshot exactly the revisions being sent; edits made during await stay pending.
                let outgoing = ledger.library
                let assetURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
                try JSONEncoder().encode(outgoing).write(to: assetURL, options: .atomic)
                defer { try? FileManager.default.removeItem(at: assetURL) }
                record["payload"] = CKAsset(fileURL: assetURL)
                do {
                    _ = try await database.save(record)
                    for (key, version) in outgoing.trips where ledger.library.trips[key]?.revision == version.revision {
                        ledger.pending.remove(key)
                    }
                    if ledger.library.orderRevision == outgoing.orderRevision { ledger.orderPending = false }
                    persist()
                    store.cloudLastSync = Date()
                    if !ledger.pending.isEmpty || ledger.orderPending {
                        store.cloudStatus = "更改已保存在本机，等待同步"
                        return
                    }
                    store.setCloudSyncResult(conflictCount: conflictCount)
                    return
                } catch let error as CKError where error.code == .serverRecordChanged && attempt < 2 { continue }
            }
        } catch {
            if let cloudError = error as? CKError {
                switch cloudError.code {
                case .notAuthenticated: store.cloudStatus = "请在系统设置登录 iCloud"
                case .networkUnavailable, .networkFailure: store.cloudStatus = "网络不可用，更改已保存在本机"
                case .quotaExceeded: store.cloudStatus = "iCloud 空间不足，更改已保存在本机"
                case .permissionFailure: store.cloudStatus = "云端尚未授权此 App，同步暂不可用（错误 10）"
                case .badContainer, .missingEntitlement: store.cloudStatus = "iCloud 容器或签名权限尚未配置"
                default: store.cloudStatus = "暂时无法同步，更改已保存在本机，稍后重试"
                }
            } else { store.cloudStatus = "同步数据读取失败，本机数据已保留" }
        }
    }

    private func synchronizeAccount() async {
        guard !syncing, let store else { return }
        guard accountStorageOK, store.saveError == nil else {
            store.cloudStatus = "本机同步资料读取或保存失败，账号同步已暂停"; return
        }
        syncing = true
        defer { syncing = false }
        do {
            let service = AccountService.shared
            let user = try await service.credential().user.id
            try service.checkOwner(user)
            store.cloudStatus = "正在同步邮箱账号…"
            for attempt in 0..<3 {
                try FileManager.default.createDirectory(at: ledgerFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(ledger).write(to: ledgerFile, options: .atomic)
                let snapshot = try await service.fetch("trips")
                try service.checkOwner(user)
                if let snapshot {
                    let remote = try snapshot.decode(CloudLibrary.self)
                    try remote.validateAccountPayload()
                    // Preserve a durable pre-merge snapshot including the trash.
                    let recovery = ledgerFile.deletingLastPathComponent().appendingPathComponent("account-before-merge.json")
                    try JSONEncoder().encode(ledger).write(to: recovery, options: .atomic)
                    conflictCount += ledger.merge(remote)
                    try JSONEncoder().encode(ledger).write(to: ledgerFile, options: .atomic)
                    applyAccountLibrary()
                    guard store.saveError == nil else { throw AccountError.invalidResponse }
                }
                if ledger.pending.isEmpty && !ledger.orderPending {
                    store.cloudStatus = "行程文字已同步"; store.cloudLastSync = Date()
                    await synchronizeAccountPhotos(user: user); return
                }
                let outgoing = ledger.library
                try outgoing.validateAccountPayload()
                do {
                    try await service.put("trips", data: JSONEncoder().encode(outgoing), replacing: snapshot?.revision ?? 0)
                    try service.checkOwner(user)
                    ledger.acknowledge(outgoing)
                    try JSONEncoder().encode(ledger).write(to: ledgerFile, options: .atomic)
                    store.cloudLastSync = Date()
                    store.cloudStatus = !ledger.pending.isEmpty || ledger.orderPending ? "更改已保存在本机，等待同步" :
                        (conflictCount == 0 ? "账号已同步" : "账号已同步，保留了 \(conflictCount) 份冲突副本")
                    await synchronizeAccountPhotos(user: user)
                    return
                } catch AccountError.conflict where attempt < 2 { continue }
            }
        } catch { store.cloudStatus = error.localizedDescription }
    }

    private func backup(_ trips: [Trip]) {
        let folder = ledgerFile.deletingLastPathComponent().appendingPathComponent("SyncBackups")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("before-sync-\(Date().timeIntervalSince1970).json")
            try JSONEncoder().encode(trips).write(to: url, options: .atomic)
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent > $1.lastPathComponent }
            for file in files.dropFirst(10) { try? FileManager.default.removeItem(at: file) }
        } catch { /* The primary local store and ledger remain authoritative. */ }
    }
}

struct CloudSyncView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                AccountSyncSettings()
            }
            .navigationTitle("账号").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
