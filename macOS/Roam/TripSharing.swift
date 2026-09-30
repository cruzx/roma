import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    static let roamTrip = UTType(exportedAs: "com.xiangchengjin.roam.trip", conformingTo: .data)
}

struct TripPackage: Codable, Transferable {
    var version = 1
    var trip: Trip
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .roamTrip) { package in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RoamShares/" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let safeName = package.trip.destination.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
            let file = folder.appendingPathComponent(String(safeName.prefix(60)) + ".roamtrip")
            try JSONEncoder().encode(package).write(to: file, options: .atomic)
            return SentTransferredFile(file)
        }
    }
    static func read(_ url: URL) throws -> TripPackage {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 25_000_000 else { throw PackageError.invalid }
        let data = try Data(contentsOf: url)
        guard data.count <= 25_000_000 else { throw PackageError.invalid }
        let package = try JSONDecoder().decode(TripPackage.self, from: data)
        guard package.version == 1, !package.trip.destination.isEmpty,
              (1...60).contains(package.trip.days.count), package.trip.itemCount <= 5000,
              package.trip.startDate.timeIntervalSince1970.isFinite,
              Set(package.trip.days.map(\.id)).count == package.trip.days.count else { throw PackageError.invalid }
        for day in package.trip.days {
            guard Set(day.items.map(\.id)).count == day.items.count else { throw PackageError.invalid }
            let points = day.items.flatMap(\.mapPlaces)
            guard Set(points.map(\.id)).count == points.count,
                  points.allSatisfy({ (-90...90).contains($0.place.latitude) && (-180...180).contains($0.place.longitude) }) else { throw PackageError.invalid }
        }
        return package
    }
    func importedCopy() -> Trip {
        var copy = trip
        copy.id = UUID()
        return copy
    }
    enum PackageError: Error { case invalid }
}

struct IncomingTrip: Identifiable {
    let id = UUID()
    let package: TripPackage
}

struct TripImportModifier: ViewModifier {
    @EnvironmentObject private var store: TravelStore
    @State private var incoming: IncomingTrip?
    @State private var error = false
    @State private var showFile = false
    func body(content: Content) -> some View {
        content
            .onOpenURL { load($0) }
            .onReceive(NotificationCenter.default.publisher(for: .importRoamTrip)) { _ in showFile = true }
            .fileImporter(isPresented: $showFile, allowedContentTypes: [.roamTrip]) { result in
                if case .success(let url) = result { load(url) }
            }
            .sheet(item: $incoming) { value in
                NavigationStack {
                    Form {
                        Section("收到的旅行") {
                            Text(value.package.trip.destination).font(.title2.bold())
                            Text(value.package.trip.dateRange)
                            Text("\(value.package.trip.days.count) 天 · \(value.package.trip.itemCount) 项安排")
                        }
                        Section {
                            Text("包含行程、地点、交通备注和自选封面。导入为一份独立旅行，不会覆盖已有行程；保存后同步到你自己的 iCloud。")
                            Button("导入到我的旅行") {
                                store.trips.insert(value.package.importedCopy(), at: 0)
                                incoming = nil
                            }.accessibilityIdentifier("confirm-trip-import")
                        }
                    }
                    .navigationTitle("导入旅行").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { incoming = nil } } }
                }
            }
            .alert("无法导入旅行", isPresented: $error) {
                Button("好", role: .cancel) {}
            } message: { Text("文件损坏、过大或来自更新版本。请确认选择的是漫游导出的 .roamtrip 文件。") }
    }
    private func load(_ url: URL) {
        Task {
            do {
                let package = try await Task.detached { try TripPackage.read(url) }.value
                incoming = IncomingTrip(package: package)
            } catch { self.error = true }
        }
    }
}

extension Notification.Name {
    static let importRoamTrip = Notification.Name("importRoamTrip")
}
