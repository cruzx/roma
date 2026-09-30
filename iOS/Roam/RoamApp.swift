import SwiftUI

@main
struct RoamApp: App {
    @StateObject private var store: TravelStore
    @Environment(\.scenePhase) private var scenePhase
    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let file = testing ? FileManager.default.temporaryDirectory.appendingPathComponent("roam-ui-tests.json") : nil
        _store = StateObject(wrappedValue: TravelStore(file: file, reset: ProcessInfo.processInfo.arguments.contains("--reset")))
    }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.cloud?.synchronize() } }
                }
                .tint(.blue)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .alert("保存遇到问题", isPresented: Binding(get: { store.saveError != nil }, set: { if !$0 { store.saveError = nil } })) {
                    Button("重试") { store.saveError = nil; store.save() }
                } message: { Text(store.saveError ?? "") }
        }
    }
}
