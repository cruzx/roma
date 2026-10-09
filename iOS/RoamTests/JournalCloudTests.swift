import CloudKit
import CoreGraphics
import XCTest
@testable import Roam

@MainActor
final class JournalCloudTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("roam-journal-cloud-\(UUID().uuidString)")
    }

    private var cutout: StickerCutout {
        StickerCutout(
            pngData: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")!,
            contours: [[StickerOutlinePoint(x: 0, y: 0), StickerOutlinePoint(x: 1, y: 0), StickerOutlinePoint(x: 1, y: 1)]],
            aspectRatio: 1
        )
    }

    private func text(_ content: String) -> StickerCanvasItem {
        StickerCanvasItem(kind: .text, text: content)
    }

    private func settled(_ items: [StickerCanvasItem], viewport: StickerCanvasViewport = .init()) -> JournalCloudLedger {
        var ledger = JournalCloudLedger()
        ledger.capture(items, viewport: viewport)
        ledger.acknowledge(ledger.library)
        return ledger
    }

    func testIndependentItemEditsMergeWithoutLosingEitherChange() {
        let first = text("东京"), second = text("京都")
        let base = settled([first, second])
        var phone = base, tablet = base
        var editedFirst = first, editedSecond = second
        editedFirst.x = -3.25
        editedSecond.text = "雨中的京都"
        phone.capture([editedFirst, second], viewport: .init())
        tablet.capture([first, editedSecond], viewport: .init())

        XCTAssertEqual(phone.merge(tablet.library), 0)
        XCTAssertEqual(phone.library.visible, [editedFirst, editedSecond])
        XCTAssertTrue(phone.hasPendingChanges)
    }

    func testSameItemConflictPreservesBothVersionsOnlyOnce() {
        let original = text("同一段记忆")
        let base = settled([original])
        var first = base, second = base
        var local = original, remote = original
        local.text = "手机修改"
        remote.text = "平板修改"
        first.capture([local], viewport: .init())
        second.capture([remote], viewport: .init())

        XCTAssertEqual(first.merge(second.library), 1)
        XCTAssertEqual(Set(first.library.visible.map(\.text)), [local.text, remote.text])
        let preservedIDs = first.library.visible.map(\.id)
        XCTAssertEqual(first.merge(second.library), 0)
        XCTAssertEqual(first.library.visible.map(\.id), preservedIDs)
        XCTAssertEqual(Set(preservedIDs).count, 2)
    }

    func testDeletionWinsOverUneditedCopyButPreservesAnOfflineEdit() {
        let original = text("不能丢失的记忆")
        let base = settled([original])
        var deleted = base, unchanged = base, edited = base
        deleted.capture([], viewport: .init())
        XCTAssertEqual(unchanged.merge(deleted.library), 0)
        XCTAssertTrue(unchanged.library.visible.isEmpty)

        var changed = original
        changed.text = "离线补充"
        edited.capture([changed], viewport: .init())
        XCTAssertEqual(edited.merge(deleted.library), 1)
        XCTAssertEqual(edited.library.visible.count, 1)
        XCTAssertEqual(edited.library.visible.first?.text, changed.text)
        XCTAssertNotEqual(edited.library.visible.first?.id, original.id)
        XCTAssertEqual(edited.merge(deleted.library), 0)
        XCTAssertEqual(edited.library.visible.count, 1)
    }

    func testAcknowledgingOlderUploadKeepsNewerItemOrderAndViewportPending() {
        let first = text("先前内容"), second = text("另一张")
        var ledger = settled([first, second])
        var sending = first
        sending.text = "上传版本"
        ledger.capture([sending, second], viewport: .init(x: 2, y: 0))
        let inFlight = ledger.library
        sending.text = "上传过程中继续输入"
        ledger.capture([second, sending], viewport: .init(x: -4, y: 0))
        ledger.acknowledge(inFlight)

        XCTAssertEqual(ledger.library.visible, [second, sending])
        XCTAssertTrue(ledger.pending.contains(first.id.uuidString))
        XCTAssertTrue(ledger.orderPending)
        XCTAssertTrue(ledger.viewportPending)
        XCTAssertTrue(ledger.hasPendingChanges)
        ledger.acknowledge(ledger.library)
        XCTAssertFalse(ledger.hasPendingChanges)
    }

    func testIdenticalFirstImportDoesNotCreateConflictCopies() {
        let original = text("同一份本机手账")
        var first = JournalCloudLedger(), second = JournalCloudLedger()
        first.capture([original], viewport: .init())
        second.capture([original], viewport: .init())
        XCTAssertEqual(first.merge(second.library), 0)
        XCTAssertEqual(first.library.visible, [original])
    }

    func testLegacyBoardMigrationKeepsPixelsAndMakesExistingContentsPending() throws {
        struct LegacyDocument: Encodable {
            var version = 1
            var items: [StickerCanvasItem]
        }
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var image = StickerCanvasItem(kind: .image, x: -2, y: 0.7)
        image.imageFile = "\(image.id.uuidString).png"
        image.contours = cutout.contours
        let originalItems = [image, text("旧手账")]
        let boardURL = directory.appendingPathComponent("board.json")
        let imageURL = directory.appendingPathComponent(try XCTUnwrap(image.imageFile))
        let legacyData = try JSONEncoder().encode(LegacyDocument(items: originalItems))
        try legacyData.write(to: boardURL)
        try cutout.pngData.write(to: imageURL)

        let store = StickerBoardStore(directory: directory)
        XCTAssertTrue(store.syncStorageAvailable)
        XCTAssertNil(store.error)
        XCTAssertEqual(store.items, originalItems)
        XCTAssertTrue(store.cloudLedger.hasPendingChanges)
        XCTAssertEqual(try Data(contentsOf: boardURL), legacyData, "Reading an older board must not rewrite it")
        try store.bindCloudOwner("owner-A")
        let restored = StickerBoardStore(directory: directory)
        XCTAssertEqual(restored.items, originalItems)
        XCTAssertEqual(restored.cloudLedger.owner, "owner-A")
        XCTAssertEqual(restored.cloudLedger.pending, store.cloudLedger.pending)
        XCTAssertEqual(try Data(contentsOf: imageURL), cutout.pngData)
    }

    func testUnreadableBoardCannotBeReplacedByCloudData() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let boardURL = directory.appendingPathComponent("board.json")
        let broken = Data("partially written document".utf8)
        try broken.write(to: boardURL)
        let store = StickerBoardStore(directory: directory)
        let cloud = settled([text("云端内容")]).library
        XCTAssertFalse(store.syncStorageAvailable)
        XCTAssertThrowsError(try store.mergeCloud(cloud, images: [:]))
        XCTAssertEqual(try Data(contentsOf: boardURL), broken)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testMissingOrInvalidDownloadedPhotoDoesNotReplaceExistingBoard() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        store.addText("本机内容", at: .init(x: 0.5, y: 0.5), color: "#ABCDEF", fontSize: 32)
        let originalItems = store.items
        let boardURL = directory.appendingPathComponent("board.json")
        let originalData = try Data(contentsOf: boardURL)
        var remotePhoto = StickerCanvasItem(kind: .image)
        let name = "\(remotePhoto.id.uuidString).png"
        remotePhoto.imageFile = name
        let remote = settled([remotePhoto]).library

        XCTAssertThrowsError(try store.mergeCloud(remote, images: [:]))
        XCTAssertThrowsError(try store.mergeCloud(remote, images: [name: Data("not a PNG".utf8)]))
        XCTAssertEqual(store.items, originalItems)
        XCTAssertEqual(try Data(contentsOf: boardURL), originalData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path))
    }

    func testCloudOwnerChangeIsRejectedWithoutRebindingExistingContents() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        store.addText("我的手账", at: .init(x: 0.2, y: 0.6), color: "#1D1D1F", fontSize: 28)
        try store.bindCloudOwner("owner-A")
        let boardURL = directory.appendingPathComponent("board.json")
        let saved = try Data(contentsOf: boardURL)
        XCTAssertThrowsError(try store.bindCloudOwner("owner-B"))
        XCTAssertEqual(store.cloudLedger.owner, "owner-A")
        XCTAssertEqual(try Data(contentsOf: boardURL), saved)
        XCTAssertEqual(StickerBoardStore(directory: directory).cloudLedger.owner, "owner-A")
    }

    func testCloudRoundTripRestoresPhotosTextOrderAndViewport() async throws {
        let firstDirectory = temporaryDirectory(), secondDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstDirectory)
            try? FileManager.default.removeItem(at: secondDirectory)
        }
        let first = StickerBoardStore(directory: firstDirectory)
        let photoID = try XCTUnwrap(first.addSticker(cutout, at: .init(x: -3.25, y: 0.75)))
        first.addText("旅行日记 Travel Journal", at: .init(x: 4.6, y: 0.2), color: "#AB5290", fontSize: 43)
        var photo = try XCTUnwrap(first.items.first { $0.id == photoID })
        photo.scale = 1.8
        photo.rotation = -37
        photo.borderColor = "#70B8E8"
        photo.borderStyle = .dashed
        first.update(photo)
        first.bringToFront(photoID)
        first.moveViewport(to: .init(x: 4.25, y: -0.5))
        let remote = MemoryJournalTransport()
        let firstSync = JournalCloudSync(store: first, transport: remote)
        await firstSync.synchronize()
        XCTAssertNotNil(remote.snapshot.library)
        XCTAssertFalse(first.cloudLedger.hasPendingChanges)
        XCTAssertEqual(remote.events.first, "image", "The manifest cannot become visible before its pixels")
        XCTAssertEqual(remote.events.last, "manifest")

        let second = StickerBoardStore(directory: secondDirectory)
        await JournalCloudSync(store: second, transport: remote).synchronize()
        XCTAssertEqual(second.items, first.items)
        XCTAssertEqual(second.viewport, first.viewport)
        XCTAssertFalse(second.cloudLedger.hasPendingChanges)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(second.imageURL(for: photo))), cutout.pngData)
        let relaunched = StickerBoardStore(directory: secondDirectory)
        XCTAssertEqual(relaunched.items, first.items)
        XCTAssertEqual(relaunched.viewport, first.viewport)
        XCTAssertEqual(relaunched.cloudLedger.owner, remote.owner)
    }

    func testEditingDuringFetchUsesCurrentLocalContentsForMergeAndUpload() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        store.addText("初始文字", at: .init(x: 0.5, y: 0.5), color: "#1D1D1F", fontSize: 28)
        let remote = MemoryJournalTransport()
        let sync = JournalCloudSync(store: store, transport: remote)
        await sync.synchronize()
        remote.onFetch = {
            var changed = store.items[0]
            changed.text = "等待读取期间输入的新文字"
            store.update(changed)
            store.moveViewport(to: .init(x: 6.5, y: 0))
        }
        await sync.synchronize()
        XCTAssertEqual(store.items.first?.text, "等待读取期间输入的新文字")
        XCTAssertEqual(remote.snapshot.library?.visible, store.items)
        XCTAssertFalse(store.cloudLedger.hasPendingChanges)
        XCTAssertEqual(StickerBoardStore(directory: directory).items, store.items)
    }

    func testEditingDuringUploadIsNotAcknowledgedAsTheOlderVersion() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        store.addText("正在上传", at: .init(x: 0.5, y: 0.5), color: "#1D1D1F", fontSize: 28)
        let remote = MemoryJournalTransport()
        remote.onSave = {
            var changed = store.items[0]
            changed.text = "上传时的新修改"
            store.update(changed)
        }
        let sync = JournalCloudSync(store: store, transport: remote)
        await sync.synchronize()
        XCTAssertEqual(store.items.first?.text, "上传时的新修改")
        XCTAssertEqual(remote.snapshot.library?.visible.first?.text, "正在上传")
        XCTAssertTrue(store.cloudLedger.hasPendingChanges)
        XCTAssertTrue(StickerBoardStore(directory: directory).cloudLedger.hasPendingChanges)
        await sync.synchronize()
        XCTAssertEqual(remote.snapshot.library?.visible, store.items)
        XCTAssertFalse(store.cloudLedger.hasPendingChanges)
        XCTAssertEqual(store.items.count, 1)
    }

    func testOfflineFailurePreservesLocalDataAndPendingWorkAfterRelaunch() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        store.addText("离线也不会丢", at: .init(x: -5, y: 0.7), color: "#ABCD12", fontSize: 34)
        let remote = MemoryJournalTransport()
        remote.fetchFailure = URLError(.notConnectedToInternet)
        await JournalCloudSync(store: store, transport: remote).synchronize()
        XCTAssertEqual(remote.events, [])
        XCTAssertNil(remote.snapshot.library)
        let restored = StickerBoardStore(directory: directory)
        XCTAssertEqual(restored.items, store.items)
        XCTAssertTrue(restored.cloudLedger.hasPendingChanges)
        remote.fetchFailure = nil
        await JournalCloudSync(store: restored, transport: remote).synchronize()
        XCTAssertEqual(remote.snapshot.library?.visible, restored.items)
        XCTAssertFalse(restored.cloudLedger.hasPendingChanges)
    }

    func testDeletionDuringPhotoUploadKeepsPixelsUntilTheInFlightManifestFinishes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        let imageID = try XCTUnwrap(store.addSticker(cutout))
        let textID = try XCTUnwrap(store.addText("另一项", at: .init(x: 0.5, y: 0.5), color: "#1D1D1F", fontSize: 28))
        let image = try XCTUnwrap(store.items.first { $0.id == imageID })
        let imageURL = try XCTUnwrap(store.imageURL(for: image))
        let remote = MemoryJournalTransport()
        remote.onUpload = {
            store.remove(imageID)
            store.remove(textID) // The photo is no longer retained by the single-item undo slot.
            XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
        }
        let sync = JournalCloudSync(store: store, transport: remote)
        await sync.synchronize()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.cloudLedger.hasPendingChanges)
        XCTAssertEqual(remote.snapshot.library?.visible.count, 2)
        XCTAssertEqual(remote.images[try XCTUnwrap(image.imageFile)], cutout.pngData)
        await sync.synchronize()
        XCTAssertEqual(remote.snapshot.library?.visible.count, 0)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(store.cloudLedger.hasPendingChanges)
        XCTAssertTrue(StickerBoardStore(directory: directory).items.isEmpty)
    }

    func testStartAndDebouncedLocalChangesSynchronizeAutomatically() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        store.addText("打开手账即同步", at: .init(x: 0.5, y: 0.5), color: "#1D1D1F", fontSize: 28)
        let remote = MemoryJournalTransport()
        let sync = JournalCloudSync(store: store, transport: remote)
        let deadline = Date().addingTimeInterval(2.8)
        sync.start()
        let initiallySynced = try await waitUntil(deadline: deadline) {
            remote.snapshot.library?.visible == store.items && !store.cloudLedger.hasPendingChanges
        }
        XCTAssertTrue(initiallySynced, "Starting the engine must sync without an explicit synchronize call")
        guard initiallySynced else { return }
        for revision in 1...3 {
            var changed = store.items[0]
            changed.text = "连续编辑 \(revision)"
            store.update(changed)
            sync.localChanged()
            await Task.yield()
        }
        XCTAssertEqual(remote.events.filter { $0 == "manifest" }.count, 1,
                       "Rapid edit notifications must not publish intermediate manifests")
        let editsSynced = try await waitUntil(deadline: deadline) {
            remote.snapshot.library?.visible == store.items && !store.cloudLedger.hasPendingChanges
        }
        XCTAssertTrue(editsSynced, "The debounced edit should sync automatically within the shared 2.8-second deadline")
        XCTAssertEqual(remote.snapshot.library?.visible.first?.text, "连续编辑 3")
        XCTAssertEqual(remote.events.filter { $0 == "manifest" }.count, 2)
    }

    func testConfirmedPhotoIsNotUploadedAgainForTextOrGeometryChanges() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        let photoID = try XCTUnwrap(store.addSticker(cutout))
        let textID = try XCTUnwrap(store.addText("原文字", at: .init(x: 0.5, y: 0.5), color: "#1D1D1F", fontSize: 28))
        let remote = MemoryJournalTransport()
        let sync = JournalCloudSync(store: store, transport: remote)
        await sync.synchronize()
        XCTAssertEqual(remote.events.filter { $0 == "image" }.count, 1)

        var photo = try XCTUnwrap(store.items.first { $0.id == photoID })
        photo.x = -5.25
        photo.scale = 2
        photo.rotation = 19
        store.update(photo)
        var words = try XCTUnwrap(store.items.first { $0.id == textID })
        words.text = "只改文字和位置"
        store.update(words)
        await sync.synchronize()
        XCTAssertEqual(remote.snapshot.library?.visible, store.items)
        XCTAssertFalse(store.cloudLedger.hasPendingChanges)
        XCTAssertEqual(remote.events.filter { $0 == "manifest" }.count, 2)
        XCTAssertEqual(remote.events.filter { $0 == "image" }.count, 1,
                       "An acknowledged immutable PNG should be reused across manifest revisions")
    }

    func testConcurrentManifestWriteRetriesAndMergesIndependentRemoteEdit() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        let firstID = try XCTUnwrap(store.addText("手机编辑的文字", at: .init(x: 0.2, y: 0.3), color: "#1D1D1F", fontSize: 28))
        let secondID = try XCTUnwrap(store.addText("另一台设备的文字", at: .init(x: 0.7, y: 0.8), color: "#1D1D1F", fontSize: 28))
        let remote = MemoryJournalTransport()
        let sync = JournalCloudSync(store: store, transport: remote)
        await sync.synchronize()
        var otherDevice = store.cloudLedger
        var otherItems = store.items
        let secondIndex = try XCTUnwrap(otherItems.firstIndex { $0.id == secondID })
        otherItems[secondIndex].text = "云端先保存的独立修改"
        otherDevice.capture(otherItems, viewport: store.viewport)
        let concurrentManifest = otherDevice.library
        var local = try XCTUnwrap(store.items.first { $0.id == firstID })
        local.text = "本机不能被覆盖的修改"
        store.update(local)
        remote.onSave = { remote.replaceManifest(concurrentManifest) }

        await sync.synchronize()
        XCTAssertEqual(remote.saveAttempts, 3, "One initial write, one stale-token rejection, and one retried write")
        XCTAssertEqual(remote.fetchCount, 3, "The conflict must cause a fresh read of the other device's revision")
        XCTAssertEqual(store.items.first { $0.id == firstID }?.text, local.text)
        XCTAssertEqual(store.items.first { $0.id == secondID }?.text, "云端先保存的独立修改")
        XCTAssertEqual(store.items.count, 2, "Independent edits do not need conflict copies")
        XCTAssertEqual(remote.snapshot.library?.visible, store.items)
        XCTAssertFalse(store.cloudLedger.hasPendingChanges)
    }

    func testVersionThreeWithCorruptCloudMetadataFailsClosedAndPreservesFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = StickerBoardStore(directory: directory)
        source.addText("有效的本机文字", at: .init(x: 0.5, y: 0.5), color: "#1D1D1F", fontSize: 28)
        let boardURL = directory.appendingPathComponent("board.json")
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: boardURL)) as? [String: Any])
        XCTAssertEqual(document["version"] as? Int, 3)
        var cloud = try XCTUnwrap(document["cloud"] as? [String: Any])
        var library = try XCTUnwrap(cloud["library"] as? [String: Any])
        library["orderRevision"] = "corrupt revision"
        cloud["library"] = library
        document["cloud"] = cloud
        let corrupted = try JSONSerialization.data(withJSONObject: document, options: .sortedKeys)
        try corrupted.write(to: boardURL, options: .atomic)

        let restored = StickerBoardStore(directory: directory)
        XCTAssertFalse(restored.syncStorageAvailable)
        XCTAssertNotNil(restored.error)
        XCTAssertNil(restored.addText("不可覆盖", at: .init(x: 0.5, y: 0.5), color: "#1D1D1F", fontSize: 28))
        XCTAssertThrowsError(try restored.mergeCloud(settled([text("云端内容")]).library, images: [:]))
        XCTAssertEqual(try Data(contentsOf: boardURL), corrupted)
    }

    private func waitUntil(deadline: Date, condition: () -> Bool) async throws -> Bool {
        while !condition() && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    func testAccountSwitchDuringFetchNeverAppliesOrUploadsOtherAccountsData() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerBoardStore(directory: directory)
        store.addText("属于账户 A", at: .init(x: 0.5, y: 0.5), color: "#1D1D1F", fontSize: 28)
        let original = store.items
        let remote = MemoryJournalTransport()
        remote.snapshot = JournalCloudSnapshot(library: settled([text("不应导入的内容")]).library, token: Data([1]))
        remote.onFetch = { remote.owner = "owner-B" }
        await JournalCloudSync(store: store, transport: remote).synchronize()
        XCTAssertEqual(store.items, original)
        XCTAssertEqual(store.cloudLedger.owner, "owner-A")
        XCTAssertTrue(store.cloudLedger.hasPendingChanges)
        XCTAssertTrue(remote.events.isEmpty)
    }
}

@MainActor
private final class MemoryJournalTransport: JournalCloudTransport {
    var owner = "owner-A"
    var snapshot = JournalCloudSnapshot()
    var images: [String: Data] = [:]
    var events: [String] = []
    private(set) var fetchCount = 0
    private(set) var saveAttempts = 0
    var fetchFailure: Error?
    var onFetch: (() -> Void)?
    var onSave: (() -> Void)?
    var onUpload: (() -> Void)?
    private var generation: UInt8 = 0

    func accountID() async throws -> String { owner }

    func fetchManifest() async throws -> JournalCloudSnapshot {
        fetchCount += 1
        if let fetchFailure { throw fetchFailure }
        let result = snapshot
        let callback = onFetch
        onFetch = nil
        await Task.yield()
        callback?()
        return result
    }

    func saveManifest(_ library: JournalCloudLibrary, replacing previous: JournalCloudSnapshot) async throws {
        saveAttempts += 1
        let callback = onSave
        onSave = nil
        await Task.yield()
        callback?()
        guard previous.token == snapshot.token else { throw CKError(.serverRecordChanged) }
        replaceManifest(library)
        events.append("manifest")
    }

    func replaceManifest(_ library: JournalCloudLibrary) {
        generation &+= 1
        snapshot = JournalCloudSnapshot(library: library, token: Data([generation]))
    }

    func downloadImage(named name: String) async throws -> Data {
        guard let bytes = images[name] else { throw URLError(.fileDoesNotExist) }
        return bytes
    }

    func uploadImage(named name: String, data: Data) async throws {
        let callback = onUpload
        onUpload = nil
        await Task.yield()
        callback?()
        images[name] = data
        events.append("image")
    }
}
