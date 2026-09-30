import SwiftUI
import Combine

enum PlanCategory: String, Codable, CaseIterable, Identifiable {
    case explore = "逛什么", food = "吃什么", stay = "住哪里", transport = "怎么去", notes = "备忘"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .explore: "map"
        case .food: "fork.knife"
        case .stay: "bed.double"
        case .transport: "tram"
        case .notes: "note.text"
        }
    }
    var color: Color {
        switch self {
        case .explore: .blue
        case .food: .orange
        case .stay: .purple
        case .transport: .teal
        case .notes: .secondary
        }
    }
}

enum TransportMode: String, Codable, CaseIterable, Identifiable {
    case taxi = "打车", subway = "地铁", highSpeedRail = "高铁", flight = "飞机"
    case jr = "JR", shinkansen = "新干线", train = "普通列车", bus = "巴士"
    case walk = "步行", bicycle = "骑行", ferry = "轮渡", driving = "自驾"

    var id: String { rawValue }
    var numberLabel: String? {
        switch self {
        case .flight: "航班号"
        case .highSpeedRail, .jr, .shinkansen, .train: "车次"
        case .subway: "线路号"
        case .bus: "线路 / 班次"
        case .taxi: "车牌号 / 订单号"
        case .ferry: "航次"
        case .driving: "车牌号"
        case .bicycle: "租车编号"
        case .walk: nil
        }
    }
    var numberExample: String {
        switch self {
        case .flight: "如 CA1234"
        case .highSpeedRail: "如 G123"
        case .jr: "如 JR 车次"
        case .shinkansen: "如 のぞみ 123 号"
        case .train: "如 K123"
        case .subway: "如 2 号线"
        case .bus: "如 101 路"
        case .taxi: "车牌或订单号"
        case .ferry: "如 123 航次"
        case .driving: "车牌号"
        case .bicycle: "租车编号"
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

struct PlanItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var detail = ""
    var time = ""
    var category: PlanCategory
    var transportMode: TransportMode? = nil
    var transportNumber: String? = nil
    var place: PlanPlace? = nil
    var places: [PlanWaypoint]? = nil

    var mapPlaces: [PlanWaypoint] {
        if let places { return places }
        return place.map { [PlanWaypoint(id: id, place: $0)] } ?? []
    }
}

struct TravelDay: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = "自由安排"
    var items: [PlanItem] = []
    var routeOrder: [UUID]? = nil
    var excludedRouteIDs: [UUID]? = nil

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
    var dateRange: String {
        let format = DateFormatter()
        format.dateFormat = "M.dd"
        return "\(format.string(from: startDate)) – \(format.string(from: date(for: max(0, days.count - 1))))"
    }
    var itemCount: Int { days.reduce(0) { $0 + $1.items.count } }
    static func date(_ string: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: string) ?? Date()
    }
}

@MainActor
final class TravelStore: ObservableObject {
    @Published var trips: [Trip] { didSet { save(); if !applyingCloud { cloud?.localChanged(trips) } } }
    @Published var cloudStatus = "仅本机保存"
    @Published var cloudLastSync: Date?
    var cloud: RoamCloudSync?
    private var applyingCloud = false
    @Published var saveError: String?
    private let file: URL

    init(file: URL? = nil, reset: Bool = false) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.file = file ?? base.appendingPathComponent("Roam/trips.json")
        if !reset, let data = try? Data(contentsOf: self.file), let loaded = try? JSONDecoder().decode([Trip].self, from: data) {
            trips = loaded
        } else {
            trips = Self.samples
        }
        if reset { save() }
        if file == nil && !reset {
            cloud = RoamCloudSync(store: self, file: self.file, hasExistingData: FileManager.default.fileExists(atPath: self.file.path))
            cloud?.start()
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(trips).write(to: file, options: .atomic)
        } catch { saveError = "暂时无法保存，请检查设备剩余空间。" }
    }

    func applyCloudTrips(_ incoming: [Trip]) {
        applyingCloud = true
        trips = incoming
        applyingCloud = false
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
