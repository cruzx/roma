import SwiftUI

@main
struct RoamApp: App {
    @StateObject private var store: TravelStore
    @StateObject private var backgrounds: HomeBackgroundStore
    @Environment(\.scenePhase) private var scenePhase
    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting") ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
        let file = testing ? FileManager.default.temporaryDirectory.appendingPathComponent("roam-ui-tests.json") : nil
        _backgrounds = StateObject(wrappedValue: HomeBackgroundStore(testing: testing, reset: ProcessInfo.processInfo.arguments.contains("--reset")))
        let travelStore = TravelStore(file: file, reset: ProcessInfo.processInfo.arguments.contains("--reset"))
        if testing && ProcessInfo.processInfo.arguments.contains("--today-trip") {
            travelStore.trips[0].startDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
            travelStore.trips[0].status = .planning
        }
        _store = StateObject(wrappedValue: travelStore)
    }
    var body: some Scene {
        WindowGroup {
            RootView().modifier(TripImportModifier()).environmentObject(store).environmentObject(backgrounds)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.purgeExpiredTrash(); Task { await backgrounds.synchronize(); await store.cloud?.synchronize() } }
                }
                .tint(.blue)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .alert("保存遇到问题", isPresented: Binding(get: { store.saveError != nil }, set: { if !$0 { store.saveError = nil } })) {
                    Button("重试") { store.saveError = nil; store.save() }
                } message: { Text(store.saveError ?? "") }
        }
    }
}
