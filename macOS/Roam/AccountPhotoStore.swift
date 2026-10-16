import Foundation
import CloudKit
import CryptoKit

/// Only references leave the device for the account server. Bytes live in a local cache and private CloudKit assets.
struct AccountPhotoCodec {
    let directory: URL
    static func valid(_ key: String) -> Bool { key.count == 64 && key.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    func cache(_ data: Data) throws -> String {
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(key)
        if read(key) != data { try data.write(to: url, options: .atomic) }
        return key
    }
    func read(_ key: String) -> Data? {
        guard Self.valid(key), let data = try? Data(contentsOf: directory.appendingPathComponent(key)),
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == key else { return nil }
        return data
    }
    func metadata(_ original: Trip) throws -> Trip {
        var trip = original
        if let bytes = trip.coverPhoto { trip.coverPhotoReference = try cache(bytes) }
        trip.coverPhoto = nil
        for d in trip.days.indices { for i in trip.days[d].items.indices {
            var item = trip.days[d].items[i]
            if let bytes = item.photos {
                let added = try bytes.map { try cache($0) }
                let retained = (item.photoReferences ?? []).filter { !added.contains($0) }
                item.photoReferences = retained + added
            }
            item.photos = nil
            if let bytes = item.linkPreview?.imageData { item.linkPreview?.imageReference = try cache(bytes) }
            item.linkPreview?.imageData = nil
            trip.days[d].items[i] = item
        } }
        return trip
    }
    func hydrated(_ original: Trip) -> Trip {
        var trip = original
        if let key = trip.coverPhotoReference { trip.coverPhoto = read(key) }
        for d in trip.days.indices { for i in trip.days[d].items.indices {
            var item = trip.days[d].items[i]
            if let keys = item.photoReferences {
                let images = keys.compactMap { read($0) }
                // Never expose a partial list that an edit could mistake for the complete set.
                item.photos = images.count == keys.count ? images : nil
            }
            if let key = item.linkPreview?.imageReference { item.linkPreview?.imageData = read(key) }
            trip.days[d].items[i] = item
        } }
        return trip
    }
    static func references(_ trip: Trip) -> Set<String> {
        var keys = Set([trip.coverPhotoReference].compactMap { $0 })
        for item in trip.days.flatMap({ $0.items }) {
            keys.formUnion(item.photoReferences ?? [])
            if let key = item.linkPreview?.imageReference { keys.insert(key) }
        }
        return keys
    }
}

@MainActor final class AccountPhotoStore {
    let codec: AccountPhotoCodec
    private let container: CKContainer?
    private var confirmed = Set<String>()
    private var boundOwner: String?
    private let binding: URL
    init(root suppliedRoot: URL? = nil) {
        let root = suppliedRoot ?? AccountWorkspace.root
        codec = AccountPhotoCodec(directory: root.appendingPathComponent("AccountPhotos"))
        binding = root.appendingPathComponent("photo-icloud-owner.txt")
        boundOwner = (try? String(contentsOf: binding, encoding: .utf8))
        container = RoamCloudSync.isConfigured ? CKContainer(identifier: RoamCloudSync.containerID) : nil
    }
    func verifyOwner() async throws {
        guard let container, try await container.accountStatus() == .available else { throw CKError(.notAuthenticated) }
        let owner = try await container.userRecordID().recordName
        boundOwner = (try? String(contentsOf: binding, encoding: .utf8)) ?? boundOwner
        guard boundOwner == nil || boundOwner == owner else { throw AccountError.wrongAccount }
        if boundOwner == nil {
            try FileManager.default.createDirectory(at: binding.deletingLastPathComponent(), withIntermediateDirectories: true)
            try owner.write(to: binding, atomically: true, encoding: .utf8)
            boundOwner = owner
        }
    }
    func synchronize(_ keys: Set<String>, user: String) async throws {
        guard !keys.isEmpty else { return }
        try AccountService.shared.checkOwner(user)
        try await verifyOwner()
        guard let database = container?.privateCloudDatabase else { throw CKError(.notAuthenticated) }
        for key in keys.sorted() {
            guard AccountPhotoCodec.valid(key) else { throw AccountError.invalidResponse }
            try AccountService.shared.checkOwner(user)
            let id = CKRecord.ID(recordName: "account-photo-\(user)-\(key)")
            if let local = codec.read(key) {
                if confirmed.contains(key) { continue }
                do {
                    let record = try await database.record(for: id)
                    guard let url = (record["payload"] as? CKAsset)?.fileURL, try Data(contentsOf: url) == local else { throw AccountError.invalidResponse }
                } catch let error as CKError where error.code == .unknownItem {
                    let record = CKRecord(recordType: "RoamLibrary", recordID: id)
                    record["payload"] = CKAsset(fileURL: codec.directory.appendingPathComponent(key))
                    try AccountService.shared.checkOwner(user)
                    try await verifyOwner()
                    do { _ = try await database.save(record) }
                    catch let error as CKError where error.code == .serverRecordChanged { continue }
                }
            } else {
                let record = try await database.record(for: id)
                guard let url = (record["payload"] as? CKAsset)?.fileURL else { throw AccountError.invalidResponse }
                let bytes = try Data(contentsOf: url)
                guard SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == key else { throw AccountError.invalidResponse }
                try await verifyOwner()
                try AccountService.shared.checkOwner(user)
                _ = try codec.cache(bytes)
            }
            try await verifyOwner()
            confirmed.insert(key)
        }
    }
}
