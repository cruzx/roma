import Combine
import CoreGraphics
import Foundation
import ImageIO

enum StickerBorderStyle: String, Codable, CaseIterable, Identifiable {
    case solid, dashed

    var id: String { rawValue }
    var title: String { localizedTitle }
    var localizedTitle: String { AppLocalization.text(self == .solid ? "实线" : "虚线") }
}

struct StickerCanvasItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case image, text
    }

    var id = UUID()
    var kind: Kind
    var x: Double = 0.5
    var y: Double = 0.5
    var scale: Double = 1
    var rotation: Double = 0
    var text: String = ""
    var textColor: String = "#1D1D1F"
    var fontSize: Double = 28
    var borderStyle: StickerBorderStyle = .solid
    // Optional storage keeps documents written before custom border colors decodable.
    var borderColor: String? = nil
    var imageFile: String?
    var contours: [[StickerOutlinePoint]] = []
    var aspectRatio: Double = 1

    var borderColorHex: String {
        guard let value = borderColor?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.hasPrefix("#"), value.utf8.count == 7,
              value.utf8.dropFirst().allSatisfy({ byte in
                  (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
              }) else { return "#FFFFFF" }
        return value.uppercased()
    }
}

/// World coordinates use the viewport's width and height as units, matching existing item positions.
struct StickerCanvasViewport: Codable, Equatable {
    var x: Double = 0
    var y: Double = 0
}

/// The array order is also the canvas stacking order; the last item is in front.
@MainActor
final class StickerBoardStore: ObservableObject {
    @Published private(set) var items: [StickerCanvasItem] = []
    @Published private(set) var viewport = StickerCanvasViewport()
    @Published var error: String?
    @Published private(set) var canUndoRemoval = false
    @Published var cloudStatus = "等待连接 iCloud"
    @Published var cloudLastSync: Date?
    private(set) var cloud: JournalCloudSync?
    private(set) var cloudLedger = JournalCloudLedger()
    var syncStorageAvailable: Bool { !failedToLoad }

    private struct Document: Codable {
        var version = 3
        var items: [StickerCanvasItem]
        var viewport: StickerCanvasViewport
        var cloud: JournalCloudLedger?

        private enum CodingKeys: String, CodingKey { case version, items, viewport, cloud }

        init(items: [StickerCanvasItem], viewport: StickerCanvasViewport, cloud: JournalCloudLedger) {
            self.items = items
            self.viewport = viewport
            self.cloud = cloud
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            items = try container.decode([StickerCanvasItem].self, forKey: .items)
            if version == 1 {
                viewport = try container.decodeIfPresent(StickerCanvasViewport.self, forKey: .viewport) ?? StickerCanvasViewport()
            } else {
                viewport = try container.decode(StickerCanvasViewport.self, forKey: .viewport)
            }
            // Old boards migrate in memory first; reading alone never rewrites their files.
            cloud = version >= 3 ? try container.decode(JournalCloudLedger.self, forKey: .cloud) : nil
        }
    }

    private struct RemovedItem {
        var item: StickerCanvasItem
        var index: Int
    }

    private enum StorageError: LocalizedError {
        case invalidDocument
        case emptyImage
        case invalidViewport

        var errorDescription: String? {
            switch self {
            case .invalidDocument: AppLocalization.text("画布文件暂时无法读取，原文件已保留。")
            case .emptyImage: AppLocalization.text("照片没有生成可保存的贴纸，请重新拍摄。")
            case .invalidViewport: AppLocalization.text("画布位置无效，请重试。")
            }
        }
    }

    private let directory: URL
    private var documentURL: URL { directory.appendingPathComponent("board.json") }
    private var failedToLoad = false
    private var lastRemoval: RemovedItem?
    private var cloudImagePins = Set<String>()
    private struct ImageStamp: Equatable { var size: UInt64; var modified: Date }
    private var verifiedCloudImages: [String: ImageStamp] = [:]
    private static let coordinateLimits: ClosedRange<Double> = -1_000_000...1_000_000

    init(directory: URL? = nil, testing: Bool = false, reset: Bool = false) {
        if let directory {
            self.directory = directory
        } else if testing {
            self.directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("roam-stickers-ui-tests", isDirectory: true)
        } else {
            self.directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Roam", isDirectory: true)
                .appendingPathComponent("Stickers", isDirectory: true)
        }

        // A launch argument must never erase the production board.
        if reset && (directory != nil || testing), FileManager.default.fileExists(atPath: self.directory.path) {
            do {
                try FileManager.default.removeItem(at: self.directory)
            } catch {
                self.error = AppLocalization.format("无法重置测试画布：%@", error.localizedDescription)
                failedToLoad = true
                return
            }
        }
        reload()
        if directory == nil && !testing {
            cloud = JournalCloudSync(store: self)
            cloud?.start()
        }
    }

    /// Retry after a temporary storage issue. A decode failure never rewrites the file.
    func reload() {
        do {
            let loaded: [StickerCanvasItem]
            let loadedViewport: StickerCanvasViewport
            var loadedLedger: JournalCloudLedger
            if FileManager.default.fileExists(atPath: documentURL.path) {
                let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: documentURL))
                guard (1...3).contains(document.version), Set(document.items.map(\.id)).count == document.items.count,
                      document.viewport.x.isFinite, document.viewport.y.isFinite else {
                    throw StorageError.invalidDocument
                }
                guard document.items.allSatisfy({ item in
                    item.kind != .image || item.imageFile.map(Self.isSafeImageName) == true
                }) else {
                    throw StorageError.invalidDocument
                }
                loaded = document.items.map(Self.normalized)
                loadedViewport = Self.normalized(document.viewport)
                loadedLedger = document.cloud ?? JournalCloudLedger()
                try loadedLedger.validated()
            } else {
                loaded = []
                loadedViewport = StickerCanvasViewport()
                loadedLedger = JournalCloudLedger()
            }
            loadedLedger.capture(loaded, viewport: loadedViewport)
            items = loaded
            viewport = loadedViewport
            cloudLedger = loadedLedger
            failedToLoad = false
            error = nil
            lastRemoval = nil
            canUndoRemoval = false
            removeUnusedImages()
        } catch {
            failedToLoad = true
            self.error = AppLocalization.format("无法读取贴纸画布，原文件已保留：%@", error.localizedDescription)
        }
    }

    @discardableResult
    func addSticker(_ cutout: StickerCutout, at point: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> UUID? {
        guard readyToSave() else { return nil }
        guard !cutout.pngData.isEmpty else {
            error = StorageError.emptyImage.localizedDescription
            return nil
        }
        var item = StickerCanvasItem(kind: .image, x: Double(point.x), y: Double(point.y))
        item.imageFile = "\(item.id.uuidString).png"
        item.contours = cutout.contours
        item.aspectRatio = cutout.aspectRatio
        item = Self.normalized(item)
        guard let imageURL = imageURL(for: item) else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Persist the pixels first, so committed metadata never points to a future write.
            try cutout.pngData.write(to: imageURL, options: .atomic)
        } catch {
            self.error = AppLocalization.format("贴纸未能保存，请稍后重试：%@", error.localizedDescription)
            return nil
        }
        guard commit(items + [item]) else {
            try? FileManager.default.removeItem(at: imageURL)
            return nil
        }
        return item.id
    }

    @discardableResult
    func addText(_ text: String, at point: CGPoint, color: String, fontSize: Double) -> UUID? {
        guard readyToSave() else { return nil }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let item = Self.normalized(StickerCanvasItem(
            kind: .text, x: Double(point.x), y: Double(point.y),
            text: text, textColor: color, fontSize: fontSize
        ))
        return commit(items + [item]) ? item.id : nil
    }

    func update(_ item: StickerCanvasItem) {
        guard readyToSave(), let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = Self.normalized(item)
        // Editing geometry or text must not switch the asset or its type.
        updated.kind = items[index].kind
        updated.imageFile = items[index].imageFile
        guard updated != items[index] else { return }
        var next = items
        next[index] = updated
        commit(next)
    }

    func remove(_ id: UUID) {
        guard readyToSave(), let index = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = RemovedItem(item: items[index], index: index)
        var next = items
        next.remove(at: index)
        guard commit(next) else { return }
        lastRemoval = removed
        canUndoRemoval = true
        removeUnusedImages()
    }

    func undoLastRemoval() {
        guard readyToSave(), let removal = lastRemoval else { return }
        guard !items.contains(where: { $0.id == removal.item.id }) else { return }
        var next = items
        next.insert(removal.item, at: min(removal.index, next.count))
        guard commit(next) else { return }
        lastRemoval = nil
        canUndoRemoval = false
    }

    func bringToFront(_ id: UUID) {
        guard readyToSave(), let index = items.firstIndex(where: { $0.id == id }), index != items.count - 1 else { return }
        var next = items
        let item = next.remove(at: index)
        next.append(item)
        commit(next)
    }

    /// Persist a finished pan without changing any item coordinates or image files.
    func moveViewport(to position: StickerCanvasViewport) {
        guard readyToSave() else { return }
        guard position.x.isFinite, position.y.isFinite else {
            error = StorageError.invalidViewport.localizedDescription
            return
        }
        let next = Self.normalized(position)
        guard next != viewport else { return }
        commit(items, viewport: next)
    }

    func imageURL(for item: StickerCanvasItem) -> URL? {
        guard item.kind == .image, let name = item.imageFile, Self.isSafeImageName(name) else { return nil }
        return directory.appendingPathComponent(name)
    }

    private func readyToSave() -> Bool {
        if failedToLoad { reload() }
        return !failedToLoad
    }

    @discardableResult
    private func commit(_ next: [StickerCanvasItem], viewport nextViewport: StickerCanvasViewport? = nil) -> Bool {
        do {
            let savedViewport = nextViewport ?? viewport
            var nextLedger = cloudLedger
            nextLedger.capture(next, viewport: savedViewport)
            try writeDocument(items: next, viewport: savedViewport, ledger: nextLedger)
            cloudLedger = nextLedger
            if items != next { items = next }
            if viewport != savedViewport { viewport = savedViewport }
            error = nil
            if cloud != nil { cloudStatus = "更改已保存在本机，等待同步" }
            cloud?.localChanged()
            return true
        } catch {
            self.error = AppLocalization.format("画布未能保存，请稍后重试：%@", error.localizedDescription)
            return false
        }
    }

    private static func isSafeImageName(_ name: String) -> Bool {
        guard name.hasSuffix(".png") else { return false }
        return UUID(uuidString: String(name.dropLast(4))) != nil
    }

    private func writeDocument(items: [StickerCanvasItem], viewport: StickerCanvasViewport,
                               ledger: JournalCloudLedger) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Document(items: items, viewport: viewport, cloud: ledger))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: documentURL, options: .atomic)
    }

    func bindCloudOwner(_ owner: String) throws {
        guard syncStorageAvailable else { throw JournalStorageError.unavailableLocalStorage }
        guard !owner.isEmpty, cloudLedger.owner == nil || cloudLedger.owner == owner else {
            throw JournalStorageError.accountChanged
        }
        guard cloudLedger.owner != owner else { return }
        var next = cloudLedger
        next.owner = owner
        try writeDocument(items: items, viewport: viewport, ledger: next)
        cloudLedger = next
    }

    @discardableResult
    func mergeCloud(_ remote: JournalCloudLibrary, images: [String: Data]) throws -> Int {
        guard syncStorageAvailable else { throw JournalStorageError.unavailableLocalStorage }
        try remote.validated()
        // Compute against the live ledger: the user may have edited while images downloaded.
        var merged = cloudLedger
        let conflicts = merged.merge(remote)
        let nextItems = merged.library.visible.map(Self.normalized)
        let nextViewport = Self.normalized(merged.library.viewport)
        merged.capture(nextItems, viewport: nextViewport)

        // Validate the entire batch before writing anything referenced by the new document.
        for name in merged.library.imageNames where !hasCloudImage(named: name) {
            guard let data = images[name], Self.isValidPNG(data) else { throw JournalStorageError.invalidImage }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in merged.library.imageNames where !hasCloudImage(named: name) {
            guard let url = imageURL(named: name), let data = images[name] else { throw JournalStorageError.invalidImage }
            try data.write(to: url, options: .atomic)
        }
        if merged != cloudLedger || nextItems != items || nextViewport != viewport {
            try writeDocument(items: nextItems, viewport: nextViewport, ledger: merged)
        }
        cloudLedger = merged
        if items != nextItems { items = nextItems }
        if viewport != nextViewport { viewport = nextViewport }
        // A local undo remains available; its immutable pixels stay retained separately.
        removeUnusedImages()
        return conflicts
    }

    func acknowledgeCloud(_ outgoing: JournalCloudLibrary) throws {
        guard syncStorageAvailable else { throw JournalStorageError.unavailableLocalStorage }
        var next = cloudLedger
        next.acknowledge(outgoing)
        try writeDocument(items: items, viewport: viewport, ledger: next)
        cloudLedger = next
    }

    func imageURL(named name: String) -> URL? {
        guard Self.isSafeImageName(name) else { return nil }
        return directory.appendingPathComponent(name)
    }

    func hasCloudImage(named name: String) -> Bool {
        guard let url = imageURL(named: name),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modified = attributes[.modificationDate] as? Date else { return false }
        let stamp = ImageStamp(size: size, modified: modified)
        if verifiedCloudImages[name] == stamp { return true }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), Self.isValidPNG(data) else {
            verifiedCloudImages.removeValue(forKey: name)
            return false
        }
        verifiedCloudImages[name] = stamp
        return true
    }

    func pinCloudImages(_ names: Set<String>) { cloudImagePins.formUnion(names) }
    func unpinCloudImages() {
        cloudImagePins.removeAll()
        if syncStorageAvailable { removeUnusedImages() }
    }

    private static func isValidPNG(_ data: Data) -> Bool {
        guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else { return false }
        return image.width > 0 && image.height > 0
    }

    private static func normalized(_ viewport: StickerCanvasViewport) -> StickerCanvasViewport {
        StickerCanvasViewport(
            x: min(coordinateLimits.upperBound, max(coordinateLimits.lowerBound, viewport.x)),
            y: min(coordinateLimits.upperBound, max(coordinateLimits.lowerBound, viewport.y))
        )
    }

    private static func normalized(_ item: StickerCanvasItem) -> StickerCanvasItem {
        func clamped(_ value: Double, to limits: ClosedRange<Double>, fallback: Double) -> Double {
            value.isFinite ? min(limits.upperBound, max(limits.lowerBound, value)) : fallback
        }
        var item = item
        item.x = clamped(item.x, to: coordinateLimits, fallback: 0.5)
        item.y = clamped(item.y, to: coordinateLimits, fallback: 0.5)
        item.scale = clamped(item.scale, to: 0.35...3, fallback: 1)
        item.rotation = item.rotation.isFinite ? item.rotation.truncatingRemainder(dividingBy: 360) : 0
        item.fontSize = clamped(item.fontSize, to: 12...96, fallback: 28)
        item.aspectRatio = clamped(item.aspectRatio, to: 0.05...20, fallback: 1)
        if item.borderColor != nil { item.borderColor = item.borderColorHex }
        item.contours = item.contours.map { contour in
            contour.map { point in
                StickerOutlinePoint(
                    x: clamped(point.x, to: 0...1, fallback: 0),
                    y: clamped(point.y, to: 0...1, fallback: 0)
                )
            }
        }
        return item
    }

    private func removeUnusedImages() {
        // Keep the most recent removal's pixels until its undo opportunity has ended.
        var retained = Set(items.compactMap(\.imageFile))
        retained.formUnion(cloudImagePins)
        if let name = lastRemoval?.item.imageFile { retained.insert(name) }
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where Self.isSafeImageName(file.lastPathComponent) && !retained.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
            verifiedCloudImages.removeValue(forKey: file.lastPathComponent)
        }
    }
}
