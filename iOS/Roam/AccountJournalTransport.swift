import Foundation
import CloudKit

@MainActor final class AccountJournalTransport: JournalCloudTransport {
    private let service = AccountService.shared
    func accountID() async throws -> String {
        let user = try await service.credential().user.id
        try service.checkOwner(user)
        return user
    }
    func fetchManifest() async throws -> JournalCloudSnapshot {
        guard let document = try await service.fetch("journal") else { return JournalCloudSnapshot() }
        let value = try document.decode(JournalCloudLibrary.self)
        guard value.schema == 1 else { throw JournalCloudSyncError.unsupportedSchema }
        try value.validated()
        return JournalCloudSnapshot(library: value, token: Data(String(document.revision).utf8))
    }
    func saveManifest(_ library: JournalCloudLibrary, replacing snapshot: JournalCloudSnapshot) async throws {
        try library.validated()
        let revision: Int
        if let token = snapshot.token {
            guard let text = String(data: token, encoding: .utf8), let parsed = Int(text), parsed > 0 else { throw AccountError.invalidResponse }
            revision = parsed
        } else { revision = 0 }
        do { try await service.put("journal", data: JSONEncoder().encode(library), replacing: revision) }
        catch AccountError.conflict { throw CKError(.serverRecordChanged) }
    }
    private lazy var photos = CloudKitJournalTransport()
    private let photoBinding = AccountPhotoStore()
    private func verifyPhotos() async throws {
        let user = try await service.credential().user.id
        try service.checkOwner(user)
        try await photoBinding.verifyOwner()
    }
    func downloadImage(named name: String) async throws -> Data {
        try await verifyPhotos()
        let data = try await photos.downloadImage(named: name)
        try await verifyPhotos()
        return data
    }
    func uploadImage(named name: String, data: Data) async throws {
        try await verifyPhotos()
        try await photos.uploadImage(named: name, data: data)
        try await verifyPhotos()
    }
}
