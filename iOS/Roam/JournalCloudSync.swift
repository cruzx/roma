import CloudKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The token contains only CloudKit system fields, including the server change tag.
struct JournalCloudSnapshot: Equatable {
    var library: JournalCloudLibrary?
    var token: Data?

    init(library: JournalCloudLibrary? = nil, token: Data? = nil) {
        self.library = library
        self.token = token
    }
}

@MainActor
protocol JournalCloudTransport: AnyObject {
    func accountID() async throws -> String
    func fetchManifest() async throws -> JournalCloudSnapshot
    func saveManifest(_ library: JournalCloudLibrary, replacing snapshot: JournalCloudSnapshot) async throws
    func downloadImage(named name: String) async throws -> Data
    func uploadImage(named name: String, data: Data) async throws
}

enum JournalCloudSyncError: Error {
    case accountChanged
    case invalidPayload
    case unsupportedSchema
    case invalidImage
    case invalidImageName
    case imageCollision
    case storageUnavailable
}

/// PNG records are immutable. The manifest is published only after all its pixels exist.
@MainActor
final class CloudKitJournalTransport: JournalCloudTransport {
    private let container: CKContainer
    private let manifestID = CKRecord.ID(recordName: "journal-board-v1")
    private var knownImages = Set<String>()
    private var knownAccount: String?

    init(container: CKContainer? = nil) {
        self.container = container ?? CKContainer(identifier: RoamCloudSync.containerID)
    }

    func accountID() async throws -> String {
        guard try await container.accountStatus() == .available else {
            throw CKError(.notAuthenticated)
        }
        let account = try await container.userRecordID().recordName
        if knownAccount != account {
            knownImages.removeAll()
            knownAccount = account
        }
        return account
    }

    func fetchManifest() async throws -> JournalCloudSnapshot {
        let record: CKRecord
        do {
            record = try await container.privateCloudDatabase.record(for: manifestID)
        } catch let error as CKError where error.code == .unknownItem {
            return JournalCloudSnapshot()
        }
        // An existing but unreadable record must never become an empty new library.
        guard let file = (record["payload"] as? CKAsset)?.fileURL else {
            throw JournalCloudSyncError.invalidPayload
        }
        let library = try await Task.detached(priority: .utility) {
            let value = try JSONDecoder().decode(JournalCloudLibrary.self, from: Data(contentsOf: file))
            guard value.schema == 1 else { throw JournalCloudSyncError.unsupportedSchema }
            try value.validated()
            return value
        }.value
        let archive = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archive)
        archive.finishEncoding()
        return JournalCloudSnapshot(library: library, token: archive.encodedData)
    }

    func saveManifest(_ library: JournalCloudLibrary, replacing snapshot: JournalCloudSnapshot) async throws {
        try library.validated()
        let record: CKRecord
        if let token = snapshot.token {
            let decoder = try NSKeyedUnarchiver(forReadingFrom: token)
            decoder.requiresSecureCoding = true
            defer { decoder.finishDecoding() }
            guard let restored = CKRecord(coder: decoder), restored.recordID == manifestID,
                  restored.recordType == "RoamLibrary" else {
                throw JournalCloudSyncError.invalidPayload
            }
            record = restored
        } else {
            guard snapshot.library == nil else { throw JournalCloudSyncError.invalidPayload }
            record = CKRecord(recordType: "RoamLibrary", recordID: manifestID)
        }
        let file = try await Task.detached(priority: .utility) {
            try Self.temporaryAsset(try JSONEncoder().encode(library), extension: "json")
        }.value
        defer { try? FileManager.default.removeItem(at: file) }
        record["payload"] = CKAsset(fileURL: file)
        // The restored change tag ensures a concurrent writer causes a retry, not an overwrite.
        _ = try await container.privateCloudDatabase.save(record)
    }

    func downloadImage(named name: String) async throws -> Data {
        let id = try imageID(name)
        let record = try await container.privateCloudDatabase.record(for: id)
        guard let file = (record["payload"] as? CKAsset)?.fileURL else {
            throw JournalCloudSyncError.invalidImage
        }
        let pixels = try await Task.detached(priority: .utility) {
            let pixels = try Data(contentsOf: file)
            try Self.validatePNG(pixels)
            return pixels
        }.value
        knownImages.insert(name)
        return pixels
    }

    func uploadImage(named name: String, data: Data) async throws {
        let id = try imageID(name)
        guard !knownImages.contains(name) else { return }
        try await Task.detached(priority: .utility) { try Self.validatePNG(data) }.value
        let database = container.privateCloudDatabase
        do {
            let existing = try await database.record(for: id)
            try await verifyExistingImage(existing, matches: data)
            knownImages.insert(name)
            return
        } catch let error as CKError where error.code == .unknownItem {
            // Only an absent record may be created. A corrupt asset is never overwritten.
        }
        let file = try await Task.detached(priority: .utility) {
            try Self.temporaryAsset(data, extension: "png")
        }.value
        defer { try? FileManager.default.removeItem(at: file) }
        let record = CKRecord(recordType: "RoamLibrary", recordID: id)
        record["payload"] = CKAsset(fileURL: file)
        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Another device may have uploaded the same immutable image concurrently.
            let existing = try await database.record(for: id)
            try await verifyExistingImage(existing, matches: data)
        }
        knownImages.insert(name)
    }

    private func verifyExistingImage(_ record: CKRecord, matches pixels: Data) async throws {
        guard let file = (record["payload"] as? CKAsset)?.fileURL else {
            throw JournalCloudSyncError.invalidImage
        }
        try await Task.detached(priority: .utility) {
            let existing = try Data(contentsOf: file)
            try Self.validatePNG(existing)
            guard existing == pixels else { throw JournalCloudSyncError.imageCollision }
        }.value
    }

    private func imageID(_ name: String) throws -> CKRecord.ID {
        guard name.hasSuffix(".png"), UUID(uuidString: String(name.dropLast(4))) != nil else {
            throw JournalCloudSyncError.invalidImageName
        }
        return CKRecord.ID(recordName: "journal-image-" + name)
    }

    nonisolated private static func temporaryAsset(_ data: Data, extension suffix: String) throws -> URL {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("roam-journal-\(UUID().uuidString).\(suffix)")
        try data.write(to: file, options: .atomic)
        return file
    }

    nonisolated private static func validatePNG(_ data: Data) throws {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              CGImageSourceGetCount(source) > 0,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw JournalCloudSyncError.invalidImage
        }
    }
}

@MainActor
final class JournalCloudSync {
    private weak var store: StickerBoardStore?
    private let transport: (any JournalCloudTransport)?
    private var timer: Task<Void, Never>?
    private var debounce: Task<Void, Never>?
    private var syncing = false
    private var accountGeneration = 0
    private var accountObserver: NSObjectProtocol?
    private var confirmedImageNames = Set<String>()
    private var confirmedImageAccount: String?
    private var conflictCount = 0

    init(store: StickerBoardStore, transport: (any JournalCloudTransport)? = nil) {
        self.store = store
        self.transport = transport ?? (RoamCloudSync.isConfigured ? CloudKitJournalTransport() : nil)
        store.cloudStatus = self.transport == nil ? "iCloud 待配置开发者权限" : "等待连接 iCloud"
        accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.accountGeneration += 1
                self.confirmedImageNames.removeAll()
                self.confirmedImageAccount = nil
                self.localChanged()
            }
        }
    }

    deinit {
        timer?.cancel()
        debounce?.cancel()
        if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) }
    }

    func start() {
        guard transport != nil, timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.synchronize()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }

    func localChanged() {
        guard transport != nil else { return }
        store?.cloudStatus = "更改已保存在本机，等待同步"
        scheduleRetry()
    }

    private func scheduleRetry() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            // A new edit must not cancel an in-flight upload started by this debounce.
            self.debounce = nil
            await self.synchronize()
        }
    }

    func synchronize() async {
        guard let store, let transport, !syncing else { return }
        guard store.syncStorageAvailable else {
            store.cloudStatus = "同步数据读取失败，本机数据已保留"
            return
        }
        syncing = true
        let generation = accountGeneration
        defer { syncing = false }
        do {
            let owner = try await transport.accountID()
            try checkGeneration(generation)
            guard store.cloudLedger.owner == nil || store.cloudLedger.owner == owner else {
                throw JournalCloudSyncError.accountChanged
            }
            try store.bindCloudOwner(owner)
            if confirmedImageAccount != owner {
                confirmedImageNames.removeAll()
                confirmedImageAccount = owner
            }
            store.cloudStatus = "正在同步 iCloud…"

            for attempt in 0..<3 {
                let snapshot = try await transport.fetchManifest()
                try checkGeneration(generation)
                var pinned = Set<String>()
                defer { store.unpinCloudImages() }
                if let remote = snapshot.library {
                    guard remote.schema == 1 else { throw JournalCloudSyncError.unsupportedSchema }
                    try remote.validated()
                    // Pin resident images too: a user may delete one while a different image downloads.
                    pinned.formUnion(remote.imageNames)
                    store.pinCloudImages(pinned)
                    var downloaded = [String: Data]()
                    for name in remote.imageNames.sorted() where !store.hasCloudImage(named: name) {
                        downloaded[name] = try await transport.downloadImage(named: name)
                        try checkGeneration(generation)
                    }
                    try await verifyAccount(owner, generation: generation)
                    confirmedImageNames.formUnion(downloaded.keys)
                    try requireStorage(store)
                    // The store merges its current versions, not a pre-await copy of the board.
                    conflictCount += try store.mergeCloud(remote, images: downloaded)
                }

                try await verifyAccount(owner, generation: generation)
                try requireStorage(store)
                guard store.cloudLedger.hasPendingChanges else {
                    store.cloudStatus = completedStatus
                    store.cloudLastSync = Date()
                    return
                }
                let outgoing = store.cloudLedger.library
                try outgoing.validated()
                pinned.formUnion(outgoing.imageNames)
                store.pinCloudImages(pinned)
                // Geometry and text edits reuse confirmed immutable assets without rereading PNGs.
                for name in outgoing.imageNames.sorted() where !confirmedImageNames.contains(name) {
                    guard let file = store.imageURL(named: name) else {
                        throw JournalCloudSyncError.invalidImageName
                    }
                    let pixels = try await Task.detached(priority: .utility) { try Data(contentsOf: file) }.value
                    try await verifyAccount(owner, generation: generation)
                    try await transport.uploadImage(named: name, data: pixels)
                    try await verifyAccount(owner, generation: generation)
                    confirmedImageNames.insert(name)
                }
                try await verifyAccount(owner, generation: generation)
                do {
                    try await transport.saveManifest(outgoing, replacing: snapshot)
                    try await verifyAccount(owner, generation: generation)
                    try requireStorage(store)
                    // Only revisions present in outgoing are acknowledged; later edits stay pending.
                    try store.acknowledgeCloud(outgoing)
                    store.cloudLastSync = Date()
                    if store.cloudLedger.hasPendingChanges {
                        store.cloudStatus = "更改已保存在本机，等待同步"
                        scheduleRetry()
                    } else {
                        store.cloudStatus = completedStatus
                    }
                    return
                } catch let error as CKError where error.code == .serverRecordChanged && attempt < 2 {
                    continue
                }
            }
        } catch {
            store.cloudStatus = status(for: error)
        }
    }

    private func checkGeneration(_ generation: Int) throws {
        try Task.checkCancellation()
        guard generation == accountGeneration else { throw JournalCloudSyncError.accountChanged }
    }

    private func verifyAccount(_ owner: String, generation: Int) async throws {
        try checkGeneration(generation)
        guard let transport, try await transport.accountID() == owner else {
            throw JournalCloudSyncError.accountChanged
        }
        try checkGeneration(generation)
        guard let store, store.cloudLedger.owner == owner else {
            throw JournalCloudSyncError.accountChanged
        }
    }

    private func requireStorage(_ store: StickerBoardStore) throws {
        guard store.syncStorageAvailable else { throw JournalCloudSyncError.storageUnavailable }
    }

    private var completedStatus: String {
        conflictCount == 0 ? "iCloud 已同步" :
            AppLocalization.format("已同步，保留了 %lld 份冲突副本", Int64(conflictCount))
    }

    private func status(for error: Error) -> String {
        if let error = error as? JournalStorageError, case .accountChanged = error {
            return "iCloud 账户已更换，同步已暂停以保护原账户数据"
        }
        if let error = error as? JournalCloudSyncError {
            switch error {
            case .accountChanged: return "iCloud 账户已更换，同步已暂停以保护原账户数据"
            case .unsupportedSchema: return "云端数据版本较新，请更新 App"
            default: return "同步数据读取失败，本机数据已保留"
            }
        }
        if let error = error as? CKError {
            switch error.code {
            case .notAuthenticated: return "请在系统设置登录 iCloud"
            case .networkUnavailable, .networkFailure: return "网络不可用，更改已保存在本机"
            case .quotaExceeded: return "iCloud 空间不足，更改已保存在本机"
            case .permissionFailure: return "云端尚未授权此 App，同步暂不可用（错误 10）"
            case .badContainer, .missingEntitlement: return "iCloud 容器或签名权限尚未配置"
            default: return "暂时无法同步，更改已保存在本机，稍后重试"
            }
        }
        if error is CancellationError { return "更改已保存在本机，等待同步" }
        return "同步数据读取失败，本机数据已保留"
    }
}
