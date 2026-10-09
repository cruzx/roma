import SwiftUI

extension TravelStore {
    func publishShareDestinations() {
        guard shareEnabled else { return }
        let destinations = trips.map { trip in
            ShareDestination(id: trip.id, title: trip.destination + " · " + trip.dateRange, days: trip.days.enumerated().map { index, day in
                ShareDestination.Day(id: day.id, title: AppLocalization.format("第 %lld 天 · %@", index + 1, day.title))
            })
        }
        try? ShareBridge.publish(destinations)
    }
    func collectPendingShares() {
        guard shareEnabled else { return }
        for note in ShareBridge.pending() {
            if trips.contains(where: { $0.days.contains(where: { $0.items.contains(where: { $0.id == note.id }) }) }) {
                try? ShareBridge.remove(note.id)
                continue
            }
            guard let tripID = note.tripID, let dayID = note.dayID else { continue }
            _ = importCollectedNote(note, tripID: tripID, dayID: dayID)
        }
        publishShareDestinations()
        Task { await refreshSharedLinks() }
    }
}

struct ShareInboxView: View {
    @EnvironmentObject private var store: TravelStore
    @Environment(\.dismiss) private var dismiss
    @State private var notes = ShareBridge.pending()
    @State private var pasted = ""
    @State private var selected: CollectedNote?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("粘贴分享文字或链接", text: $pasted, axis: .vertical)
                    Button("收集到备忘") {
                        let text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        let note = CollectedNote(title: String(text.prefix(60)), text: text)
                        do { try ShareBridge.save(note); pasted = ""; reload(); selected = note }
                        catch { store.saveError = AppLocalization.text("分享内容未能保存，请稍后重试。") }
                    }.disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pasted.count > 100_000)
                } header: { Text("从其他 App 收集") } footer: {
                    Text("在其他 App 的系统分享面板中选择「漫游」。如果没有系统分享入口，可复制链接或分享文字后粘贴到这里。")
                }
                Section("待归档 · \(notes.count)") {
                    if notes.isEmpty { Text("暂时没有待归档内容").foregroundStyle(.secondary) }
                    ForEach(notes) { note in
                        if let preview = note.preview { LinkPreviewCard(preview: preview) }
                        Button { selected = note } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(note.preview == nil ? note.title : "放入备忘").foregroundStyle(.primary).lineLimit(2)
                                Text(note.text).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                    }
                }
            }
            .navigationTitle("分享收集箱").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $selected, onDismiss: reload) { note in ShareArchiveView(note: note).environmentObject(store) }
            .onAppear(perform: reload)
        }
    }
    private func reload() { notes = ShareBridge.pending() }
}

private struct ShareArchiveView: View {
    @EnvironmentObject private var store: TravelStore
    @Environment(\.dismiss) private var dismiss
    @State var note: CollectedNote
    @State private var reading = false
    @State private var tripID: UUID?
    @State private var dayID: UUID?
    var body: some View {
        NavigationStack {
            Form {
                Section("链接内容") {
                    if let preview = note.preview { LinkPreviewCard(preview: preview, expanded: true) }
                    else { Text(note.title).font(.headline) }
                    if reading { ProgressView("正在读取标题和内容…") }
                    if !reading, LinkReader.firstURL(in: note.text) != nil {
                        Button(note.preview == nil ? "读取链接" : "重新读取") { Task { await readLink() } }
                    }
                }
                Section("原始分享") { Text(note.text).textSelection(.enabled) }
                Section("放入哪一天的备忘") {
                    if store.trips.isEmpty { Text("先创建一次旅行，再回来归档。内容已保存在收集箱。") }
                    Picker("旅行", selection: $tripID) {
                        Text("请选择旅行").tag(nil as UUID?)
                        ForEach(store.trips) { Text($0.destination + " · " + $0.dateRange).tag(Optional($0.id)) }
                    }.onChange(of: tripID) { _, id in dayID = store.trips.first { $0.id == id }?.days.first?.id }
                    if let trip = store.trips.first(where: { $0.id == tripID }) {
                        Picker("日期", selection: $dayID) {
                            ForEach(Array(trip.days.enumerated()), id: \.element.id) { index, day in Text("第 \(index + 1) 天 · \(day.title)").tag(Optional(day.id)) }
                        }
                    }
                    Button("保存到备忘") {
                        if let tripID, let dayID, store.importCollectedNote(note, tripID: tripID, dayID: dayID) { dismiss() }
                    }.disabled(tripID == nil || dayID == nil || reading)
                }
            }.navigationTitle("归档分享")
                .task { if note.preview?.fetchedAt == nil { await readLink() } }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
    private func readLink() async {
        guard !reading, let url = LinkReader.firstURL(in: note.text) else { return }
        reading = true
        defer { reading = false }
        note.preview = await LinkReader.read(url, fallback: note.title)
        if ShareBridge.pending().contains(where: { $0.id == note.id }) {
            do { try ShareBridge.save(note) }
            catch { store.saveError = AppLocalization.text("链接内容暂时未能保存，请重试。") }
        }
    }

}

extension TravelStore {
    func refreshSharedLinks() async {
        guard shareEnabled, !readingSharedLinks else { return }
        readingSharedLinks = true
        defer { readingSharedLinks = false }
        let days: [TravelDay] = trips.flatMap { $0.days }
        let items: [PlanItem] = days.flatMap { $0.items }
        let pendingIDs: [UUID] = items.filter { item in
            item.category == .notes && item.linkPreview != nil && item.linkPreview?.fetchedAt == nil
        }.map { $0.id }
        for id in pendingIDs {
            if Task.isCancelled { break }
            await refreshLink(id)
        }
    }

    func refreshLink(_ id: UUID) async {
        guard readingLinkIDs.insert(id).inserted else { return }
        defer { readingLinkIDs.remove(id) }
        guard let original = trips.flatMap({ $0.days }).flatMap({ $0.items }).first(where: { $0.id == id }),
              let preview = original.linkPreview else { return }
        let result = await LinkReader.read(preview.originalURL, fallback: original.title)
        for trip in trips {
            guard let d = trip.days.firstIndex(where: { $0.items.contains(where: { $0.id == id }) }),
                  let i = trip.days[d].items.firstIndex(where: { $0.id == id }) else { continue }
            var changed = trip
            // Re-read the latest item after the network request so edits are preserved.
            guard changed.days[d].items[i].linkPreview?.originalURL == preview.originalURL else { return }
            changed.days[d].items[i].linkPreview = result
            if changed.days[d].items[i].title == original.title { changed.days[d].items[i].title = result.title }
            update(changed)
            return
        }
    }
}

struct LinkPreviewCard: View {
    let preview: LinkPreview
    var expanded = false
    var body: some View {
        Link(destination: preview.originalURL) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(preview.title).font(.headline).foregroundStyle(.primary).lineLimit(expanded ? nil : 3)
                        if !preview.author.isEmpty { Text(preview.author).font(.caption).foregroundStyle(.secondary) }
                        if !preview.summary.isEmpty {
                            Text(preview.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(expanded ? nil : 5)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if let data = preview.imageData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }.padding(14).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityHint("打开分享来源的原文")
    }
}

struct SavedLinkCard: View {
    @EnvironmentObject private var store: TravelStore
    let item: PlanItem
    let edit: () -> Void
    @State private var reading = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let preview = item.linkPreview { LinkPreviewCard(preview: preview) }
            HStack {
                Button("编辑备忘", action: edit)
                Spacer()
                if reading { ProgressView() }
                else { Button("重新读取") { Task { await refresh() } } }
            }.font(.caption).buttonStyle(.borderless)
        }.task { if item.linkPreview?.fetchedAt == nil { await refresh() } }
    }
    private func refresh() async {
        guard !reading else { return }
        reading = true
        await store.refreshLink(item.id)
        reading = false
    }
}

/// An entry point bound to a specific day, so collecting never requires reselecting a trip.
struct DayLinkCollector: View {
    let tripID: UUID
    let dayID: UUID
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            Label("添加攻略", doodleSystemImage: "plus")
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("collect-day-link")
        .sheet(isPresented: $showing) {
            DayLinkCaptureView(tripID: tripID, dayID: dayID)
        }
    }
}

private struct DayLinkCaptureView: View {
    @EnvironmentObject private var store: TravelStore
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    let dayID: UUID
    @State private var text = ""
    @State private var preview: LinkPreview?
    @State private var reading = false
    @State private var error: String?
    private var url: URL? { LinkReader.firstURL(in: text) }
    private var day: TravelDay? { store.trips.first { $0.id == tripID }?.days.first { $0.id == dayID } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("粘贴攻略链接或分享文字", text: $text, axis: .vertical)
                        .lineLimit(3...8).disabled(reading)
                        .accessibilityIdentifier("day-link-input")
                        .onChange(of: text) { _, _ in preview = nil; error = nil }
                    Button("读取标题和内容") {
                        Task {
                            guard let url, !reading else { return }
                            reading = true
                            preview = await LinkReader.read(url, fallback: String(text.prefix(100)))
                            reading = false
                        }
                    }.disabled(url == nil || reading || text.count > 100_000)
                    if reading { ProgressView("正在读取攻略…") }
                } header: { Text("添加当天攻略") } footer: {
                    Text("支持粘贴小红书等 App 的整段分享文字。保存后，攻略会显示在当天备忘下方的攻略区。")
                }
                if let preview { Section("攻略预览") { LinkPreviewCard(preview: preview, expanded: true) } }
                if let day { Section("保存位置") { Text(day.title) } }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("添加攻略").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(reading) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let url else { return }
                        var note = CollectedNote(title: preview?.title ?? String(text.prefix(100)), text: text)
                        note.preview = preview ?? LinkPreview(originalURL: url, title: note.title)
                        if store.importCollectedNote(note, tripID: tripID, dayID: dayID) {
                            Task { await store.refreshSharedLinks() }
                            dismiss()
                        } else { error = AppLocalization.text("未能保存，请检查当天安排是否仍然存在后重试。") }
                    }.disabled(url == nil || reading || day == nil || text.count > 100_000)
                        .accessibilityIdentifier("save-day-link")
                }
            }
            .interactiveDismissDisabled(reading)
        }
    }
}
