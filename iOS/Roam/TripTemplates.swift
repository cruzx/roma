import SwiftUI

struct TravelTemplate: Codable, Identifiable {
    struct Source: Codable, Identifiable {
        let title: String
        let url: URL
        var id: URL { url }
    }
    struct Item: Codable {
        let category: PlanCategory
        let title: String
        let detail: String
        let time: String
        var photo: PlacePhoto? = nil
    }
    struct Day: Codable {
        let title: String
        let items: [Item]
    }
    let id: String
    let destination: String
    let country: String
    let theme: String
    let summary: String
    let cover: String
    struct CoverCredit: Codable {
        let title: String
        let author: String
        let license: String
        let licenseURL: URL
        let url: URL
        let note: String
    }
    let coverCredit: CoverCredit?
    let reviewedOn: String
    let sources: [Source]
    let days: [Day]

    func makeTrip(startDate: Date) -> Trip {
        var plans = days.map { day in
            TravelDay(title: day.title, items: day.items.map { item in
                PlanItem(title: item.title, detail: item.detail, time: item.time, category: item.category, photo: item.photo)
            })
        }
        if !plans.isEmpty {
            if let credit = coverCredit {
                plans[0].items.append(PlanItem(title: AppLocalization.text("封面图片来源"), detail: "\(credit.title)\n\(credit.author) · \(credit.license)\n\(credit.url.absoluteString)\n\(credit.licenseURL.absoluteString)\n\(credit.note)", category: .notes))
            }
            let references = sources.map { "\($0.title)\n\($0.url.absoluteString)" }.joined(separator: "\n\n")
            let explanation = AppLocalization.format("漫游整理的示例行程，可按喜好编辑。时间为建议，费用、开放日、预约和交通请在出发前核对。住宿为区域建议，不代表预订。资料整理：%@。", reviewedOn)
            plans[0].items.append(PlanItem(title: AppLocalization.text("模板说明与参考资料"),
                                         detail: "\(explanation)\n\n\(references)", category: .notes))
        }
        return Trip(destination: destination, country: country,
                    startDate: Calendar.current.startOfDay(for: startDate), cover: cover, days: plans)
    }
}

enum TravelTemplateCatalog {
    // Keep each decoded catalog separate; changing the app language never rewrites saved trips.
    private static let chineseResult = load(resource: "TripTemplates")
    private static let englishResult = load(resource: "TripTemplates.en")

    static var result: Result<[TravelTemplate], Error> {
        AppLocalization.isEnglish ? englishResult : chineseResult
    }

    private static func load(resource: String) -> Result<[TravelTemplate], Error> {
        Result {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try JSONDecoder().decode([TravelTemplate].self, from: Data(contentsOf: url))
        }
    }
}

struct TravelTemplatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TravelStore
    @State private var search = ""

    var body: some View {
        NavigationStack {
            Group {
                switch TravelTemplateCatalog.result {
                case .success(let templates):
                    let visible = templates.filter {
                        search.isEmpty || ($0.destination + $0.country + $0.theme).localizedStandardContains(search)
                    }
                    List {
                        Section {
                            Text("选一座城市，先预览路线，再设定出发日期。创建后，每条安排都可以编辑。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Section("目的地") {
                            ForEach(visible) { template in
                                NavigationLink {
                                    TravelTemplateDetail(template: template) { trip in
                                        store.trips.insert(trip, at: 0)
                                        dismiss()
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(template.destination).font(.headline)
                                            Spacer()
                                            Text("\(template.days.count) 天").font(.subheadline).foregroundStyle(.blue)
                                        }
                                        Text(template.country + " · " + template.theme)
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text(template.summary).font(.subheadline).foregroundStyle(.secondary)
                                    }.padding(.vertical, 6)
                                }
                                .simultaneousGesture(TapGesture().onEnded { AppHaptics.tap() })
                                .accessibilityIdentifier("template-\(template.id)")
                            }
                        }
                    }
                    .overlay {
                        if visible.isEmpty {
                            ContentUnavailableView {
                                Label("未找到目的地", doodleSystemImage: "magnifyingglass", size: 48)
                            } description: {
                                Text("试试搜索其他目的地")
                            }
                        }
                    }
                    .searchable(text: $search, prompt: "搜索城市或主题")
                case .failure:
                    ContentUnavailableView {
                        Label("暂时无法读取模板", doodleSystemImage: "exclamationmark.triangle", size: 48)
                    } description: {
                        Text("请重新打开应用后再试。")
                    }
                }
            }
            .navigationTitle("旅行模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { AppHaptics.tap(); dismiss() } }
            }
        }
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 560, minHeight: 600)
        #endif
    }
}

struct TravelTemplateDetail: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TravelStore
    let template: TravelTemplate
    var closesAfterCreation = false
    let onCreate: (Trip) -> Void
    @State private var departure = Date()

    var body: some View {
        List {
            Section {
                GeometryReader { geometry in
                    Image(template.cover).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: 200).clipped()
                }.frame(height: 200)
                    .listRowInsets(EdgeInsets())
                    .accessibilityLabel(AppLocalization.format("%@封面", template.destination))
            }
            Section {
                Text(template.theme).font(.title2.bold())
                Text(template.summary).foregroundStyle(.secondary)
                Label("\(template.days.count) 天 · \(template.country)", doodleSystemImage: "calendar")
                DatePicker("出发日期", selection: $departure, displayedComponents: .date)
                    .accessibilityIdentifier("template-departure")
            }
            ForEach(Array(template.days.enumerated()), id: \.offset) { index, day in
                Section("第 \(index + 1) 天 · \(day.title)") {
                    ForEach(Array(day.items.enumerated()), id: \.offset) { itemIndex, item in
                        HStack(alignment: .top, spacing: 12) {
                            DoodleIcon(systemName: item.category.symbol).foregroundStyle(item.category.color)
                                .frame(width: 24).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.title).font(.subheadline.weight(.semibold))
                                Text(item.detail).font(.subheadline).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if item.photo != nil || !item.time.isEmpty {
                                VStack(alignment: .trailing, spacing: 6) {
                                    if let photo = item.photo {
                                        PlacePhotoThumbnail(photo: photo,
                                            identifier: "template-photo-\(template.id)-\(index)-\(itemIndex)")
                                    }
                                    if !item.time.isEmpty {
                                        Text(item.time).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
            if let credit = template.coverCredit {
                Section("封面图片") {
                    Text(credit.author).font(.caption).foregroundStyle(.secondary)
                    Link(credit.title, destination: credit.url)
                    Link(credit.license, destination: credit.licenseURL)
                    Text(credit.note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(template.sources) { source in
                    Link(destination: source.url) {
                        Label(source.title, doodleSystemImage: "arrow.up.right.square")
                    }
                }
            } header: {
                Text("参考资料")
            } footer: {
                Text("漫游整理的示例路线，资料整理于 \(template.reviewedOn)。时间仅供规划；开放日、门票、预约和交通以出发时官方信息为准。住宿为区域建议。")
            }
        }
        .navigationTitle(template.destination)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            Button {
                onCreate(template.makeTrip(startDate: departure))
                if store.saveError == nil { AppHaptics.success() }
                else { AppHaptics.error() }
                if closesAfterCreation { dismiss() }
            } label: {
                Text("用此模板创建旅行").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("create-template-trip")
            .padding().background(.regularMaterial)
        }
    }
}

struct TravelTemplateHomeSection: View {
    @EnvironmentObject private var store: TravelStore
    let columns: [GridItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Divider().padding(.vertical, 6)
            Text("Recommended Trips").font(.title2.bold()).foregroundStyle(.white).accessibilityAddTraits(.isHeader)
            if case .success(let templates) = TravelTemplateCatalog.result {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(templates) { template in
                        NavigationLink {
                            TravelTemplateDetail(template: template, closesAfterCreation: true) { trip in
                                store.trips.insert(trip, at: 0)
                            }.tint(.blue)
                        } label: {
                            TravelTemplateHomeCard(template: template)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { AppHaptics.tap() })
                        .accessibilityIdentifier("home-template-\(template.id)")
                        .accessibilityLabel(AppLocalization.format("%@，%d 天旅行模板，%@", template.destination, template.days.count, template.theme))
                    }
                }
            } else {
                Text("暂时无法读取模板，请重新打开应用后再试。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct TravelTemplateHomeCard: View {
    let template: TravelTemplate
    private var symbol: String {
        switch template.id {
        case "beijing", "paris": "building.columns"
        case "kyoto": "leaf"
        case "kobe": "ferry"
        case "fuji": "mountain.2"
        case "london": "clock"
        case "dalian": "water.waves"
        default: "building.2"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if !template.cover.isEmpty {
                    GeometryReader { geometry in
                        Image(template.cover).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: 118).clipped()
                    }
                } else {
                    Color.blue.opacity(0.08)
                    DoodleIcon(systemName: symbol, size: 44)
                        .foregroundStyle(.black)
                }
            }.frame(height: 118).clipped()
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(template.destination).font(.headline)
                    Spacer(minLength: 4)
                    Text("\(template.days.count) 天").font(.caption).foregroundStyle(.blue)
                }
                Text(template.theme).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(template.country).font(.caption).foregroundStyle(.secondary)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}
