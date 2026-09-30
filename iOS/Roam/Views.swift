import SwiftUI
import MapKit
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

struct RootView: View {
    var body: some View { LibraryView() }
}

struct LibraryView: View {
    @EnvironmentObject private var backgrounds: HomeBackgroundStore
    @State private var showBackground = false
    @EnvironmentObject private var store: TravelStore
    @State private var search = ""
    @State private var showCreate = false
    @State private var showCloud = false
    @State private var showTrash = false
    private var filtered: [Trip] {
        store.trips.filter {
            (search.isEmpty || ($0.destination + $0.country).localizedStandardContains(search))
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        if let trip = store.trips.first(where: { $0.dayIndex(on: context.date) != nil }),
                           let index = trip.dayIndex(on: context.date) {
                            NavigationLink(value: TodayDayRoute(tripID: trip.id, dayID: trip.days[index].id)) {
                                TodayItineraryCard(trip: trip, index: index)
                            }.buttonStyle(.plain).accessibilityIdentifier("today-itinerary-card")
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                        ForEach(filtered) { trip in
                            sortableTripCard(trip)
                        }
                        Button { showCreate = true } label: {
                            VStack(spacing: 12) {
                                Image(systemName: "plus").font(.title2.weight(.medium))
                                    .frame(width: 48, height: 48).background(.blue.opacity(0.08), in: Circle())
                                Text("新的旅程").font(.headline)
                                Text("下一站，由你决定").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).frame(height: 225)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                        }.buttonStyle(.plain).foregroundStyle(.blue).accessibilityIdentifier("new-trip-card")
                    }
                    if filtered.isEmpty && !search.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                    Label("长按卡片拖动，调整旅行顺序", systemImage: "hand.draw")
                        .font(.caption).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity).padding(.top, 10)
                }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 28)
            }
            .background(HomeBackdropView(selection: backgrounds.selection))
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("我的旅行")
                        .font(.system(size: 32, weight: .bold))
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityAddTraits(.isHeader)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("首页背景", systemImage: "photo") { showBackground = true }
                        Button("iCloud 同步", systemImage: "icloud") { showCloud = true }
                        Button("垃圾桶", systemImage: "trash") { showTrash = true }
                        Button("新建旅行", systemImage: "plus") { showCreate = true }
                        Button("导入旅行文件", systemImage: "square.and.arrow.down") {
                            NotificationCenter.default.post(name: .importRoamTrip, object: nil)
                        }
                    } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("设置").accessibilityIdentifier("library-settings")
                }
            }
            .searchable(text: $search, prompt: "搜索目的地")
            .navigationDestination(for: UUID.self) { TripDetailView(tripID: $0) }
            .navigationDestination(for: TodayDayRoute.self) { route in
                if let trip = store.trips.first(where: { $0.id == route.tripID }),
                   let index = trip.days.firstIndex(where: { $0.id == route.dayID }) {
                    TripDetailView(tripID: route.tripID, initialDay: index)
                }
            }
            .sheet(isPresented: $showCreate) { TripEditor().environmentObject(store) }
            .sheet(isPresented: $showBackground) { HomeBackgroundPicker().environmentObject(backgrounds) }
            .sheet(isPresented: $showCloud) { CloudSyncView().environmentObject(store) }
            .sheet(isPresented: $showTrash) { TrashView().environmentObject(store) }
        }
    }
    private func sortableTripCard(_ trip: Trip) -> some View {
                            NavigationLink(value: trip.id) { DestinationCard(trip: trip) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("trip-\(trip.cover.isEmpty ? trip.destination : trip.cover)")
                                .accessibilityLabel("\(trip.destination)，\(trip.days.count)天，\(trip.status.rawValue)")
                                .draggable("roam-trip:" + trip.id.uuidString)
                                .dropDestination(for: String.self) { values, _ in
                                    guard let value = values.first, value.hasPrefix("roam-trip:"),
                                          let source = UUID(uuidString: String(value.dropFirst(10))) else { return false }
                                    return store.reorderTrip(source, onto: trip.id)
                                }
                                .accessibilityHint("长按后拖动可以调整位置，点按打开旅行")
                                .accessibilityAction(named: "向前移动") { moveTrip(trip.id, offset: -1) }
                                .accessibilityAction(named: "向后移动") { moveTrip(trip.id, offset: 1) }
    }

    private func moveTrip(_ id: UUID, offset: Int) {
        guard let index = filtered.firstIndex(where: { $0.id == id }), filtered.indices.contains(index + offset) else { return }
        _ = store.reorderTrip(id, onto: filtered[index + offset].id)
    }

}

struct TodayDayRoute: Hashable {
    let tripID: UUID
    let dayID: UUID
}

struct TodayItineraryCard: View {
    let trip: Trip
    let index: Int
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                if let photo = trip.coverPhoto.flatMap({ UIImage(data: $0) }) {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else if !trip.cover.isEmpty {
                    Image(trip.cover).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else { Color.blue }
                LinearGradient(colors: [.black.opacity(0.12), .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Label("今日行程", systemImage: "sun.max.fill").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("第 \(index + 1) 天").font(.subheadline)
                    }
                    Spacer(minLength: 8)
                    Text(trip.destination).font(.subheadline).opacity(0.85)
                    Text(trip.days[index].title).font(.title2.bold()).lineLimit(2)
                    Text(trip.date(for: index), format: .dateTime.month().day().weekday())
                        .font(.caption).opacity(0.85)
                    HStack {
                        Text(trip.days[index].items.isEmpty ? "今天自由安排" : trip.days[index].items.prefix(2).map(\.title).joined(separator: " · "))
                            .font(.subheadline).lineLimit(1)
                        Spacer(minLength: 4)
                    }
                }.padding(22).foregroundStyle(.white)
            }.clipShape(RoundedRectangle(cornerRadius: 26))
        }.aspectRatio(4.0 / 3.0, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: 26))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日行程，\(trip.destination)，第 \(index + 1) 天，\(trip.days[index].title)")
        .accessibilityHint("打开当天行程详情")
    }
}

struct DestinationCard: View {
    let trip: Trip
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let photo = trip.coverPhoto.flatMap({ UIImage(data: $0) }) {
                    GeometryReader { geo in
                        Image(uiImage: photo).resizable().scaledToFill()
                            .frame(width: geo.size.width, height: 142).clipped()
                    }.frame(height: 142)
                } else if !trip.cover.isEmpty, UIImage(named: trip.cover) != nil {
                    GeometryReader { geo in
                        Image(trip.cover).resizable().scaledToFill()
                            .frame(width: geo.size.width, height: 142).clipped()
                    }.frame(height: 142)
                } else {
                    ZStack {
                        Color.blue.opacity(0.08)
                        Image(systemName: "mountain.2").font(.system(size: 52, weight: .ultraLight))
                            .foregroundStyle(.blue.opacity(0.6))
                    }.frame(height: 142)
                }
                Text(trip.status == .wish ? "想去" : "\(trip.days.count) 天")
                    .font(.caption2.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule()).padding(10)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(trip.destination).font(.title3.weight(.bold)).foregroundStyle(.primary).lineLimit(1)
                    Spacer(minLength: 2)
                }
                Text(trip.status == .wish ? "\(trip.country) · 等一个出发的日子" : "\(trip.dateRange) · \(trip.country)")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }.padding(14).frame(height: 83)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct ItemSelection: Identifiable {
    let id = UUID()
    var dayID: UUID
    var category: PlanCategory
    var item: PlanItem?
}

struct TripDetailView: View {
    @EnvironmentObject private var store: TravelStore
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    @State private var singleDay = false
    @State private var organizingDay = false
    @State private var reorderingDays = false
    @State private var draggedDayID: UUID?
    @State private var hoveredDayID: UUID?
    @State private var tableHeaderPosition = ScrollPosition(edge: .leading)
    @Namespace private var dayCardMotion
    @State private var cardExpansion: CGFloat = 0
    @State private var cardLift: CGFloat = 0
    @State private var expandingDay: Int?
    @State private var visibleDayID: UUID?
    @State private var selectedDay = 0
    @State private var editing: ItemSelection?
    @State private var showTripEditor = false
    @State private var showRoute = false
    @State private var showDeleteDay = false
    @State private var showDeleteTrip = false
    init(tripID: UUID, initialDay: Int? = nil) {
        self.tripID = tripID
        _singleDay = State(initialValue: initialDay != nil)
        _selectedDay = State(initialValue: initialDay ?? 0)
    }
    private var trip: Trip? { store.trips.first { $0.id == tripID } }

    var body: some View {
        Group {
            if let trip {
                VStack(spacing: 0) {
                    if !singleDay {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(trip.destination)
                                .font(.system(size: 28, weight: .bold)).foregroundStyle(.primary)
                            Text("\(trip.dateRange) · \(trip.days.count) 天")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 22)
                    }
                    if reorderingDays { dayReorderView(trip) } else if singleDay { dailyView(trip).matchedGeometryEffect(id: trip.days[min(selectedDay, trip.days.count - 1)].id, in: dayCardMotion) } else { cardsView(trip).zIndex(10) }
                }
                .background {
                    ZStack(alignment: .top) {
                        Color(singleDay ? .systemBackground : .systemGroupedBackground)
                        if !singleDay { tripHeaderImage(trip) }
                    }
                    .ignoresSafeArea()
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .navigationBarBackButtonHidden(true)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
                .toolbarBackground(.hidden, for: .bottomBar)
                .onChange(of: trip.days.count) { _, count in selectedDay = min(selectedDay, count - 1) }
                .toolbar {
                    detailNavigation(trip)
                    ToolbarItemGroup(placement: .bottomBar) {
                        Spacer()
                        Button("地图路线", systemImage: "map") { showRoute = true }
                            .accessibilityIdentifier("show-route")
                        Button("加一天", systemImage: "plus") { addDay(trip) }
                            .accessibilityLabel("加一天").accessibilityIdentifier("add-day")
                    }
                }
                .sheet(item: $editing) { selection in
                    ItemEditor(tripID: tripID, selection: selection).environmentObject(store)
                }
                .sheet(isPresented: $showRoute) {
                    TripRouteView(tripID: tripID, initialDay: selectedDay).environmentObject(store)
                }
                .sheet(isPresented: $showTripEditor) { TripEditor(existing: trip).environmentObject(store) }
                .confirmationDialog("删除第 \(selectedDay + 1) 天及当天所有安排？", isPresented: $showDeleteDay, titleVisibility: .visible) {
                    Button("删除当天", role: .destructive) {
                        var changed = trip; changed.days.remove(at: selectedDay)
                        selectedDay = min(selectedDay, changed.days.count - 1); store.update(changed)
                    }
                } message: { Text("后面的日期会依次提前一天。此操作无法撤销。") }
                .confirmationDialog("删除“\(trip.destination)”旅行？", isPresented: $showDeleteTrip, titleVisibility: .visible) {
                    Button("删除旅行", role: .destructive) { store.deleteTrip(tripID); dismiss() }
                } message: { Text("攻略会移入垃圾桶，保留 30 天，期间可以恢复。") }
            } else { ContentUnavailableView("旅行已删除", systemImage: "suitcase") }
        }
    }

    private func tripHeaderImage(_ trip: Trip) -> some View {
        GeometryReader { geometry in
            Group {
                if let photo = trip.coverPhoto.flatMap({ UIImage(data: $0) }) {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else if !trip.cover.isEmpty, UIImage(named: trip.cover) != nil {
                    Image(trip.cover).resizable().scaledToFill()
                } else {
                    Color.blue.opacity(0.12)
                }
            }
            .frame(width: geometry.size.width, height: 310).clipped()
            .mask {
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.85), location: 0),
                    .init(color: .black.opacity(0.65), location: 0.25),
                    .init(color: .black.opacity(0.15), location: 0.68),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .frame(height: 310).accessibilityHidden(true).allowsHitTesting(false)
    }

    @ToolbarContentBuilder
    private func detailNavigation(_ trip: Trip) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                if reorderingDays { reorderingDays = false; draggedDayID = nil }
                else if singleDay { closeDay() }
                else { dismiss() }
            } label: {
                Image(systemName: singleDay ? "xmark" : "chevron.left")
            }
            .accessibilityLabel(singleDay ? "收起当天" : "返回")
            .accessibilityIdentifier(singleDay ? "close-day" : "back-trip")
        }
        ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("重新排序", systemImage: "arrow.up.arrow.down") {
                                singleDay = false; draggedDayID = nil; reorderingDays = true
                            }.accessibilityIdentifier("reorder-days")
                            Button(trip.status == .wish ? "加入行程 / 编辑旅行" : "编辑旅行", systemImage: "pencil") { showTripEditor = true }
                            ShareLink(item: TripPackage(trip: trip), preview: SharePreview(trip.destination)) {
                                Label("分享旅行 / AirDrop", systemImage: "square.and.arrow.up")
                            }.accessibilityIdentifier("share-trip")
                            Button("查看地图路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { showRoute = true }
                            Button("新增一天", systemImage: "calendar.badge.plus") { addDay(trip) }
                            if trip.days.count > 1 {
                                Button("删除第 \(selectedDay + 1) 天", systemImage: "calendar.badge.minus", role: .destructive) { showDeleteDay = true }
                            }
                            Divider()
                            Button(trip.status == .completed ? "移回计划中" : "标记为已结束", systemImage: "checkmark.circle") {
                                var changed = trip; changed.status = trip.status == .completed ? .planning : .completed; store.update(changed)
                            }
                            Button("删除旅行", systemImage: "trash", role: .destructive) { showDeleteTrip = true }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("旅行选项").accessibilityIdentifier("trip-options")
        }
    }

    private func dayReorderView(_ trip: Trip) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text("拖动卡片调整顺序，日期随顺序更新")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("完成") { draggedDayID = nil; reorderingDays = false }
                    .font(.subheadline.weight(.semibold)).accessibilityIdentifier("finish-day-reorder")
            }
            .padding(.horizontal, 22)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(Array(trip.days.enumerated()), id: \.element.id) { index, day in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("第 \(index + 1) 天").font(.caption.weight(.bold)).foregroundStyle(.blue)
                            Text(day.title.isEmpty ? "自由安排" : day.title)
                                .font(.subheadline.weight(.semibold)).lineLimit(3)
                            Spacer(minLength: 4)
                            Text(trip.date(for: index).formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day()))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(14).frame(maxWidth: .infinity, minHeight: 140, maxHeight: 140, alignment: .topLeading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.blue.opacity(draggedDayID == day.id ? 0.6 : 0), lineWidth: 2))
                        .opacity(draggedDayID == day.id ? 0.65 : 1)
                        .contentShape(RoundedRectangle(cornerRadius: 18))
                        .onDrag {
                            draggedDayID = day.id
                            hoveredDayID = nil
                            return NSItemProvider(object: day.id.uuidString as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: DayOrderDropDelegate(targetID: day.id, draggedID: $draggedDayID, hoveredID: $hoveredDayID, move: moveDay))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("reorder-day-\(index)")
                        .accessibilityAction(named: "向前移动") {
                            if index > 0 { moveDay(day.id, trip.days[index - 1].id) }
                        }
                        .accessibilityAction(named: "向后移动") {
                            if index + 1 < trip.days.count { moveDay(day.id, trip.days[index + 1].id) }
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 24)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("day-reorder-grid")
    }

    private func moveDay(_ source: UUID, _ target: UUID) {
        guard let trip, trip.days.indices.contains(selectedDay) else { return }
        let selectedID = trip.days[selectedDay].id
        withAnimation(.easeInOut(duration: 0.18)) {
            _ = store.reorderDay(source, onto: target, tripID: tripID)
            if let updated = store.trips.first(where: { $0.id == tripID }),
               let index = updated.days.firstIndex(where: { $0.id == selectedID }) { selectedDay = index }
        }
    }

    private func daySelector(_ trip: Trip) -> some View {
        Menu {
            Picker("选择天数", selection: $selectedDay) {
                ForEach(trip.days.indices, id: \.self) { index in
                    Text("第 \(index + 1) 天 · \(trip.date(for: index).formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day()))").tag(index)
                }
            }
        } label: {
            HStack(spacing: 7) {
                Text("第 \(selectedDay + 1) 天 · \(trip.date(for: selectedDay).formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day()))")
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold)).foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("day-picker")
    }

    private func openDay(_ index: Int) {
        selectedDay = index
        organizingDay = false
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
            singleDay = true
            cardExpansion = 0
            cardLift = 0
            expandingDay = nil
        }
    }

    private func closeDay() {
        organizingDay = false
        visibleDayID = trip?.days[min(selectedDay, (trip?.days.count ?? 1) - 1)].id
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { singleDay = false }
    }

    private func cardsView(_ trip: Trip) -> some View {
        GeometryReader { geometry in
            let cardWidth = min((geometry.size.width - 21 - 10) / 1.3, 500)
            let cardHeight = max(440, geometry.size.height - 28)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .center, spacing: 10) {
                    ForEach(Array(trip.days.enumerated()), id: \.element.id) { index, day in
                        dayCard(trip, day: day, index: index)
                                .frame(width: cardWidth, height: cardHeight)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
                                .clipShape(RoundedRectangle(cornerRadius: 28))
                                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.primary.opacity(0.06)))
                                .shadow(color: .black.opacity(0.09), radius: 16, y: 8)
                        .matchedGeometryEffect(id: day.id, in: dayCardMotion)
                        .scaleEffect(1 + (expandingDay == index ? cardExpansion * 0.12 : 0), anchor: .bottomLeading)
                        .offset(y: expandingDay == index ? cardLift : 0)
                        .id(day.id)
                        .zIndex(expandingDay == index ? 1 : 0)
                        .contentShape(RoundedRectangle(cornerRadius: 28))
                        .onTapGesture { openDay(index) }
                        .gesture(cardPan(index: index, dayID: day.id))
                        .accessibilityElement(children: .combine)
                        .accessibilityAction { openDay(index) }
                        .accessibilityIdentifier("day-header-\(index)")
                        .accessibilityLabel("第 \(index + 1) 天，\(day.title)，\(day.items.count) 项安排")
                        .accessibilityHint("向上滑动展开当天安排，左右滑动切换天数")
                    }
                }
                .scrollTargetLayout()
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .contentMargins(.horizontal, 21, for: .scrollContent)
            .scrollClipDisabled()
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollPosition(id: $visibleDayID, anchor: .leading)
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("day-cards")
        }
    }

    private func cardPan(index: Int, dayID: UUID) -> UpwardCardPan {
        UpwardCardPan(changed: { translation in
            expandingDay = index
            let distance: CGFloat = max(0, -translation.height)
            cardExpansion = min(1, distance / 240)
            cardLift = -min(distance * 0.7, 120)
        }, ended: { translation, cancelled in
            let upward = -translation.height
            let shouldOpen = !cancelled && upward > 100 && upward > abs(translation.width) * 1.7
            if shouldOpen {
                visibleDayID = dayID
                openDay(index)
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    cardExpansion = 0
                    cardLift = 0
                    expandingDay = nil
                }
            }
        })
    }

    private func dayCard(_ trip: Trip, day: TravelDay, index: Int) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("DAY " + String(format: "%02d", index + 1))
                        .font(.caption.weight(.bold)).tracking(2).foregroundStyle(.blue)
                    Text(day.title).font(.title2.weight(.bold)).foregroundStyle(.primary).lineLimit(2)
                    Text(trip.date(for: index).formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month(.twoDigits).day(.twoDigits)))
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)

            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .overlay(alignment: .bottom) { Divider().padding(.horizontal, 22) }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("当天安排").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(day.items.count) 项").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }.padding(.bottom, 8)
                ForEach(PlanCategory.allCases) { category in
                    let items = day.items.filter { $0.category == category }
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: category.symbol)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(category.color)
                            .frame(width: 22)
                        Text(category.rawValue).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(width: 45, alignment: .leading)
                        Text(items.first?.title ?? "待安排")
                            .font(.subheadline.weight(items.isEmpty ? .regular : .medium))
                            .foregroundStyle(items.isEmpty ? Color.secondary : Color.primary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        if items.count > 1 { Text("+\(items.count - 1)").font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(minHeight: 43, alignment: .top)
                    .padding(.vertical, 4)
                    if category != .notes { Divider().opacity(0.55) }
                }
                Spacer(minLength: 12)

            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func tableView(_ trip: Trip) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(PlanCategory.allCases) { category in
                                VStack(spacing: 7) {
                                    Image(systemName: category.symbol).font(.body)
                                    Text(category.rawValue).font(.caption2.weight(.medium))
                                }.foregroundStyle(category.color)
                                    .frame(width: 62, height: rowHeight(category))
                                    .overlay(alignment: .top) { Divider() }
                            }
                        }.background(Color(.secondarySystemGroupedBackground))
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(Array(trip.days.enumerated()), id: \.element.id) { index, day in
                                    VStack(spacing: 0) {
                                        ForEach(PlanCategory.allCases) { category in
                                            tableCell(trip: trip, day: day, index: index, category: category)
                                                .overlay(alignment: .top) { Divider() }
                                        }
                                    }.frame(width: 166)
                                        .background(index.isMultiple(of: 2) ? Color(.secondarySystemGroupedBackground) : Color("ItineraryAlternate"))
                                        .overlay(alignment: .trailing) { Divider() }
                                }
                            }
                        }
                        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, offset in
                            tableHeaderPosition.scrollTo(x: max(0, offset))
                        }
                    }
                } header: {
                    HStack(spacing: 0) {
                        Text("安排").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            .frame(width: 62, height: 64)
                            .background(Color(.secondarySystemGroupedBackground))
                        ScrollView(.horizontal) {
                            HStack(spacing: 0) {
                                ForEach(Array(trip.days.enumerated()), id: \.element.id) { index, day in
                                    Button {
                                        selectedDay = index; singleDay = true
                                    } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack {
                                                Text("DAY \(index + 1)").font(.caption2.weight(.bold)).foregroundStyle(.blue)
                                                Spacer()
                                                Text(trip.date(for: index).formatted(.dateTime.month(.twoDigits).day(.twoDigits))).font(.caption2).foregroundStyle(.secondary)
                                            }
                                            Text(day.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                        }.padding(12).frame(width: 166, height: 64).contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityIdentifier("day-header-\(index)")
                                        .background(index.isMultiple(of: 2) ? Color(.secondarySystemGroupedBackground) : Color("ItineraryAlternate"))
                                        .overlay(alignment: .trailing) { Divider() }
                                }
                            }
                        }
                        .scrollPosition($tableHeaderPosition)
                        .scrollDisabled(true)
                        .scrollIndicators(.hidden)
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .overlay(alignment: .bottom) { Divider() }
                }
            }
            .frame(maxWidth: CGFloat(62 + 166 * trip.days.count))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 14)
            Text("先安排想做的事，具体时间可以慢慢决定。")
                .font(.caption).foregroundStyle(.secondary).padding(20)
        }.accessibilityIdentifier("itinerary-table")
    }

    private func tableCell(trip: Trip, day: TravelDay, index: Int, category: PlanCategory) -> some View {
        let items = day.items.filter { $0.category == category }
        return Button {
            selectedDay = index
            if items.count == 1 { editing = ItemSelection(dayID: day.id, category: category, item: items[0]) }
            else if items.isEmpty { editing = ItemSelection(dayID: day.id, category: category) }
            else { singleDay = true }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                if items.isEmpty {
                    Label("添加", systemImage: "plus").font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(items.prefix(2)) { item in
                        if category == .transport, let mode = item.transportMode {
                            Label([mode.rawValue, item.transportNumber].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "), systemImage: mode.symbol)
                                .font(.caption.weight(.semibold)).foregroundStyle(category.color)
                        }
                        Text(item.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                    }
                    if items.count == 1, let first = items.first, !first.detail.isEmpty {
                        Text(first.detail).font(.caption).foregroundStyle(.secondary).lineLimit(category == .stay ? 2 : 3)
                    }
                    if let firstPhoto = items.first?.photos?.first, let image = UIImage(data: firstPhoto) {
                        HStack(spacing: 6) {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 38, height: 32).clipped().clipShape(RoundedRectangle(cornerRadius: 5))
                            if let count = items.first?.photos?.count, count > 1 {
                                Text("共 \(count) 张照片").font(.caption2).foregroundStyle(.secondary)
                            }
                        }.accessibilityLabel("安排照片")
                    }
                    if let place = items.first?.mapPlaces.first?.place {
                        Label(place.name, systemImage: "mappin").font(.caption2).foregroundStyle(.blue).lineLimit(1)
                    }
                    if items.count > 2 { Text("另有 \(items.count - 2) 项").font(.caption2).foregroundStyle(.blue) }
                }
                Spacer(minLength: 0)
            }.padding(12).frame(width: 166, height: rowHeight(category), alignment: .topLeading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("cell-\(index)-\(category.rawValue)")
    }

    private func rowHeight(_ category: PlanCategory) -> CGFloat {
        category == .stay ? 106 : category == .explore || category == .notes ? 150 : 130
    }

    private func dailyView(_ trip: Trip) -> some View {
        let day = trip.days[min(selectedDay, trip.days.count - 1)]
        return VStack(spacing: 0) {
            if organizingDay {
                HStack {
                    Text("整理当天安排").font(.headline)
                    Spacer()
                    Button("完成") { organizingDay = false }
                }.padding(.horizontal, 20).padding(.vertical, 8)
                dailyOrganization(trip)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                daySelector(trip)
                                TextField("给今天起个名字", text: Binding(get: { day.title }, set: { value in
                                    var changed = trip; changed.days[selectedDay].title = value; store.update(changed)
                                }), axis: .vertical)
                                .font(.title2.bold()).accessibilityIdentifier("day-title")
                                Text("\(day.items.count) 项安排 · \(day.routeItems.count) 个地图地点")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.top, 8)
                        HStack {
                            Button { showRoute = true } label: {
                                Label("查看当天路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            }.buttonStyle(.bordered).accessibilityIdentifier("day-route")
                            Spacer()
                            Button { organizingDay = true } label: {
                                Label("整理", systemImage: "slider.horizontal.3")
                            }.accessibilityLabel("整理安排").accessibilityIdentifier("organize-day")
                        }.font(.subheadline)
                        dayCategoryCard(day, category: .explore)
                        dayCategoryCard(day, category: .food)
                        dayCategoryCard(day, category: .stay)
                        dayCategoryCard(day, category: .transport)
                        dayCategoryCard(day, category: .notes)
                        Text("点安排即可编辑 · 按自己的节奏出发")
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 4)
                    }.padding(.horizontal, 18).padding(.bottom, 20)
                }.background(Color(.systemBackground)).accessibilityIdentifier("daily-itinerary")
            }
        }
    }

    private func dayCategoryCard(_ day: TravelDay, category: PlanCategory) -> some View {
        let items = day.items.filter { $0.category == category }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: category.symbol).font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32).background(category.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                Text(category.rawValue).font(.headline)
                Spacer(minLength: 0)
                if !items.isEmpty { Text("\(items.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            }.foregroundStyle(category.color)
            ForEach(items) { item in
                Button { editing = ItemSelection(dayID: day.id, category: category, item: item) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        if !item.time.isEmpty {
                            Text(item.time).font(.caption.weight(.semibold)).foregroundStyle(category.color)
                                .padding(.horizontal, 8).padding(.vertical, 4).background(category.color.opacity(0.08), in: Capsule())
                        }
                        if category == .transport, let mode = item.transportMode {
                            Label([mode.rawValue, item.transportNumber].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "), systemImage: mode.symbol)
                                .font(.subheadline.weight(.semibold)).foregroundStyle(category.color)
                        }
                        Text(item.title).font(.title3.weight(.semibold))
                            .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                        if let photos = item.photos, !photos.isEmpty {
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(photos.indices, id: \.self) { index in
                                        if let image = UIImage(data: photos[index]) {
                                            Image(uiImage: image).resizable().scaledToFill()
                                                .frame(width: 116, height: 88).clipped()
                                                .clipShape(RoundedRectangle(cornerRadius: 9))
                                                .accessibilityLabel("安排照片 \(index + 1)")
                                        }
                                    }
                                }
                            }.scrollIndicators(.hidden)
                        }
                        if !item.detail.isEmpty {
                            Text(item.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        if !item.mapPlaces.isEmpty {
                            Label(item.mapPlaces.map { $0.place.name }.joined(separator: " → "), systemImage: "mappin")
                                .font(.caption).foregroundStyle(category.color).fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("day-item-\(item.title)").accessibilityHint("编辑这项安排")
                if item.id != items.last?.id { Divider().opacity(0.5) }
            }
            if items.isEmpty {
                Text(category == .stay ? "今晚住哪里？" : category == .food ? "留一家想吃的店" : category == .explore ? "把想去的地方放进今天" : category == .transport ? "记下车次、航班或出行方式" : "灵感、预约与随手记")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Button { editing = ItemSelection(dayID: day.id, category: category) } label: {
                Label(category == .stay ? "添加住宿" : category == .food ? "添加美食" : category == .notes ? "写备忘" : "添加安排", systemImage: "plus")
                    .font(.subheadline.weight(.medium)).frame(minHeight: 32)
            }.tint(category.color).accessibilityIdentifier("add-\(category.rawValue)")
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.bottom, 22)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func dailyOrganization(_ trip: Trip) -> some View {
        let day = trip.days[min(selectedDay, trip.days.count - 1)]
        return List {
            Section {
                TextField("给今天起个名字", text: Binding(get: { day.title }, set: { value in
                    var changed = trip; changed.days[selectedDay].title = value; store.update(changed)
                })).font(.headline).accessibilityIdentifier("day-title")
            }
            ForEach(PlanCategory.allCases) { category in
                Section {
                    let items = day.items.filter { $0.category == category }
                    ForEach(items) { item in
                        Button {
                            editing = ItemSelection(dayID: day.id, category: category, item: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    Spacer()
                                    if !item.time.isEmpty { Text(item.time).font(.caption).foregroundStyle(.secondary) }
                                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                                }
                                if !item.mapPlaces.isEmpty {
                                    Label(item.mapPlaces.map { $0.place.name }.joined(separator: " → "), systemImage: "mappin.circle.fill").font(.caption).foregroundStyle(.blue)
                                }
                                if !item.detail.isEmpty { Text(item.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(4) }
                            }.padding(.vertical, 3)
                        }.buttonStyle(.plain).swipeActions {
                            Button("删除", role: .destructive) { store.removeItem(item.id, tripID: tripID, dayID: day.id) }
                        }
                    }
                    .onMove { source, destination in
                        var ordered = items; ordered.move(fromOffsets: source, toOffset: destination)
                        var changed = trip
                        changed.days[selectedDay].items.removeAll { $0.category == category }
                        changed.days[selectedDay].items.append(contentsOf: ordered)
                        store.update(changed)
                    }
                    Button { editing = ItemSelection(dayID: day.id, category: category) } label: {
                        Label("添加\(category == .notes ? "备忘" : "安排")", systemImage: "plus").font(.subheadline)
                    }.accessibilityIdentifier("add-\(category.rawValue)")
                } header: {
                    HStack {
                        Label(category.rawValue, systemImage: category.symbol).foregroundStyle(category.color)
                        Spacer()
                    }
                }
            }
            Section { EditButton().accessibilityIdentifier("reorder-items") } footer: { Text("时间选填。点开任意安排，可以把它移到其他天。") }
        }.listStyle(.insetGrouped).contentMargins(.top, 8, for: .scrollContent).accessibilityIdentifier("daily-itinerary")
    }

    private func addDay(_ trip: Trip) {
        var changed = trip; changed.days.append(TravelDay()); store.update(changed)
        selectedDay = changed.days.count - 1; singleDay = true
    }
}

struct TripEditor: View {
    @EnvironmentObject private var store: TravelStore
    @Environment(\.dismiss) private var dismiss
    var existing: Trip?
    var defaultWishlist = false
    @State private var destination = ""
    @State private var country = ""
    @State private var date = Date()
    @State private var duration = 3
    @State private var status: TripStatus = .planning
    @State private var cover = ""
    @State private var coverPhoto: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotoFile = false
    @State private var photoError: String?
    @State private var loadingPhoto = false
    @State private var loaded = false
    @State private var confirmShorten = false
    private var valid: Bool { !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("去哪里") {
                    TextField("目的地，例如：杭州", text: $destination).accessibilityIdentifier("destination-field")
                    TextField("国家 / 地区（选填）", text: $country)
                }
                Section("旅行安排") {
                    Picker("状态", selection: $status) { ForEach(TripStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    if status != .wish { DatePicker("出发日期", selection: $date, displayedComponents: .date) }
                    Stepper("\(duration) 天", value: $duration, in: 1...60).accessibilityIdentifier("duration-stepper")
                }
                Section("封面") {
                    if let image = coverPhoto.flatMap({ UIImage(data: $0) }) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(height: 150).frame(maxWidth: .infinity).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .accessibilityIdentifier("custom-cover-preview")
                        Button("移除自选照片", role: .destructive) { coverPhoto = nil; selectedPhoto = nil }
                    }
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("从相册选择", systemImage: "photo.on.rectangle")
                    }.accessibilityIdentifier("choose-cover-photo")
                    Button { showPhotoFile = true } label: {
                        Label("从文件选择", systemImage: "folder")
                    }.accessibilityIdentifier("choose-cover-file")
                    if loadingPhoto { ProgressView("正在处理照片…") }
                    Text("照片随行程同步到你自己的 iCloud 私人空间。")
                        .font(.caption).foregroundStyle(.secondary)

                    Picker("内置封面", selection: $cover) {
                        Text("简约封面").tag("")
                        Text("东京").tag("tokyo")
                        Text("京都").tag("kyoto")
                        Text("富士山").tag("fuji")
                    }
                }
                Section {
                    Label("吃、逛、住，之后都可以慢慢补充。", systemImage: "square.grid.2x2")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(existing == nil ? "新的旅行" : "编辑旅行").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let existing, duration < existing.days.count { confirmShorten = true } else { save() }
                    }.disabled(!valid || loadingPhoto).accessibilityIdentifier("save-trip")
                }
            }
            .onAppear {
                guard !loaded else { return }; loaded = true
                coverPhoto = existing?.coverPhoto
                if let existing {
                    destination = existing.destination; country = existing.country; date = existing.startDate
                    duration = existing.days.count; status = existing.status; cover = existing.cover
                } else { status = defaultWishlist ? .wish : .planning }
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                loadingPhoto = true
                defer { loadingPhoto = false }
                do {
                    guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else { throw CoverPhotoError.invalid }
                    let compressed = try await Task.detached { try CoverPhotoCodec.compress(data) }.value
                    guard !Task.isCancelled else { return }
                    coverPhoto = compressed
                } catch { if !Task.isCancelled { photoError = "无法读取这张照片，请选择其他图片。" } }
            }
            .fileImporter(isPresented: $showPhotoFile, allowedContentTypes: [.image]) { result in
                switch result {
                case .success(let url):
                    loadingPhoto = true
                    Task {
                        defer { loadingPhoto = false }
                        do {
                            let data = try await Task.detached {
                                let access = url.startAccessingSecurityScopedResource()
                                defer { if access { url.stopAccessingSecurityScopedResource() } }
                                return try CoverPhotoCodec.compress(Data(contentsOf: url))
                            }.value
                            coverPhoto = data
                        } catch { photoError = "无法读取这张照片，请选择其他图片。" }
                    }
                case .failure: photoError = "未能打开文件，请重试。"
                }
            }
            .alert("照片导入失败", isPresented: Binding(get: { photoError != nil }, set: { if !$0 { photoError = nil } })) {
                Button("好") { photoError = nil }
            } message: { Text(photoError ?? "") }
            .confirmationDialog("缩短旅行会删除最后几天的安排", isPresented: $confirmShorten, titleVisibility: .visible) {
                Button("缩短并保存", role: .destructive) { save() }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func save() {
        var days = existing?.days ?? []
        if days.count < duration { days.append(contentsOf: (days.count..<duration).map { _ in TravelDay() }) }
        else { days = Array(days.prefix(duration)) }
        let trip = Trip(id: existing?.id ?? UUID(), destination: destination.trimmingCharacters(in: .whitespacesAndNewlines), country: country, startDate: date, cover: cover, coverPhoto: coverPhoto, status: status, days: days)
        if existing != nil { store.update(trip) } else { store.trips.insert(trip, at: 0) }
        dismiss()
    }
}

struct ItemEditor: View {
    @EnvironmentObject private var store: TravelStore
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    let selection: ItemSelection
    @State private var title: String
    @State private var detail: String
    @State private var time: String
    @State private var category: PlanCategory
    @State private var transportMode: TransportMode?
    @State private var transportNumber: String
    @State private var itemPhotos: [Data]
    @State private var selectedItemPhotos: [PhotosPickerItem] = []
    @State private var showItemPhotoFiles = false
    @State private var loadingItemPhotos = false
    @State private var itemPhotoError: String?
    @State private var dayID: UUID
    @State private var endDayID: UUID
    @State private var multipleNights = false
    @State private var confirmDelete = false
    @State private var places: [PlanWaypoint]
    @State private var showPlacePicker = false
    init(tripID: UUID, selection: ItemSelection) {
        self.tripID = tripID; self.selection = selection
        _places = State(initialValue: selection.item?.mapPlaces ?? [])
        _title = State(initialValue: selection.item?.title ?? "")
        _detail = State(initialValue: selection.item?.detail ?? "")
        _time = State(initialValue: selection.item?.time ?? "")
        _category = State(initialValue: selection.category)
        _transportMode = State(initialValue: selection.item?.transportMode)
        _transportNumber = State(initialValue: selection.item?.transportNumber ?? "")
        _itemPhotos = State(initialValue: selection.item?.photos ?? [])
        _dayID = State(initialValue: selection.dayID)
        _endDayID = State(initialValue: selection.dayID)
    }
    private var trip: Trip? { store.trips.first { $0.id == tripID } }
    private var valid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !itemPhotos.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("安排什么") {
                    TextField("地点或安排", text: $title, axis: .vertical).accessibilityIdentifier("item-title")
                    Picker("分类", selection: $category) { ForEach(PlanCategory.allCases) { Text($0.rawValue).tag($0) } }
                    if category == .transport {
                        Picker("出行方式", selection: $transportMode) {
                            Text("未指定").tag(nil as TransportMode?)
                            ForEach(TransportMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode.symbol).tag(Optional(mode))
                            }
                        }.accessibilityIdentifier("transport-mode")
                        if let mode = transportMode, let label = mode.numberLabel {
                            LabeledContent(label) {
                                TextField(mode.numberExample, text: $transportNumber)
                                    .multilineTextAlignment(.trailing)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .accessibilityIdentifier("transport-number")
                            }
                        }
                    }
                }
                if let trip {
                    Section("安排在哪一天") {
                        Picker("日期", selection: $dayID) {
                            ForEach(Array(trip.days.enumerated()), id: \.element.id) { index, day in
                                Text("第 \(index + 1) 天 · \(day.title)").tag(day.id)
                            }
                        }.accessibilityIdentifier("item-day")
                        TextField("时间（选填，例如：午后）", text: $time).accessibilityIdentifier("item-time")
                        if category == .stay {
                            Toggle("连续多晚住这里", isOn: $multipleNights)
                            if multipleNights {
                                Picker("最后一晚", selection: $endDayID) {
                                    let first = trip.days.firstIndex { $0.id == dayID } ?? 0
                                    ForEach(first..<trip.days.count, id: \.self) { index in
                                        Text("第 \(index + 1) 天").tag(trip.days[index].id)
                                    }
                                }
                            }
                        }
                    }
                }
                Section("照片 · \(itemPhotos.count)/8") {
                    if !itemPhotos.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(itemPhotos.indices, id: \.self) { index in
                                    if let image = UIImage(data: itemPhotos[index]) {
                                        VStack(spacing: 5) {
                                            Image(uiImage: image).resizable().scaledToFill()
                                                .frame(width: 112, height: 88).clipped()
                                                .clipShape(RoundedRectangle(cornerRadius: 9))
                                            Button("移除第 \(index + 1) 张", systemImage: "trash", role: .destructive) {
                                                itemPhotos.remove(at: index)
                                            }.font(.caption).accessibilityIdentifier("remove-item-photo-\(index)")
                                        }
                                    }
                                }
                            }.padding(.vertical, 4)
                        }.scrollIndicators(.hidden)
                    }
                    if itemPhotos.count < 8 && !loadingItemPhotos {
                        PhotosPicker(selection: $selectedItemPhotos, maxSelectionCount: 8 - itemPhotos.count, matching: .images) {
                            Label("从相册添加图片", systemImage: "photo.on.rectangle")
                        }.accessibilityIdentifier("choose-item-photos")
                        Button { showItemPhotoFiles = true } label: {
                            Label("从文件添加图片", systemImage: "folder")
                        }.accessibilityIdentifier("choose-item-photo-files")
                    }
                    if loadingItemPhotos { ProgressView("正在处理图片…") }
                    Text("每条安排最多 8 张。图片随行程保存在你的 iCloud 私人空间，分享旅行时也会一同发送。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("地图地点 · \(places.count) 个") {
                    if !places.isEmpty {
                        Map {
                            ForEach(Array(places.enumerated()), id: \.element.id) { index, waypoint in
                                Marker("\(index + 1). \(waypoint.place.name)", coordinate: waypoint.place.coordinate)
                            }
                            if places.count > 1 {
                                MapPolyline(coordinates: places.map { $0.place.coordinate })
                                    .stroke(.blue, style: StrokeStyle(lineWidth: 3, dash: [5, 4]))
                            }
                        }.id(places.map(\.id)).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 12))
                        if places.contains(where: { $0.place.source == "OpenStreetMap" }) {
                            Link("地点数据 © OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!).font(.caption2)
                        }
                        ForEach(Array(places.enumerated()), id: \.element.id) { index, waypoint in
                            HStack {
                                Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(waypoint.place.name)
                                    Text(waypoint.place.address).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Menu {
                                    Button("上移", systemImage: "arrow.up") { places.swapAt(index, index - 1) }.disabled(index == 0)
                                    Button("下移", systemImage: "arrow.down") { places.swapAt(index, index + 1) }.disabled(index == places.count - 1)
                                    Button("在地图中打开", systemImage: "arrow.up.right.square") { waypoint.place.mapItem.openInMaps() }
                                    Button("移除地点", role: .destructive) { places.removeAll { $0.id == waypoint.id } }
                                } label: { Image(systemName: "ellipsis.circle") }
                            }
                        }
                    }
                    Button(places.isEmpty ? "选择多个地点 / 地图选点" : "继续添加地点", systemImage: "plus.circle") { showPlacePicker = true }
                        .accessibilityIdentifier("choose-place")
                    if places.count > 1 { Text("按上方顺序连线；可在当天地图路线中选择地点、计算道路路线。")
                        .font(.caption).foregroundStyle(.secondary) }
                }
                Section("攻略与备注") {
                    TextEditor(text: $detail).frame(minHeight: 150).accessibilityIdentifier("item-detail")
                }
                Section {
                    Text("可以放地址、预订信息、攻略链接，或几个备选。时间不用急着确定。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if selection.item != nil {
                    Section { Button("删除这项安排", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(selection.item == nil ? "添加安排" : "编辑安排").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var item = PlanItem(id: selection.item?.id ?? UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "照片" : title.trimmingCharacters(in: .whitespacesAndNewlines), detail: detail, time: time, category: category, places: places)
                        item.transportMode = category == .transport ? transportMode : nil
                        let number = transportNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                        item.transportNumber = category == .transport && transportMode?.numberLabel != nil && !number.isEmpty ? number : nil
                        item.photos = itemPhotos.isEmpty ? nil : itemPhotos
                        store.upsert(item, tripID: tripID, from: selection.item == nil ? nil : selection.dayID, to: dayID, through: multipleNights ? endDayID : nil)
                        dismiss()
                    }.disabled(!valid || loadingItemPhotos).accessibilityIdentifier("save-item")
                }
            }
            .task(id: selectedItemPhotos) {
                guard !selectedItemPhotos.isEmpty else { return }
                loadingItemPhotos = true
                defer { loadingItemPhotos = false; selectedItemPhotos = [] }
                do {
                    var added: [Data] = []
                    for photo in selectedItemPhotos.prefix(max(0, 8 - itemPhotos.count)) {
                        guard let data = try await photo.loadTransferable(type: Data.self) else { throw CoverPhotoError.invalid }
                        let compressed = try await Task.detached { try CoverPhotoCodec.compress(data, maxPixelSize: 1200, quality: 0.72) }.value
                        guard compressed.count <= 5_000_000 else { throw CoverPhotoError.invalid }
                        added.append(compressed)
                    }
                    guard !Task.isCancelled else { return }
                    itemPhotos.append(contentsOf: added)
                } catch {
                    if !Task.isCancelled { itemPhotoError = "图片无法读取或过大，请选择其他图片。" }
                }
            }
            .fileImporter(isPresented: $showItemPhotoFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    loadingItemPhotos = true
                    Task {
                        defer { loadingItemPhotos = false }
                        do {
                            let remaining = max(0, 8 - itemPhotos.count)
                            let added = try await Task.detached { () throws -> [Data] in
                                try urls.prefix(remaining).map { url in
                                    let access = url.startAccessingSecurityScopedResource()
                                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 30_000_000 else { throw CoverPhotoError.invalid }
                                    let data = try CoverPhotoCodec.compress(Data(contentsOf: url), maxPixelSize: 1200, quality: 0.72)
                                    guard data.count <= 5_000_000 else { throw CoverPhotoError.invalid }
                                    return data
                                }
                            }.value
                            itemPhotos.append(contentsOf: added)
                        } catch { itemPhotoError = "图片无法读取或过大，请选择其他图片。" }
                    }
                case .failure: itemPhotoError = "未能打开文件，请重试。"
                }
            }
            .alert("图片导入失败", isPresented: Binding(get: { itemPhotoError != nil }, set: { if !$0 { itemPhotoError = nil } })) {
                Button("好") { itemPhotoError = nil }
            } message: { Text(itemPhotoError ?? "") }
            .sheet(isPresented: $showPlacePicker) {
                PlacePicker(destination: [trip?.country, trip?.destination].compactMap { $0 }.joined(separator: " "), existing: places.last?.place) { selected in
                    places.append(contentsOf: selected.map { PlanWaypoint(place: $0) })
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { title = selected.map(\.name).joined(separator: " → ") }
                }
            }
            .onChange(of: dayID) { _, new in endDayID = new }
            .onChange(of: transportMode) { _, _ in transportNumber = "" }
            .confirmationDialog("删除这项安排？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let item = selection.item { store.removeItem(item.id, tripID: tripID, dayID: selection.dayID) }
                    dismiss()
                }
            }
        }.presentationDragIndicator(.visible)
    }
}

extension PlanPlace {
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var region: MKCoordinateRegion { .init(center: coordinate, span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)) }
    var mapItem: MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
        item.name = name
        return item
    }
    init(mapItem: MKMapItem) {
        name = mapItem.name ?? "地图地点"
        address = mapItem.address?.fullAddress ?? ""
        latitude = mapItem.location.coordinate.latitude
        longitude = mapItem.location.coordinate.longitude
    }
}

struct PlacePicker: View {
    @Environment(\.dismiss) private var dismiss
    let destination: String
    let existing: PlanPlace?
    let onSelect: ([PlanPlace]) -> Void
    @State private var query = ""
    @State private var searchFocused = false
    @StateObject private var searchModel = PlaceSearchModel()
    @State private var searchCity = ""
    @State private var editCity = false
    @State private var selectedPlaces: [PlanPlace] = []
    @State private var position: MapCameraPosition = .automatic
    @State private var center: CLLocationCoordinate2D?
    @State private var manual = false
    @State private var pinName = ""
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Button { searchFocused = false; editCity = true } label: {
                    HStack {
                        Image(systemName: "globe.asia.australia.fill").font(.title2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("1 · 国家 / 地区与城市").font(.caption).foregroundStyle(.secondary)
                            Text(searchCity.isEmpty ? "点这里选择" : searchCity).font(.headline)
                        }
                        Spacer()
                        Text("更改").font(.subheadline)
                        Image(systemName: "chevron.right").font(.caption)
                    }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).accessibilityIdentifier("search-city").padding(.horizontal).padding(.bottom, 10)
                if !manual {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("2 · 搜索想去的地点").font(.subheadline.bold()).padding(.horizontal, 8)
                        NativePlaceSearchBar(text: $query, focused: $searchFocused, onSearch: search)
                        if searchModel.resolvingArea { ProgressView("正在定位城市…").font(.caption) }
                    }.padding(.horizontal, 8).padding(.bottom, 6)
                }
                Picker("选点方式", selection: $manual) {
                    Text("搜索地点").tag(false)
                    Text("地图选点").tag(true)
                }.pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8)
                Map(position: $position) {
                    if !manual {
                        ForEach(Array(searchModel.places.prefix(6).enumerated()), id: \.offset) { _, place in
                            if !selectedPlaces.contains(place) {
                                Annotation(place.name, coordinate: place.coordinate) {
                                    Button { selectedPlaces.append(place); searchFocused = false; position = .region(place.region) } label: {
                                        Image(systemName: "mappin.circle.fill").font(.title).foregroundStyle(.blue).background(.white, in: Circle())
                                    }.accessibilityLabel("选择" + place.name)
                                }
                            }
                        }
                    }
                    ForEach(Array(selectedPlaces.enumerated()), id: \.offset) { index, place in
                        Marker("\(index + 1). \(place.name)", coordinate: place.coordinate)
                    }
                    if selectedPlaces.count > 1 {
                        MapPolyline(coordinates: selectedPlaces.map(\.coordinate)).stroke(.blue, style: StrokeStyle(lineWidth: 3, dash: [5, 4]))
                    }
                }
                .mapControls { MapCompass(); MapScaleView() }
                .onMapCameraChange(frequency: .onEnd) { center = $0.region.center }
                .overlay {
                    if manual {
                        Image(systemName: "mappin.circle.fill").font(.largeTitle).foregroundStyle(.red)
                            .background(.white, in: Circle()).allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Button { if let area = searchModel.area { position = .region(area.region) } } label: {
                        Image(systemName: "scope").padding(10).background(.regularMaterial, in: Circle())
                    }.accessibilityLabel("回到搜索城市").padding(10)
                }
                .frame(height: manual ? 250 : searchFocused ? 100 : 170)
                .accessibilityIdentifier("place-preview-map")
                if !selectedPlaces.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(Array(selectedPlaces.enumerated()), id: \.offset) { index, place in
                                Button { selectedPlaces.remove(at: index) } label: {
                                    Label("\(index + 1). \(place.name)", systemImage: "xmark.circle.fill")
                                }.buttonStyle(.bordered).font(.caption)
                            }
                        }.padding(.horizontal)
                    }.padding(.vertical, 6)
                }
                if manual {
                    Form {
                        Section {
                            TextField("地点名称", text: $pinName).accessibilityIdentifier("pin-name")
                            Button("加入已选地点", systemImage: "plus.circle.fill") {
                                if let pin = manualPin { selectedPlaces.append(pin); pinName = "" }
                            }.disabled(center == nil).accessibilityIdentifier("add-map-pin")
                            Text("移动地图对准位置，加入已选后可继续选下一站。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    if searchModel.loading { ProgressView("正在搜索地点…").padding() }
                    if let message = searchModel.message {
                        HStack {
                            Text(message).font(.subheadline).foregroundStyle(.secondary)
                            Button("重试", action: search).disabled(query.isEmpty || searchModel.loading)
                        }.padding(.horizontal)
                    }
                    List {
                        ForEach(Array(searchModel.completions.enumerated()), id: \.offset) { _, completion in
                            Button {
                                searchFocused = false
                                searchTask?.cancel()
                                searchTask = Task { await searchModel.search(query, completion: completion) }
                            } label: {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(completion.title).foregroundStyle(.primary)
                                        Text(completion.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }.accessibilityIdentifier("place-suggestion")
                        }
                        ForEach(Array(searchModel.places.enumerated()), id: \.offset) { _, place in
                            Button {
                                searchFocused = false
                                if let index = selectedPlaces.firstIndex(of: place) { selectedPlaces.remove(at: index) }
                                else { selectedPlaces.append(place) }
                                position = .region(place.region)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(place.name).foregroundStyle(.primary)
                                        Text(place.address).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Label(selectedPlaces.contains(place) ? "已选" : "选择", systemImage: selectedPlaces.contains(place) ? "checkmark.circle.fill" : "plus.circle").font(.subheadline).foregroundStyle(.blue)
                                }
                            }.accessibilityIdentifier("place-result")
                        }
                        if query.isEmpty {
                            Text("在上方输入景点、餐厅、酒店或车站名称。\n例如：东京站、银座。\n点搜索建议查看地点，再点“选择”加入。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.listStyle(.plain).scrollDismissesKeyboard(.interactively)
                    if searchModel.places.contains(where: { $0.source == "OpenStreetMap" }) {
                        Link("地点数据 © OpenStreetMap contributors · Photon", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                            .font(.caption2).padding(.bottom, 4)
                    }
                }
            }
            .navigationTitle("选择地图地点").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button(selectedPlaces.isEmpty ? "请先选择地点" : "添加 \(selectedPlaces.count) 个地点") {
                    if selectedPlaces.isEmpty, manual, let pin = manualPin { onSelect([pin]) }
                    else { onSelect(selectedPlaces) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPlaces.isEmpty && (!manual || center == nil))
                .accessibilityIdentifier("save-place")
                .frame(maxWidth: .infinity).padding(10).background(.regularMaterial)
            }
            .onAppear {
                guard searchCity.isEmpty else { return }
                pinName = ""; searchCity = destination
                if let existing { center = existing.coordinate; position = .region(existing.region) }
            }
            .task(id: searchCity) {
                guard !searchCity.isEmpty else { return }
                searchTask?.cancel()
                await searchModel.configure(searchCity)
                if let area = searchModel.area { position = .region(area.region) }
                if searchModel.area != nil { scheduleSuggestions() }
            }
            .onChange(of: query) { _, _ in scheduleSuggestions() }
            .sheet(isPresented: $editCity) {
                SearchCityEditor(initial: searchCity) { city in query = ""; searchCity = city }
            }
            .onChange(of: manual) { _, value in
                if value { searchTask?.cancel(); searchModel.invalidate() }
                else { scheduleSuggestions() }
            }
            .onDisappear { searchTask?.cancel(); searchModel.invalidate() }
        }
    }

    private var manualPin: PlanPlace? {
        guard let center else { return nil }
        let name = pinName.trimmingCharacters(in: .whitespacesAndNewlines)
        return PlanPlace(name: name.isEmpty ? "地图选点 \(selectedPlaces.count + 1)" : name, address: "", latitude: center.latitude, longitude: center.longitude)
    }

    private func scheduleSuggestions() {
        searchTask?.cancel()
        guard searchModel.area != nil else { return }
        searchModel.invalidate()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !manual else { return }
        searchTask = Task {
            do { try await Task.sleep(for: .milliseconds(650)); try Task.checkCancellation() }
            catch { return }
            await searchModel.suggest(text)
        }
    }
    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searchFocused = false; searchTask?.cancel()
        searchTask = Task { await searchModel.search(text) }
    }
}

struct TripRouteView: View {
    @EnvironmentObject private var store: TravelStore
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    @State private var dayIndex: Int
    @State private var driving = false
    @State private var showSelection = false
    @State private var showAddPlace = false
    @State private var position: MapCameraPosition = .automatic
    @State private var routes: [Int: MKRoute] = [:]
    @State private var routeTask: Task<Void, Never>?
    @State private var activeDirections: MKDirections?
    @State private var calculating = false
    @State private var routeMessage: String?
    init(tripID: UUID, initialDay: Int) {
        self.tripID = tripID; _dayIndex = State(initialValue: initialDay)
    }
    private var trip: Trip? { store.trips.first { $0.id == tripID } }
    private var allStops: [PlanItem] {
        guard let trip, trip.days.indices.contains(dayIndex) else { return [] }
        return trip.days[dayIndex].routeItems
    }
    private var stops: [PlanItem] {
        let excluded = Set(trip?.days[dayIndex].excludedRouteIDs ?? [])
        return allStops.filter { !excluded.contains($0.id) }
    }
    private var signature: String {
        "\(dayIndex)-\(driving)-" + stops.map { "\($0.id)-\($0.place!.latitude)-\($0.place!.longitude)" }.joined(separator: ",")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let trip {
                    Picker("哪一天", selection: $dayIndex) {
                        ForEach(trip.days.indices, id: \.self) { index in
                            Text("第 \(index + 1) 天 · \(trip.days[index].title)").tag(index)
                        }
                    }.pickerStyle(.menu).padding(.vertical, 6).accessibilityIdentifier("route-day")
                }
                HStack {
                    Button { showSelection = true } label: {
                        Label("选择地点 (\(stops.count))", systemImage: "checklist")
                    }.accessibilityIdentifier("select-route-stops")
                    Spacer()
                    Button("添加地点", systemImage: "plus") { showAddPlace = true }
                        .accessibilityIdentifier("add-route-place")
                }.font(.subheadline).padding(.horizontal).padding(.bottom, 10)
                if !stops.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(stops.enumerated()), id: \.element.id) { index, item in
                            if index == 0 || index == stops.count - 1 || stops.count <= 3 {
                                HStack(spacing: 8) {
                                    Text(stopRole(index)).font(.caption.bold())
                                        .foregroundStyle(index == 0 ? .green : index == stops.count - 1 ? .red : .secondary)
                                    Text(item.place?.name ?? item.title).font(.subheadline).lineLimit(1)
                                }
                            } else if index == 1 {
                                Text("途经 \(stops.count - 2) 个地点").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.bottom, 10)
                }
                if stops.isEmpty {
                    ContentUnavailableView("选择想串起来的地点", systemImage: "map", description: Text("点击上方“选择地点”勾选已有地点，或“添加地点”一次加入多个地点。"))
                } else {
                    routeMap.frame(height: 260)
                    List {
                        Section {
                            Picker("出行方式", selection: $driving) {
                                Text("步行").tag(false); Text("驾车").tag(true)
                            }.pickerStyle(.segmented)
                            Button { calculateRoutes() } label: {
                                HStack {
                                    Text(calculating ? "正在计算路线…" : "计算\(driving ? "驾车" : "步行")路线")
                                    Spacer()
                                    if calculating { ProgressView() } else { Image(systemName: "arrow.triangle.turn.up.right.diamond") }
                                }
                            }.disabled(stops.count < 2 || calculating).accessibilityIdentifier("calculate-route")
                            if routes.count == max(0, stops.count - 1), !routes.isEmpty {
                                Text("全程 \(routes.values.reduce(0) { $0 + $1.distance } / 1000, specifier: "%.1f") 公里 · 约 \(Int(ceil(routes.values.reduce(0) { $0 + $1.expectedTravelTime } / 60))) 分钟")
                                    .font(.subheadline.bold())
                            }
                            if let routeMessage { Text(routeMessage).font(.caption).foregroundStyle(.secondary) }
                        } footer: {
                            Text("虚线为地点顺序示意；计算后实线为道路路线。至少添加两个地点，拖动下方列表可调整顺序。")
                        }
                        Section("\(stops.count) 个地点") {
                            ForEach(Array(stops.enumerated()), id: \.element.id) { index, item in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .top) {
                                        Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white)
                                            .frame(width: 24, height: 24).background(item.category.color, in: Circle())
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.place?.name ?? item.title).font(.body.weight(.medium))
                                            Text(item.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    if index < stops.count - 1 {
                                        if let route = routes[index] {
                                            Text("至下一站：\(route.distance / 1000, specifier: "%.1f") 公里 · 约 \(Int(ceil(route.expectedTravelTime / 60))) 分钟")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Button("在苹果地图查看这一段", systemImage: "arrow.up.right.square") { openLeg(index) }
                                            .font(.caption)
                                    }
                                }.padding(.vertical, 3)
                                    .swipeActions {
                                        Button("移出路线", role: .destructive) { setIncluded(item.id, included: false) }
                                    }
                            }.onMove(perform: moveStops)
                        }
                        if stops.contains(where: { $0.place?.source == "OpenStreetMap" }) {
                            Link("地点数据 © OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!).font(.caption2)
                        }
                    }.listStyle(.insetGrouped)
                }
            }
            .navigationTitle("当天地图路线").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { EditButton().disabled(stops.count < 2) }
            }
            .sheet(isPresented: $showSelection) {
                NavigationStack {
                    List {
                        Section {
                            Button("全选") { setAllIncluded(true) }
                            Button("清空选择") { setAllIncluded(false) }
                        }
                        Section("勾选要经过的地点") {
                            ForEach(allStops) { item in
                                Button { setIncluded(item.id, included: !stops.contains { $0.id == item.id }) } label: {
                                    HStack {
                                        Image(systemName: stops.contains { $0.id == item.id } ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(.blue)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.place?.name ?? item.title).foregroundStyle(.primary)
                                            Text(item.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .accessibilityValue(stops.contains { $0.id == item.id } ? "已选" : "未选")
                                    .accessibilityIdentifier("route-select-\(item.place?.name ?? item.title)")
                            }
                        }
                    }
                    .navigationTitle("选择路线地点").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showSelection = false }.accessibilityIdentifier("route-selection-done") } }
                }
            }
            .sheet(isPresented: $showAddPlace) {
                PlacePicker(destination: [trip?.country, trip?.destination].compactMap { $0 }.joined(separator: " "), existing: stops.last?.place) { places in
                    guard var trip, !places.isEmpty else { return }
                    let item = PlanItem(title: places.map(\.name).joined(separator: " → "), category: .explore, places: places.map { PlanWaypoint(place: $0) })
                    trip.days[dayIndex].items.append(item)
                    store.update(trip)
                }
            }
            .onChange(of: signature) { _, _ in clearRoutes(); position = .automatic }
            .onDisappear { clearRoutes() }
        }
    }

    private var routeMap: some View {
        Map(position: $position) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, item in
                if let place = item.place {
                    Annotation(place.name, coordinate: place.coordinate) {
                        Text(index == 0 ? "起" : index == stops.count - 1 ? "终" : "\(index + 1)").font(.subheadline.bold()).foregroundStyle(.white)
                            .frame(width: 30, height: 30).background(index == 0 ? Color.green : index == stops.count - 1 ? Color.red : Color.blue, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            ForEach(0..<max(0, stops.count - 1), id: \.self) { index in
                if let route = routes[index] {
                    MapPolyline(route.polyline).stroke(.blue, lineWidth: 5)
                } else if let start = stops[index].place, let end = stops[index + 1].place {
                    MapPolyline(coordinates: [start.coordinate, end.coordinate])
                        .stroke(.blue.opacity(0.6), style: StrokeStyle(lineWidth: 3, dash: [6, 5]))
                }
            }
        }.mapControls { MapCompass(); MapScaleView() }
    }

    private func stopRole(_ index: Int) -> String {
        if index == 0 { return "起点" }
        return index == stops.count - 1 ? "终点" : "途经"
    }
    private func setIncluded(_ id: UUID, included: Bool) {
        guard var trip else { return }
        var excluded = Set(trip.days[dayIndex].excludedRouteIDs ?? [])
        if included { excluded.remove(id) } else { excluded.insert(id) }
        trip.days[dayIndex].excludedRouteIDs = Array(excluded)
        store.update(trip)
    }
    private func setAllIncluded(_ included: Bool) {
        guard var trip else { return }
        trip.days[dayIndex].excludedRouteIDs = included ? [] : allStops.map(\.id)
        store.update(trip)
    }
    private func moveStops(from source: IndexSet, to destination: Int) {
        guard var trip else { return }
        var ordered = stops; ordered.move(fromOffsets: source, toOffset: destination)
        trip.days[dayIndex].routeOrder = ordered.map(\.id) + allStops.filter { item in !ordered.contains { $0.id == item.id } }.map(\.id); store.update(trip)
    }
    private func clearRoutes() {
        routeTask?.cancel(); activeDirections?.cancel(); routes = [:]; calculating = false; routeMessage = nil
    }
    private func calculateRoutes() {
        clearRoutes()
        let points = stops.compactMap(\.place)
        guard points.count > 1 else { return }
        calculating = true
        let mode: MKDirectionsTransportType = driving ? .automobile : .walking
        routeTask = Task { @MainActor in
            var failed = 0
            for index in 0..<(points.count - 1) {
                guard !Task.isCancelled else { return }
                let request = MKDirections.Request()
                request.source = points[index].mapItem; request.destination = points[index + 1].mapItem
                request.transportType = mode
                let directions = MKDirections(request: request); activeDirections = directions
                do {
                    let response = try await directions.calculate()
                    guard !Task.isCancelled else { return }
                    if let route = response.routes.first { routes[index] = route } else { failed += 1 }
                } catch {
                    guard !Task.isCancelled else { return }
                    failed += 1
                }
            }
            calculating = false
            routeMessage = failed == 0 ? "道路路线已更新，时间为估算。" : "\(failed) 段暂时无法获取道路路线，保留虚线示意；可重试或在苹果地图查看。"
            position = .automatic
        }
    }
    private func openLeg(_ index: Int) {
        guard stops.indices.contains(index + 1), let start = stops[index].place, let end = stops[index + 1].place else { return }
        MKMapItem.openMaps(with: [start.mapItem, end.mapItem], launchOptions: [MKLaunchOptionsDirectionsModeKey: driving ? MKLaunchOptionsDirectionsModeDriving : MKLaunchOptionsDirectionsModeWalking])
    }
}

struct SearchArea {
    var name: String
    var country: String?
    var region: MKCoordinateRegion
}

enum PlaceSearchTerms {
    static func isStation(_ query: String) -> Bool {
        ["车站", "車站", "火车站", "駅", "站", "station"].contains { query.lowercased().contains($0) }
    }
    static func local(_ query: String, country: String?) -> String {
        guard country == "JP" else { return query }
        var text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases = [("Tokyo Station", "東京駅"), ("tokyo station", "東京駅"), ("东京", "東京"), ("银座", "銀座"), ("日本桥", "日本橋"), ("涩谷", "渋谷"), ("大阪", "大阪"), ("成田机场", "成田空港"), ("羽田机场", "羽田空港")]
        for (from, to) in aliases { text = text.replacingOccurrences(of: from, with: to) }
        text = text.applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) ?? text
        for suffix in ["火車站", "車站", "站"] { text = text.replacingOccurrences(of: suffix, with: "駅") }
        return text
    }
    static func stationBase(_ query: String, country: String?) -> String {
        var text = local(query, country: country)
        for suffix in [" Station", " station", "駅", "火车站", "车站", "站"] { text = text.replacingOccurrences(of: suffix, with: "") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func city(_ destination: String, country: String?) -> String {
        if country == "JP" {
            for (name, local) in [("东京", "Tokyo"), ("東京", "Tokyo"), ("京都", "Kyoto"), ("大阪", "Osaka"), ("札幌", "Sapporo"), ("福冈", "Fukuoka"), ("富士山", "Mount Fuji")] {
                if destination.contains(name) { return local }
            }
        }
        return destination.replacingOccurrences(of: "\\d+天.*$|旅行.*$|规划.*$|行程.*$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

actor OverseasPlaceSearch {
    static let shared = OverseasPlaceSearch()
    private var nextRequest = Date.distantPast
    private var cache: [String: [PlanPlace]] = [:]
    struct Response: Decodable {
        var features: [Feature]
        struct Feature: Decodable {
            var geometry: Geometry
            var properties: Properties
            struct Geometry: Decodable { var coordinates: [Double] }
            struct Properties: Decodable {
                var name: String?
                var country: String?
                var countrycode: String?
                var state: String?
                var city: String?
                var district: String?
                var street: String?
                var housenumber: String?
                var osm_value: String?
            }
        }
    }
    func search(_ query: String, country: String?, area: SearchArea? = nil, stationsOnly: Bool = false) async throws -> [PlanPlace] {
        var url = URLComponents(string: "https://photon.komoot.io/api/")!
        let text = stationsOnly ? PlaceSearchTerms.stationBase(query, country: country) : PlaceSearchTerms.local(query, country: country)
        var params = [URLQueryItem(name: "q", value: text), URLQueryItem(name: "limit", value: "12")]
        if stationsOnly { params.append(.init(name: "osm_tag", value: "railway:station")) }
        if let country { params.append(.init(name: "countrycode", value: country)) }
        if let area {
            let c = area.region.center, span = area.region.span
            params += [.init(name: "lat", value: String(c.latitude)), .init(name: "lon", value: String(c.longitude)),
                       .init(name: "bbox", value: "\(c.longitude - span.longitudeDelta / 2),\(c.latitude - span.latitudeDelta / 2),\(c.longitude + span.longitudeDelta / 2),\(c.latitude + span.latitudeDelta / 2)")]
        }
        url.queryItems = params
        let endpoint = url.url!
        if let cached = cache[endpoint.absoluteString] { return cached }
        let reserved = max(nextRequest, Date())
        nextRequest = reserved.addingTimeInterval(1)
        if reserved.timeIntervalSinceNow > 0 { try await Task.sleep(for: .seconds(reserved.timeIntervalSinceNow)) }
        try Task.checkCancellation()
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.setValue("RoamTravelPlanner/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(country == "JP" ? "ja" : "en", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        var places: [PlanPlace] = []
        for feature in decoded.features {
            let p = feature.properties, c = feature.geometry.coordinates
            guard c.count >= 2, let name = p.name, !name.isEmpty,
                  country == nil || p.countrycode?.uppercased() == country,
                  !["footway", "steps", "path"].contains(p.osm_value ?? "") else { continue }
            let countryName = p.countrycode.flatMap { Locale(identifier: "zh_CN").localizedString(forRegionCode: $0) } ?? p.country
            var parts: [String] = []
            for part in [countryName, p.state, p.city, p.district, p.street, p.housenumber].compactMap({ $0 }) {
                if !parts.contains(part) { parts.append(part) }
            }
            let displayName = stationsOnly && country == "JP" && !name.hasSuffix("駅") ? name + "駅" : name
            let place = PlanPlace(name: displayName, address: parts.joined(separator: " · "), latitude: c[1], longitude: c[0], source: "OpenStreetMap")
            if !places.contains(where: { $0.name == displayName && CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: CLLocation(latitude: c[1], longitude: c[0])) < 250 }) { places.append(place) }
        }
        if cache.count > 100 { cache.removeAll() }
        if !places.isEmpty { cache[endpoint.absoluteString] = places }
        return places
    }
}

@MainActor
final class PlaceSearchModel: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published var places: [PlanPlace] = []
    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var loading = false
    @Published var resolvingArea = false
    @Published var message: String?
    @Published var area: SearchArea?
    @Published var scopeName = ""
    @Published var overseas = false
    private var generation = UUID()
    private var scopeGeneration = UUID()
    private var completer: MKLocalSearchCompleter?
    private var activeSearch: MKLocalSearch?
    private static var areas: [String: SearchArea] = [:]

    static func countryCode(for destination: String) -> String? {
        let text = destination.lowercased()
        for code in Locale.Region.isoRegions.map(\.identifier) {
            for locale in [Locale(identifier: "zh_CN"), Locale(identifier: "en_US")] {
                if let name = locale.localizedString(forRegionCode: code), text.contains(name.lowercased()) { return code }
            }
        }
        return nil
    }
    func configure(_ destination: String) async {
        invalidate(); area = nil; scopeName = destination; resolvingArea = true
        scopeGeneration = UUID(); let token = scopeGeneration
        let country = Self.countryCode(for: destination)
        let city = PlaceSearchTerms.city(destination, country: country)
        overseas = country != nil && country != "CN"
        if let cached = Self.areas[destination] { area = cached; resolvingArea = false; return }
        do {
            let coordinate: CLLocationCoordinate2D
            if overseas {
                let places = try await OverseasPlaceSearch.shared.search(city, country: country)
                guard let first = places.first else { throw URLError(.cannotFindHost) }
                coordinate = first.coordinate
            } else {
                guard let request = MKGeocodingRequest(addressString: city) else { throw URLError(.badURL) }
                let result = try await request.mapItems
                guard let first = result.first else { throw URLError(.cannotFindHost) }
                coordinate = first.location.coordinate
            }
            guard scopeGeneration == token, !Task.isCancelled else { return }
            let resolved = SearchArea(name: destination, country: country, region: MKCoordinateRegion(center: coordinate, latitudinalMeters: 120_000, longitudinalMeters: 120_000))
            area = resolved; Self.areas[destination] = resolved; resolvingArea = false
        } catch {
            guard scopeGeneration == token, !Task.isCancelled else { return }
            resolvingArea = false; message = "无法定位搜索城市，请点上方城市，输入国家和城市后重试。"
        }
    }
    func invalidate() {
        generation = UUID(); completer?.cancel(); completer = nil; activeSearch?.cancel()
        places = []; completions = []; loading = false; message = nil
    }
    func suggest(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let area else { return }
        let token = generation; loading = true
        if overseas { await search(text); return }
        let next = MKLocalSearchCompleter(); next.region = area.region; next.regionPriority = .default
        next.resultTypes = [.address, .pointOfInterest]; next.delegate = self; completer = next
        next.queryFragment = text
    }
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard completer === self.completer else { return }
        completions = completer.results; loading = false
        if completions.isEmpty { message = "没有找到联想地点，可点搜索或修改搜索城市。" }
    }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        guard completer === self.completer else { return }
        loading = false; message = "地点联想暂时不可用，可以点搜索重试。"
    }
    func search(_ text: String, completion: MKLocalSearchCompletion? = nil) async {
        invalidate()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        guard let area else { message = "请先确认搜索城市，再搜索地点。"; return }
        loading = true; let token = generation
        let station = PlaceSearchTerms.isStation(query)
        let request = completion.map { MKLocalSearch.Request(completion: $0) } ?? MKLocalSearch.Request()
        if completion == nil { request.naturalLanguageQuery = PlaceSearchTerms.local(query, country: area.country) }
        request.region = area.region; request.regionPriority = .default
        request.resultTypes = [.address, .pointOfInterest]
        let search = MKLocalSearch(request: request); activeSearch = search
        async let fallback: [PlanPlace]? = overseas ? try? await OverseasPlaceSearch.shared.search(query, country: area.country, area: area, stationsOnly: station) : nil
        var apple: [PlanPlace] = []
        var appleSucceeded = false
        do {
            let response = try await search.start()
            appleSucceeded = true
            apple = response.mapItems.map { PlanPlace(mapItem: $0) }.filter { place in
                CLLocation(latitude: area.region.center.latitude, longitude: area.region.center.longitude).distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude)) < 90_000
            }
            guard token == generation, !Task.isCancelled else { return }
            places = apple
        } catch { }
        let supplemental = await fallback
        guard token == generation, !Task.isCancelled else { return }
        let merged = station ? (supplemental ?? []) + apple : apple + (supplemental ?? [])
        var unique: [PlanPlace] = []
        for place in merged {
            let base = PlaceSearchTerms.stationBase(place.name, country: area.country)
            if !unique.contains(where: {
                PlaceSearchTerms.stationBase($0.name, country: area.country) == base &&
                CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude)) < 250
            }) { unique.append(place) }
        }
        places = Array(unique.prefix(20)); loading = false
        if places.isEmpty {
            message = appleSucceeded || supplemental != nil ? "没有找到这个地点。可输入更完整的地址，或切换到地图选点。" : "网络暂时不可用，请重试；也可以在地图上手动选点。"
        }
    }

}

struct NativePlaceSearchBar: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var onSearch: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UISearchBar {
        let bar = UISearchBar()
        bar.searchBarStyle = .minimal
        bar.placeholder = "输入景点、餐厅、酒店名称"
        bar.delegate = context.coordinator
        bar.searchTextField.accessibilityIdentifier = "place-query"
        return bar
    }
    func updateUIView(_ bar: UISearchBar, context: Context) {
        context.coordinator.parent = self
        if bar.text != text { bar.text = text }
        if !focused && bar.searchTextField.isFirstResponder { bar.resignFirstResponder() }
    }
    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: NativePlaceSearchBar
        init(_ parent: NativePlaceSearchBar) { self.parent = parent }
        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { parent.text = searchText }
        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) { parent.focused = true }
        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) { parent.focused = false }
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { parent.onSearch(); searchBar.resignFirstResponder() }
    }
}

struct SearchCityEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var city: String
    @State private var country: String
    @State private var selectingCountry = false
    let onSave: (String) -> Void
    static let locale = Locale(identifier: "zh_CN")
    static let common = ["CN", "JP", "KR", "TH", "SG", "MY", "US", "GB", "FR", "AU"]
    static let cities = ["CN": ["广州", "上海", "北京", "成都", "大理"], "JP": ["东京", "大阪", "京都", "札幌", "福冈"], "KR": ["首尔", "釜山"], "TH": ["曼谷", "清迈", "普吉岛"], "SG": ["新加坡"], "US": ["纽约", "洛杉矶", "旧金山"], "GB": ["伦敦"], "FR": ["巴黎"], "AU": ["悉尼", "墨尔本"]]
    static func name(_ code: String) -> String { locale.localizedString(forRegionCode: code) ?? code }
    init(initial: String, onSave: @escaping (String) -> Void) {
        let code = PlaceSearchModel.countryCode(for: initial) ?? "CN"
        _country = State(initialValue: code)
        _city = State(initialValue: initial.replacingOccurrences(of: Self.name(code), with: "").trimmingCharacters(in: .whitespacesAndNewlines))
        self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("1 · 选择国家 / 地区") {
                    Button { selectingCountry = true } label: {
                        HStack { Text("国家 / 地区"); Spacer(); Text(Self.name(country)).foregroundStyle(.blue); Image(systemName: "chevron.right").font(.caption) }
                    }.accessibilityIdentifier("choose-country")
                    .navigationDestination(isPresented: $selectingCountry) {
                        List {
                            Section("常用") {
                                ForEach(Self.common, id: \.self) { code in countryRow(code) }
                            }
                            Section("全部国家 / 地区") {
                                ForEach(Locale.Region.isoRegions.map(\.identifier).filter { !Self.common.contains($0) }.sorted { Self.name($0) < Self.name($1) }, id: \.self) { code in countryRow(code) }
                            }
                        }.navigationTitle("选择国家 / 地区")
                    }
                }
                Section {
                    TextField("输入城市名称，例如东京", text: $city).accessibilityIdentifier("search-city-input")
                    ForEach(Self.cities[country] ?? [], id: \.self) { name in
                        Button { city = name } label: {
                            HStack { Text(name); Spacer(); if city == name { Image(systemName: "checkmark") } }
                        }.accessibilityIdentifier("city-" + name)
                    }
                } header: { Text("2 · 选择或输入城市") } footer: { Text("只填城市，不用再输入国家。下一步再搜索餐厅、景点和酒店。") }
                Section {
                    Button("在" + (city.isEmpty ? "所选城市" : city) + "搜索地点") {
                        onSave(Self.name(country) + " " + city.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss()
                    }.disabled(city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("confirm-search-city")
                }
            }
            .navigationTitle("先选要去哪里").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
    private func countryRow(_ code: String) -> some View {
        Button { if country != code { country = code; city = "" }; selectingCountry = false } label: {
            HStack { Text(Self.name(code)); Spacer(); if country == code { Image(systemName: "checkmark") } }
        }.accessibilityIdentifier("country-" + code)
    }
}

struct TrashView: View {
    @EnvironmentObject private var store: TravelStore
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: DeletedTrip?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("删除的攻略保留 30 天，到期后自动彻底删除。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if store.deletedTrips.isEmpty {
                    ContentUnavailableView("垃圾桶为空", systemImage: "trash", description: Text("删除的攻略会暂存在这里。"))
                } else {
                    ForEach(store.deletedTrips) { entry in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(entry.trip.destination).font(.headline)
                            Text("\(entry.trip.dateRange) · \(entry.trip.days.count) 天 · \(entry.trip.itemCount) 项安排")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("剩余 \(entry.remainingDays) 天后彻底删除")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("恢复", systemImage: "arrow.uturn.backward") { store.restoreTrip(entry.id) }
                                    .buttonStyle(.bordered).accessibilityIdentifier("restore-trip-" + entry.id.uuidString)
                                Spacer()
                                Button("彻底删除", systemImage: "trash", role: .destructive) { deleting = entry }
                                    .buttonStyle(.borderless)
                            }
                        }.padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle("垃圾桶").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .onAppear { store.purgeExpiredTrash() }
            .confirmationDialog("彻底删除这份攻略？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("彻底删除", role: .destructive) { if let entry = deleting { store.permanentlyDeleteTrip(entry.id) }; deleting = nil }
            } message: { Text("彻底删除后无法恢复。") }
        }
    }
}

// Reject horizontal motion before recognition so UIScrollView owns every sideways swipe.
private struct UpwardCardPan: UIGestureRecognizerRepresentable {
    var changed: (CGSize) -> Void
    var ended: (CGSize, Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }
    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let point = recognizer.translation(in: recognizer.view)
        let translation = CGSize(width: point.x, height: point.y)
        switch recognizer.state {
        case .began, .changed: changed(translation)
        case .ended: ended(translation, false)
        case .cancelled, .failed: ended(translation, true)
        default: break
        }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return velocity.y < 0 && -velocity.y > abs(velocity.x) * 1.7
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}

private struct DayOrderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedID: UUID?
    @Binding var hoveredID: UUID?
    let move: (UUID, UUID) -> Void
    func dropEntered(info: DropInfo) {
        guard let source = draggedID, source != targetID, hoveredID != targetID else { return }
        hoveredID = targetID
        move(source, targetID)
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard let source = draggedID else { return false }
        if source != targetID && hoveredID != targetID { move(source, targetID) }
        hoveredID = nil
        draggedID = nil
        return true
    }
}
