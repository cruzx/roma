import SwiftUI
import PhotosUI
import CloudKit

struct HomeBackdrop: Codable, Equatable {
    var asset: String? = nil
    var photo: Data? = nil
    var revision = UUID().uuidString
    var modifiedAt = Date()
}

struct BackgroundPreset: Identifiable {
    let id: String
    let title: String
    let source: String
    var localizedTitle: String { AppLocalization.text(title) }
    static let all: [BackgroundPreset] = [
        .init(id: "bg-fuji", title: "日本 · 富士山", source: "https://pixabay.com/photos/mount-fuji-sunrise-morning-haze-2232290/"), 
        .init(id: "bg-norway", title: "挪威 · 山谷", source: "https://pixabay.com/photos/landscape-norway-mountains-rock-3669990/"), 
        .init(id: "bg-santorini", title: "希腊 · 圣托里尼", source: "https://pixabay.com/photos/akrotiri-santorini-blue-white-4385371/"), 
        .init(id: "bg-swiss", title: "瑞士 · 山野", source: "https://pixabay.com/photos/switzerland-swiss-landscape-5414899/"), 
        .init(id: "bg-dolomites", title: "意大利 · 多洛米蒂", source: "https://pixabay.com/photos/mountains-alps-italy-nature-7305769/"), 
        .init(id: "bg-nz", title: "新西兰 · 山间湖泊", source: "https://pixabay.com/photos/new-zealand-lake-mountain-landscape-679068/"), 
        .init(id: "bg-iceland", title: "冰岛 · 瀑布", source: "https://pixabay.com/photos/waterfall-nature-iceland-landscape-7929685/"), 
        .init(id: "bg-canada", title: "加拿大 · 班夫", source: "https://pixabay.com/photos/mountains-lake-canada-banff-nature-9606525/"), 
        .init(id: "bg-bali", title: "印尼 · 巴厘岛梯田", source: "https://pixabay.com/photos/bali-rice-terraces-landscape-rice-1514132/"), 
        .init(id: "bg-namibia", title: "纳米比亚 · 沙丘", source: "https://pixabay.com/photos/namib-desert-namibia-africa-desert-7559993/"), 
    ]
}

@MainActor
final class HomeBackgroundStore: ObservableObject {
    @Published private(set) var selection = HomeBackdrop()
    @Published private var statusKey = "背景保存在本机"
    var status: String { AppLocalization.text(statusKey) }
    @Published var error: String?
    private struct Saved: Codable {
        var selection: HomeBackdrop
        var pending: Bool
        var owner: String?
    }
    private let file: URL
    private let enabled: Bool
    private var pending = false
    private var owner: String?
    private var syncing = false
    private var task: Task<Void, Never>?
    init(testing: Bool = false, reset: Bool = false) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = testing ? FileManager.default.temporaryDirectory.appendingPathComponent("roam-test-background.json") : base.appendingPathComponent("Roam/home-background.json")
        enabled = !testing && RoamCloudSync.isConfigured
        if !reset, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            selection = saved.selection; pending = saved.pending; owner = saved.owner
        }
        if enabled {
            task = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.synchronize()
                    do { try await Task.sleep(for: .seconds(30)) } catch { break }
                }
            }
        }
    }
    func select(asset: String? = nil, photo: Data? = nil) {
        let next = HomeBackdrop(asset: asset, photo: photo)
        guard persist(next, pending: true) else { return }
        selection = next; pending = true
        statusKey = enabled ? "背景已保存，等待 iCloud 同步" : "背景保存在本机"
        Task { await synchronize() }
    }
    @discardableResult private func persist(_ value: HomeBackdrop, pending: Bool) -> Bool {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Saved(selection: value, pending: pending, owner: owner)).write(to: file, options: .atomic)
            return true
        } catch { self.error = AppLocalization.text("背景保存失败，请重试。"); return false }
    }
    func synchronize() async {
        guard enabled, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let container = CKContainer(identifier: RoamCloudSync.containerID)
            guard try await container.accountStatus() == .available else { statusKey = "请登录 iCloud，背景已保存在本机"; return }
            let account = try await container.userRecordID().recordName
            guard owner == nil || owner == account else { statusKey = "iCloud 账户已更换，背景同步已暂停"; return }
            owner = account
            _ = persist(selection, pending: pending)
            let database = container.privateCloudDatabase
            let id = CKRecord.ID(recordName: "home-background-v1")
            for attempt in 0..<3 {
                let record: CKRecord
                do { record = try await database.record(for: id) }
                catch let e as CKError where e.code == .unknownItem { record = CKRecord(recordType: "RoamLibrary", recordID: id) }
                if let asset = record["payload"] as? CKAsset, let url = asset.fileURL {
                    let remote = try JSONDecoder().decode(HomeBackdrop.self, from: Data(contentsOf: url))
                    if remote.revision == selection.revision {
                        pending = false
                    } else if !pending || remote.modifiedAt > selection.modifiedAt || (remote.modifiedAt == selection.modifiedAt && remote.revision > selection.revision) {
                        guard persist(remote, pending: false) else { return }
                        selection = remote; pending = false
                    }
                }
                guard pending else { _ = persist(selection, pending: false); statusKey = "背景已同步到 iCloud"; return }
                let outgoing = selection
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
                try JSONEncoder().encode(outgoing).write(to: url, options: .atomic)
                defer { try? FileManager.default.removeItem(at: url) }
                record["payload"] = CKAsset(fileURL: url)
                do {
                    _ = try await database.save(record)
                    if outgoing.revision == selection.revision { pending = false }
                    _ = persist(selection, pending: pending)
                    statusKey = pending ? "背景已保存，等待 iCloud 同步" : "背景已同步到 iCloud"
                    return
                } catch let e as CKError where e.code == .serverRecordChanged && attempt < 2 { continue }
            }
        } catch { statusKey = "背景已保存在本机，iCloud 将稍后重试" }
    }
}

struct HomeBackdropView: View {
    let selection: HomeBackdrop
    // A light blur keeps the scenery recognizable behind the cards.
    private let blurRadius: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.systemGroupedBackground)
                if let photo = selection.photo.flatMap({ UIImage(data: $0) }) {
                    softened(Image(uiImage: photo), size: geometry.size)
                } else if let asset = selection.asset {
                    softened(Image(asset), size: geometry.size)
                }
            }
        }.ignoresSafeArea().allowsHitTesting(false)
    }

    private func softened(_ image: Image, size: CGSize) -> some View {
        image.resizable().scaledToFill()
            // Extend the image beyond the viewport so blur never reveals a pale border.
            .frame(width: size.width + blurRadius * 4, height: size.height + blurRadius * 4)
            .clipped()
            .blur(radius: blurRadius, opaque: true)
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay(Color.black.opacity(0.10))
    }
}

struct HomeBackgroundPicker: View {
    @EnvironmentObject private var backgrounds: HomeBackgroundStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var processing = false
    @State private var photoTask: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("让每次打开，都像出发").font(.title2.bold())
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(processing ? AppLocalization.text("正在处理照片…") : AppLocalization.text("从手机相册选择"), doodleSystemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity).padding().background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    }.disabled(processing).accessibilityIdentifier("choose-background-photo")
                    if let data = backgrounds.selection.photo, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 160).clipped().clipShape(RoundedRectangle(cornerRadius: 16))
                        Label("正在使用自选照片", doodleSystemImage: "checkmark.circle.fill").foregroundStyle(.blue)
                    }
                    Button("恢复默认背景") { backgrounds.select() }.accessibilityIdentifier("default-background")
                    Text("世界风景").font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                        ForEach(BackgroundPreset.all) { preset in
                            VStack(alignment: .leading, spacing: 7) {
                                Button { photoTask?.cancel(); processing = false; selectedPhoto = nil; backgrounds.select(asset: preset.id) } label: {
                                    Image(preset.id).resizable().scaledToFill().frame(height: 125).clipped()
                                        .overlay(alignment: .topTrailing) {
                                            if backgrounds.selection.asset == preset.id {
                                                DoodleIcon(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.white).background(.blue, in: Circle()).padding(10)
                                            }
                                        }.clipShape(RoundedRectangle(cornerRadius: 16))
                                }.buttonStyle(.plain).accessibilityLabel(preset.localizedTitle).accessibilityIdentifier(preset.id)
                                Text(preset.localizedTitle).font(.subheadline.weight(.medium))
                                Link("照片来源 · Pixabay", destination: URL(string: preset.source)!).font(.caption)
                            }
                        }
                    }
                    Text(backgrounds.status).font(.caption).foregroundStyle(.secondary)
                    Text("自选照片会同步到你的私人 iCloud；离线时先保存在本机，联网后自动重试。").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.navigationTitle("首页背景").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .onChange(of: selectedPhoto) { _, item in
                photoTask?.cancel()
                guard let item else { return }
                processing = true
                photoTask = Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw CoverPhotoError.invalid }
                        let photo = try await Task.detached(priority: .userInitiated) { try CoverPhotoCodec.compress(data) }.value
                        try Task.checkCancellation()
                        backgrounds.select(photo: photo)
                    } catch is CancellationError { return }
                    catch { backgrounds.error = AppLocalization.text("无法读取这张照片，请换一张重试。") }
                    processing = false
                }
            }
            .onDisappear { photoTask?.cancel() }
            .alert("背景设置", isPresented: Binding(get: { backgrounds.error != nil }, set: { if !$0 { backgrounds.error = nil } })) {
                Button("好") { backgrounds.error = nil }
            } message: { Text(backgrounds.error ?? "") }
        }
    }
}
