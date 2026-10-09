import SwiftUI
import Combine

enum PlanCategory: String, Codable, CaseIterable, Identifiable {
    case explore = "逛什么", food = "吃什么", stay = "住哪里", transport = "怎么去", expense = "多少钱", notes = "备忘"
    var id: String { rawValue }
    var localizedTitle: String { AppLocalization.text(rawValue) }
    var symbol: String {
        switch self {
        case .explore: "map"
        case .food: "fork.knife"
        case .stay: "bed.double"
        case .transport: "tram"
        case .expense: "creditcard"
        case .notes: "note.text"
        }
    }
    var color: Color {
        switch self {
        case .explore: .blue
        case .food: .orange
        case .stay: .purple
        case .transport: .teal
        case .expense: .green
        case .notes: .secondary
        }
    }
}

enum TransportMode: String, Codable, CaseIterable, Identifiable {
    case taxi = "打车", subway = "地铁", highSpeedRail = "高铁", flight = "飞机"
    case jr = "JR", shinkansen = "新干线", train = "普通列车", bus = "巴士"
    case walk = "步行", bicycle = "骑行", ferry = "轮渡", driving = "自驾"

    var id: String { rawValue }
    var localizedTitle: String { AppLocalization.text(rawValue) }
    var numberLabel: String? {
        switch self {
        case .flight: AppLocalization.text("航班号")
        case .highSpeedRail, .jr, .shinkansen, .train: AppLocalization.text("车次")
        case .subway: AppLocalization.text("线路号")
        case .bus: AppLocalization.text("线路 / 班次")
        case .taxi: AppLocalization.text("车牌号 / 订单号")
        case .ferry: AppLocalization.text("航次")
        case .driving: AppLocalization.text("车牌号")
        case .bicycle: AppLocalization.text("租车编号")
        case .walk: nil
        }
    }
    var numberExample: String {
        switch self {
        case .flight: AppLocalization.text("如 CA1234")
        case .highSpeedRail: AppLocalization.text("如 G123")
        case .jr: AppLocalization.text("如 JR 车次")
        case .shinkansen: AppLocalization.text("如 のぞみ 123 号")
        case .train: AppLocalization.text("如 K123")
        case .subway: AppLocalization.text("如 2 号线")
        case .bus: AppLocalization.text("如 101 路")
        case .taxi: AppLocalization.text("车牌或订单号")
        case .ferry: AppLocalization.text("如 123 航次")
        case .driving: AppLocalization.text("车牌号")
        case .bicycle: AppLocalization.text("租车编号")
        case .walk: ""
        }
    }
    var symbol: String {
        switch self {
        case .taxi, .driving: "car.side.fill"
        case .subway: "tram.fill"
        case .highSpeedRail, .shinkansen: "train.side.front.car"
        case .flight: "airplane"
        case .jr, .train: "train.side.middle.car"
        case .bus: "bus.fill"
        case .walk: "figure.walk"
        case .bicycle: "bicycle"
        case .ferry: "ferry.fill"
        }
    }
}

struct PlanPlace: Codable, Equatable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var source: String? = nil
}

struct PlanWaypoint: Identifiable, Codable, Equatable {
    var id = UUID()
    var place: PlanPlace
}

/// A bundled destination photo with its original attribution retained when a trip is copied or shared.
struct PlacePhoto: Codable, Equatable, Identifiable {
    let asset: String
    let thumbnail: String
    let title: String
    let author: String
    let license: String
    let licenseURL: URL
    let sourceURL: URL
    var note: String? = nil
    var id: String { asset }
}

struct PlanItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var detail = ""
    var time = ""
    var category: PlanCategory
    var amount: Decimal? = nil
    var currency: String? = nil
    var displayTitle: String {
        guard category == .expense, let amount else { return title }
        return title + " · " + ExpenseMoney.format(amount, currency: currency ?? "CNY")
    }
    var transportMode: TransportMode? = nil
    var transportNumber: String? = nil
    var linkPreview: LinkPreview? = nil
    var photos: [Data]? = nil
    var photo: PlacePhoto? = nil
    var place: PlanPlace? = nil
    var places: [PlanWaypoint]? = nil

    var mapPlaces: [PlanWaypoint] {
        if let places { return places }
        return place.map { [PlanWaypoint(id: id, place: $0)] } ?? []
    }
}

struct TravelDay: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = AppLocalization.text("自由安排")
    var items: [PlanItem] = []
    var routeOrder: [UUID]? = nil
    var excludedRouteIDs: [UUID]? = nil

    var expenseTotals: [String: Decimal] {
        items.filter { $0.category == .expense }.reduce(into: [:]) { totals, item in
            if let amount = item.amount { totals[item.currency ?? "CNY", default: 0] += amount }
        }
    }
    var expenseSummary: String {
        let totals = expenseTotals
        return totals.isEmpty ? AppLocalization.text("未记账") : totals.keys.sorted().map { ExpenseMoney.format(totals[$0]!, currency: $0) }.joined(separator: " · ")
    }

    var routeItems: [PlanItem] {
        let located = items.flatMap { item in
            item.mapPlaces.map { waypoint in
                PlanItem(id: waypoint.id, title: item.title, detail: item.detail, time: item.time, category: item.category, place: waypoint.place)
            }
        }
        var remaining = located
        var ordered: [PlanItem] = []
        for id in routeOrder ?? [] {
            if let index = remaining.firstIndex(where: { $0.id == id }) {
                ordered.append(remaining.remove(at: index))
            }
        }
        return ordered + remaining
    }
}

enum TripStatus: String, CaseIterable, Codable {
    case planning = "计划中", wish = "想去", completed = "已结束"
    var localizedTitle: String { AppLocalization.text(rawValue) }
}

struct Trip: Identifiable, Codable, Equatable {
    var id = UUID()
    var destination: String
    var country: String
    var startDate: Date
    var cover: String
    var coverPhoto: Data? = nil
    var status: TripStatus = .planning
    var days: [TravelDay]

    func date(for index: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: index, to: startDate) ?? startDate
    }
    func dayIndex(on date: Date, calendar: Calendar = .current) -> Int? {
        guard status == .planning,
              let index = calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: calendar.startOfDay(for: date)).day,
              days.indices.contains(index) else { return nil }
        return index
    }
    var dateRange: String {
        let format = DateFormatter()
        format.locale = AppLocalization.locale
        format.dateFormat = AppLocalization.isEnglish ? "MMM d" : "M.dd"
        return "\(format.string(from: startDate)) – \(format.string(from: date(for: max(0, days.count - 1))))"
    }
    var itemCount: Int { days.reduce(0) { $0 + $1.items.count } }
    static func date(_ string: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: string) ?? Date()
    }
}

struct DeletedTrip: Identifiable, Codable, Equatable {
    var trip: Trip
    var deletedAt: Date
    var id: UUID { trip.id }
    var expiresAt: Date { deletedAt.addingTimeInterval(30 * 24 * 60 * 60) }
    var remainingDays: Int { max(0, Int(ceil(expiresAt.timeIntervalSinceNow / 86400))) }
}

@MainActor
final class TravelStore: ObservableObject {
    @Published var trips: [Trip] { didSet { save(); if !applyingCloud { cloud?.localChanged(trips, trash: deletedTrips) } } }
    @Published private(set) var deletedTrips: [DeletedTrip] = []
    private var trashFile: URL { file.deletingLastPathComponent().appendingPathComponent(file.deletingPathExtension().lastPathComponent + "-trash.json") }
    @Published private var cloudStatusKey = "仅本机保存"
    @Published private var cloudConflictCount = 0
    var cloudStatus: String {
        get {
            cloudConflictCount > 0
                ? AppLocalization.format("已同步，保留了 %lld 份冲突副本", Int64(cloudConflictCount))
                : AppLocalization.text(cloudStatusKey)
        }
        set { cloudConflictCount = 0; cloudStatusKey = newValue }
    }
    func setCloudSyncResult(conflictCount: Int) {
        cloudStatusKey = "iCloud 已同步"
        cloudConflictCount = conflictCount
    }
    @Published var cloudLastSync: Date?
    var cloud: RoamCloudSync?
    private var applyingCloud = false
    @Published var saveError: String?
    private let file: URL
    var readingLinkIDs = Set<UUID>()
    var readingSharedLinks = false
    let shareEnabled: Bool

    init(file: URL? = nil, reset: Bool = false) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.shareEnabled = file == nil && !reset
        self.file = file ?? base.appendingPathComponent("Roam/trips.json")
        if !reset, let data = try? Data(contentsOf: self.file), let loaded = try? JSONDecoder().decode([Trip].self, from: data) {
            trips = loaded
        } else {
            trips = file == nil ? [] : Self.samples
        }
        if !reset, let data = try? Data(contentsOf: trashFile), let saved = try? JSONDecoder().decode([DeletedTrip].self, from: data) {
            deletedTrips = saved.filter { $0.expiresAt > Date() }
        }
        if reset { save(); saveTrash() }
        collectPendingShares()
        if file == nil && !reset {
            cloud = RoamCloudSync(store: self, file: self.file, hasExistingData: FileManager.default.fileExists(atPath: self.file.path))
            cloud?.start()
        }
    }

    @discardableResult
    func importCollectedNote(_ note: CollectedNote, tripID: UUID, dayID: UUID) -> Bool {
        guard let t = trips.firstIndex(where: { $0.id == tripID }),
              let d = trips[t].days.firstIndex(where: { $0.id == dayID }) else { return false }
        var updated = trips
        if !updated.contains(where: { $0.days.contains(where: { $0.items.contains(where: { $0.id == note.id }) }) }) {
            var item = PlanItem(id: note.id, title: note.preview?.title ?? note.title, detail: note.text, category: .notes)
            item.linkPreview = note.preview ?? LinkReader.firstURL(in: note.text).map { LinkPreview(originalURL: $0, title: note.title) }
            updated[t].days[d].items.append(item)
        }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: file, options: .atomic)
            trips = updated
            if shareEnabled { try? ShareBridge.remove(note.id) }
            return true
        } catch { saveError = AppLocalization.text("分享内容未能保存，仍保留在收集箱，请稍后重试。"); return false }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(trips).write(to: file, options: .atomic)
            publishShareDestinations()
        } catch { saveError = AppLocalization.text("暂时无法保存，请检查设备剩余空间。") }
    }

    func applyCloudTrips(_ incoming: [Trip], trash: [DeletedTrip] = []) {
        applyingCloud = true
        deletedTrips = trash.filter { $0.expiresAt > Date() }
        saveTrash()
        trips = incoming
        applyingCloud = false
    }

    @discardableResult private func saveTrash() -> Bool {
        do {
            try FileManager.default.createDirectory(at: trashFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(deletedTrips).write(to: trashFile, options: .atomic)
            return true
        } catch { saveError = AppLocalization.text("暂时无法保存垃圾桶，请检查设备剩余空间。"); return false }
    }

    func deleteTrip(_ id: UUID, now: Date = Date()) {
        guard let trip = trips.first(where: { $0.id == id }) else { return }
        deletedTrips.removeAll { $0.id == id }
        deletedTrips.insert(DeletedTrip(trip: trip, deletedAt: now), at: 0)
        guard saveTrash() else { deletedTrips.removeAll { $0.id == id }; return }
        trips.removeAll { $0.id == id }
    }

    func restoreTrip(_ id: UUID, now: Date = Date()) {
        guard let entry = deletedTrips.first(where: { $0.id == id }), entry.expiresAt > now else { purgeExpiredTrash(now: now); return }
        applyingCloud = true
        if !trips.contains(where: { $0.id == id }) { trips.insert(entry.trip, at: 0) }
        deletedTrips.removeAll { $0.id == id }
        saveTrash()
        applyingCloud = false
        cloud?.localChanged(trips, trash: deletedTrips)
    }

    func permanentlyDeleteTrip(_ id: UUID) {
        deletedTrips.removeAll { $0.id == id }
        saveTrash()
        cloud?.localChanged(trips, trash: deletedTrips)
    }

    func purgeExpiredTrash(now: Date = Date()) {
        guard deletedTrips.contains(where: { $0.expiresAt <= now }) else { return }
        deletedTrips.removeAll { $0.expiresAt <= now }
        saveTrash()
        cloud?.localChanged(trips, trash: deletedTrips)
    }

    func update(_ trip: Trip) {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[index] = trip
    }

    @discardableResult
    func reorderTrip(_ sourceID: UUID, onto targetID: UUID) -> Bool {
        guard sourceID != targetID,
              let source = trips.firstIndex(where: { $0.id == sourceID }),
              let target = trips.firstIndex(where: { $0.id == targetID }) else { return false }
        var ordered = trips
        let moved = ordered.remove(at: source)
        ordered.insert(moved, at: target)
        trips = ordered
        return true
    }

    @discardableResult
    func reorderDay(_ sourceID: UUID, onto targetID: UUID, tripID: UUID) -> Bool {
        guard sourceID != targetID,
              let t = trips.firstIndex(where: { $0.id == tripID }),
              let source = trips[t].days.firstIndex(where: { $0.id == sourceID }),
              let target = trips[t].days.firstIndex(where: { $0.id == targetID }) else { return false }
        var trip = trips[t]
        let moved = trip.days.remove(at: source)
        trip.days.insert(moved, at: target)
        trips[t] = trip
        return true
    }

    func upsert(_ item: PlanItem, tripID: UUID, from originalDay: UUID?, to destinationDay: UUID, through endDay: UUID? = nil) {
        guard let t = trips.firstIndex(where: { $0.id == tripID }), let target = trips[t].days.firstIndex(where: { $0.id == destinationDay }) else { return }
        var trip = trips[t]
        var insertion: Int?
        if let old = originalDay, let d = trip.days.firstIndex(where: { $0.id == old }) {
            if d == target, let oldIndex = trip.days[d].items.firstIndex(where: { $0.id == item.id }), trip.days[d].items[oldIndex].category == item.category {
                insertion = oldIndex
            }
            trip.days[d].items.removeAll { $0.id == item.id }
        }
        if let insertion { trip.days[target].items.insert(item, at: min(insertion, trip.days[target].items.count)) }
        else { trip.days[target].items.append(item) }
        if item.category == .stay, let endDay, let last = trip.days.firstIndex(where: { $0.id == endDay }), last > target {
            for day in (target + 1)...last {
                var copy = item; copy.id = UUID()
                if let places = copy.places { copy.places = places.map { PlanWaypoint(place: $0.place) } }
                trip.days[day].items.append(copy)
            }
        }
        trips[t] = trip
    }

    func removeItem(_ itemID: UUID, tripID: UUID, dayID: UUID) {
        guard let t = trips.firstIndex(where: { $0.id == tripID }), let d = trips[t].days.firstIndex(where: { $0.id == dayID }) else { return }
        trips[t].days[d].items.removeAll { $0.id == itemID }
    }

    static var samples: [Trip] {
        let titles = ["抵达东京", "山中湖 · 富士山", "富士山骑行", "银座 · 东京站", "中目黑 · 代官山", "镰仓 · 江之岛", "新宿慢逛", "六本木", "回广州"]
        var days = titles.map { TravelDay(title: $0) }
        func item(_ day: Int, _ category: PlanCategory, _ title: String, _ detail: String = "", _ time: String = "") {
            days[day].items.append(PlanItem(title: title, detail: detail, time: time, category: category))
        }
        item(0, .transport, "广州 → 东京", "航班和接驳信息待补充")
        item(0, .explore, "池袋随意走走", "抵达后轻松安排，熟悉住处周边")
        item(0, .food, "找一家日式食堂", "先收藏几家备选，不急着决定")
        item(1, .explore, "山中湖看富士山", "天气好就沿湖散步。多留一些看风景的时间。")
        item(1, .transport, "新宿出发乘巴士", "出发前确认车站、车次及是否需要预约。")
        item(1, .food, "湖边午餐", "餐厅待选；留一个下雨天的室内备选")
        item(1, .notes, "看天气再决定路线", "带防风外套、充电宝；门票和交通费用以实际查询为准。")
        item(2, .explore, "沿湖骑行", "租车前检查电量和刹车，途中随时停下来拍照。")
        item(3, .explore, "东京站 · 日本桥 · 银座", "同一区域慢慢逛，商店和咖啡馆随心挑。")
        item(4, .explore, "中目黑 → 代官山", "沿目黑川散步，再找一家咖啡馆休息。")
        item(5, .explore, "镰仓 · 江之岛", "把海边的时间留足。路线和车票出发前再确认。")
        item(6, .explore, "新宿 · 歌舞伎町", "逛店、找抹茶店，预留自由活动时间。")
        item(7, .explore, "六本木看展", "21_21 DESIGN SIGHT、东京城市观景台，开放时间待确认。")
        item(8, .transport, "东京 → 广州", "提前确认航站楼和出发时间。")
        for d in 0...6 { item(d, .stay, "池袋 Resol", "示例住宿，预订信息待填写") }
        item(7, .stay, "机场酒店", "最后一晚住得离机场近一点")
        var kyoto = (0..<5).map { _ in TravelDay() }
        kyoto[0] = TravelDay(title: "东山散步", items: [.init(title: "清水寺 · 二年坂", detail: "慢慢逛，沿途找喜欢的小店", category: .explore)])
        kyoto[1] = TravelDay(title: "岚山的一天", items: [.init(title: "岚山竹林", category: .explore)])
        return [
            Trip(destination: "东京", country: "日本", startDate: Trip.date("2026-10-24"), cover: "tokyo", days: days),
            Trip(destination: "京都", country: "日本", startDate: Trip.date("2026-11-18"), cover: "kyoto", days: kyoto),
            Trip(destination: "富士山", country: "日本", startDate: Trip.date("2027-01-01"), cover: "fuji", days: [TravelDay(), TravelDay(), TravelDay()]),
            Trip(destination: "大理", country: "中国 · 云南", startDate: Trip.date("2027-02-01"), cover: "", status: .wish, days: [TravelDay(), TravelDay(), TravelDay(), TravelDay()])
        ]
    }
}
