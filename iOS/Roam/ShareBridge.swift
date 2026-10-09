import Foundation

struct ShareDestination: Codable, Identifiable {
    struct Day: Codable, Identifiable { let id: UUID; let title: String }
    let id: UUID
    let title: String
    let days: [Day]
}
struct CollectedNote: Codable, Identifiable {
    var id = UUID()
    var title: String
    var text: String
    var tripID: UUID?
    var dayID: UUID?
    var preview: LinkPreview? = nil
}
enum ShareBridge {
    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.xiangchengjin.roam")?.appendingPathComponent("SharedNotes", isDirectory: true)
    }
    static func folder(_ override: URL?) throws -> URL {
        guard let url = override ?? directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func destinations(at directory: URL? = nil) -> [ShareDestination] {
        guard let url = try? folder(directory), let data = try? Data(contentsOf: url.appendingPathComponent("destinations.json")) else { return [] }
        return (try? JSONDecoder().decode([ShareDestination].self, from: data)) ?? []
    }
    static func publish(_ destinations: [ShareDestination], at directory: URL? = nil) throws {
        let url = try folder(directory).appendingPathComponent("destinations.json")
        try JSONEncoder().encode(destinations).write(to: url, options: .atomic)
    }
    static func save(_ note: CollectedNote, at directory: URL? = nil) throws {
        guard !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, note.text.count <= 100_000 else { throw CocoaError(.fileWriteInvalidFileName) }
        let url = try folder(directory).appendingPathComponent(note.id.uuidString + ".json")
        try JSONEncoder().encode(note).write(to: url, options: .atomic)
    }
    static func pending(at directory: URL? = nil) -> [CollectedNote] {
        guard let folder = try? folder(directory), let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.lastPathComponent != "destinations.json" && $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap {
            guard let data = try? Data(contentsOf: $0) else { return nil }
            return try? JSONDecoder().decode(CollectedNote.self, from: data)
        }
    }
    static func remove(_ id: UUID, at directory: URL? = nil) throws {
        try FileManager.default.removeItem(at: folder(directory).appendingPathComponent(id.uuidString + ".json"))
    }
}

struct LinkPreview: Codable, Equatable {
    var originalURL: URL
    var resolvedURL: URL?
    var title: String
    var summary: String = ""
    var author: String = ""
    var imageData: Data?
    var fetchedAt: Date?
    var failure: String?
    var source: String {
        let host = (resolvedURL ?? originalURL).host ?? AppLocalization.text("网页")
        if host == "xhslink.com" || host.hasSuffix(".xhslink.com") || host == "xiaohongshu.com" || host.hasSuffix(".xiaohongshu.com") { return AppLocalization.text("小红书") }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}
