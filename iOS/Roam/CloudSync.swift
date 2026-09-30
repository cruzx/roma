import Foundation
import CloudKit
import SwiftUI

struct CloudTripVersion: Codable, Equatable {
    var trip: Trip?
    var revision: String = UUID().uuidString
    var parent: String?
}

struct CloudLibrary: Codable {
    var schema = 1
    var trips: [String: CloudTripVersion] = [:]
    var order: [String] = []
    var orderRevision = UUID().uuidString

    var visible: [Trip] {
        let keys = order + trips.keys.filter { !order.contains($0) }.sorted()
        var seen = Set<String>()
        return keys.compactMap { key in
            guard seen.insert(key).inserted else { return nil }
            return trips[key]?.trip
        }
    }
}

struct CloudLedger: Codable {
    var library = CloudLibrary()
    var pending = Set<String>()
    var orderPending = false
    var owner: String?

    mutating func capture(_ trips: [Trip]) {
        let ids = Set(trips.map { $0.id.uuidString })
        for trip in trips {
            let key = trip.id.uuidString
            if library.trips[key]?.trip != trip {
                let previous = library.trips[key]
                library.trips[key] = CloudTripVersion(trip: trip, parent: pending.contains(key) ? previous?.parent : previous?.revision)
                pending.insert(key)
            }
        }
        for key in Array(library.trips.keys) where !ids.contains(key) && library.trips[key]?.trip != nil {
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
            if local.trip == incoming.trip { library.trips[key] = incoming; pending.remove(key); continue }
            if !pending.contains(key) { library.trips[key] = incoming; continue }
            if local.parent == incoming.revision { continue }
            if var preserved = incoming.trip ?? local.trip {
                preserved.id = UUID()
                preserved.destination += "（冲突副本）"
                let copyID = preserved.id.uuidString
                library.trips[copyID] = CloudTripVersion(trip: preserved)
                library.order.append(copyID); pending.insert(copyID)
                conflicts += 1
            }
            // If a deletion and an edit collide, retain the edit as the copy above.
            if incoming.trip == nil { local.trip = nil }
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
        let value = Bundle.main.object(forInfoDictionaryKey: "RoamCloudEnabled")
        return (value as? Bool) == true || ["YES", "true", "1"].contains(value as? String ?? "")
    }
    static let containerID = "iCloud.com.xiangchengjin.roam"
    private weak var store: TravelStore?
    private let ledgerFile: URL
    private var ledger: CloudLedger
    private var task: Task<Void, Never>?
    private var syncing = false
    private var conflictCount = 0
    private var container: CKContainer?
    private let recordID = CKRecord.ID(recordName: "travel-library-v1")

    init(store: TravelStore, file: URL, hasExistingData: Bool) {
        self.store = store
        ledgerFile = file.deletingLastPathComponent().appendingPathComponent("icloud-ledger-v1.json")
        if let data = try? Data(contentsOf: ledgerFile), let saved = try? JSONDecoder().decode(CloudLedger.self, from: data) {
            ledger = saved
            if hasExistingData { ledger.capture(store.trips) }
        } else {
            ledger = CloudLedger()
            if hasExistingData { ledger.capture(store.trips) }
        }
        if Self.isConfigured {
            container = CKContainer(identifier: Self.containerID)
            store.cloudStatus = "等待连接 iCloud"
        } else { store.cloudStatus = "iCloud 待配置开发者权限" }
    }

    func localChanged(_ trips: [Trip]) {
        ledger.capture(trips)
        persist()
        if container != nil { store?.cloudStatus = "更改已保存在本机，等待同步" }
    }

    func start() {
        guard container != nil, task == nil else { return }
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
        } catch { store?.cloudStatus = "同步记录保存失败，本机行程仍保留" }
    }

    func synchronize() async {
        guard let container, !syncing, let store else { return }
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
                    if ledger.library.visible != store.trips {
                        backup(store.trips)
                        store.applyCloudTrips(ledger.library.visible)
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
                    store.cloudStatus = conflictCount > 0 ? "已同步，保留了 \(conflictCount) 份冲突副本" : "iCloud 已同步"
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
    @EnvironmentObject private var store: TravelStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(store.cloudStatus, systemImage: "icloud")
                    if let date = store.cloudLastSync { Text("最近同步：" + date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                    Button("立即同步") { Task { await store.cloud?.synchronize() } }
                        .disabled(!RoamCloudSync.isConfigured)
                }
                Section("两台设备互通") {
                    Text("iPhone 和 Mac 登录同一个 iCloud 账户，即可同步旅行、每日安排、地点、路线顺序和首页排序。")
                    Text("离线时仍会保存到本机；打开 App 后会自动重试。同一旅行发生同时编辑冲突时，会保留冲突副本供你整理。")
                    Text("云端数据保存在你的私人 iCloud 空间，不会公开给其他用户。")
                }
            }
            .navigationTitle("iCloud 同步").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
