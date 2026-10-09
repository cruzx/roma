import Foundation

enum JournalStorageError: Error {
    case invalidCloudDocument, invalidImage, unavailableLocalStorage, accountChanged
}

struct JournalItemVersion: Codable, Equatable {
    var item: StickerCanvasItem?
    var revision = UUID().uuidString
    var parent: String?
}

struct JournalCloudLibrary: Codable, Equatable {
    var schema = 1
    var items: [String: JournalItemVersion] = [:]
    var order: [String] = []
    var orderRevision = UUID().uuidString
    var viewport = StickerCanvasViewport()
    var viewportRevision = UUID().uuidString

    var visible: [StickerCanvasItem] {
        let keys = order + items.keys.filter { !order.contains($0) }.sorted()
        return keys.compactMap { items[$0]?.item }
    }

    var imageNames: Set<String> { Set(visible.compactMap(\.imageFile)) }

    func validated() throws {
        guard schema == 1, viewport.x.isFinite, viewport.y.isFinite,
              Set(order).count == order.count,
              order.allSatisfy({ UUID(uuidString: $0) != nil }),
              UUID(uuidString: orderRevision) != nil, UUID(uuidString: viewportRevision) != nil else {
            throw JournalStorageError.invalidCloudDocument
        }
        for (key, version) in items {
            guard UUID(uuidString: key) != nil, UUID(uuidString: version.revision) != nil,
                  version.parent.map({ UUID(uuidString: $0) != nil }) ?? true else {
                throw JournalStorageError.invalidCloudDocument
            }
            guard let item = version.item else { continue }
            guard item.id.uuidString == key, item.x.isFinite, item.y.isFinite,
                  item.scale.isFinite, item.rotation.isFinite, item.fontSize.isFinite,
                  item.aspectRatio.isFinite, item.aspectRatio > 0,
                  item.contours.allSatisfy({ $0.allSatisfy { $0.x.isFinite && $0.y.isFinite } }),
                  item.kind != .image || item.imageFile.map(Self.isSafeImageName) == true,
                  item.kind != .text || item.imageFile == nil else {
                throw JournalStorageError.invalidCloudDocument
            }
        }
    }

    static func isSafeImageName(_ name: String) -> Bool {
        name.hasSuffix(".png") && UUID(uuidString: String(name.dropLast(4))) != nil
    }
}

/// Stored in the same atomic document as the canvas, so a saved offline edit always has a revision.
struct JournalCloudLedger: Codable, Equatable {
    var library = JournalCloudLibrary()
    var pending = Set<String>()
    var orderPending = false
    var viewportPending = false
    var owner: String?

    var hasPendingChanges: Bool { !pending.isEmpty || orderPending || viewportPending }

    func validated() throws {
        try library.validated()
        guard pending.allSatisfy({ library.items[$0] != nil }), owner != "" else {
            throw JournalStorageError.invalidCloudDocument
        }
    }

    mutating func capture(_ items: [StickerCanvasItem], viewport: StickerCanvasViewport) {
        let ids = Set(items.map { $0.id.uuidString })
        for item in items {
            let key = item.id.uuidString
            guard library.items[key]?.item != item else { continue }
            let previous = library.items[key]
            library.items[key] = JournalItemVersion(item: item,
                parent: pending.contains(key) ? previous?.parent : previous?.revision)
            pending.insert(key)
        }
        for key in Array(library.items.keys) where !ids.contains(key) && library.items[key]?.item != nil {
            let previous = library.items[key]
            library.items[key] = JournalItemVersion(item: nil,
                parent: pending.contains(key) ? previous?.parent : previous?.revision)
            pending.insert(key)
        }
        let order = items.map { $0.id.uuidString }
        if order != library.order {
            library.order = order
            library.orderRevision = UUID().uuidString
            orderPending = true
        }
        if viewport != library.viewport {
            library.viewport = viewport
            library.viewportRevision = UUID().uuidString
            viewportPending = true
        }
    }

    /// Preserve concurrent content as another item; tombstones keep old devices from resurrecting deletes.
    @discardableResult
    mutating func merge(_ remote: JournalCloudLibrary) -> Int {
        var conflicts = 0
        for key in remote.items.keys.sorted() {
            let incoming = remote.items[key]!
            guard var local = library.items[key] else {
                library.items[key] = incoming
                continue
            }
            if local.revision == incoming.revision { continue }
            if local.item == incoming.item || !pending.contains(key) || incoming.parent == local.revision {
                library.items[key] = incoming
                pending.remove(key)
                continue
            }
            if local.parent == incoming.revision { continue }

            if var copy = incoming.item ?? local.item {
                copy.id = UUID()
                let copyKey = copy.id.uuidString
                library.items[copyKey] = JournalItemVersion(item: copy)
                library.order.append(copyKey)
                pending.insert(copyKey)
                orderPending = true
                library.orderRevision = UUID().uuidString
                conflicts += 1
            }
            if incoming.item == nil, local.item != nil {
                local.item = nil
                local.revision = UUID().uuidString
            }
            local.parent = incoming.revision
            library.items[key] = local
        }
        if !orderPending {
            library.order = remote.order + library.order.filter { !remote.order.contains($0) }
            library.orderRevision = remote.orderRevision
        } else {
            library.order += remote.order.filter { !library.order.contains($0) }
        }
        if !viewportPending || library.viewport == remote.viewport {
            library.viewport = remote.viewport
            library.viewportRevision = remote.viewportRevision
            viewportPending = false
        }
        return conflicts
    }

    /// An upload only acknowledges its own snapshot; changes made while awaiting CloudKit stay pending.
    mutating func acknowledge(_ outgoing: JournalCloudLibrary) {
        for (key, sent) in outgoing.items {
            if library.items[key]?.revision == sent.revision {
                pending.remove(key)
            } else if pending.contains(key), var current = library.items[key] {
                // The server now knows the intermediate edit, even if another local edit followed it.
                current.parent = sent.revision
                library.items[key] = current
            }
        }
        if library.orderRevision == outgoing.orderRevision { orderPending = false }
        if library.viewportRevision == outgoing.viewportRevision { viewportPending = false }
    }
}
