import SwiftUI

@main
struct RoamApp: App {
    @StateObject private var language = AppLanguageStore()
    @StateObject private var store: TravelStore
    @StateObject private var backgrounds: HomeBackgroundStore
    @StateObject private var stickers: StickerBoardStore
    @Environment(\.scenePhase) private var scenePhase
    init() {
        DoodleIcon.configureNativeControls()
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting") ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
        let file = testing ? FileManager.default.temporaryDirectory.appendingPathComponent("roam-ui-tests.json") : nil
        _backgrounds = StateObject(wrappedValue: HomeBackgroundStore(testing: testing, reset: ProcessInfo.processInfo.arguments.contains("--reset")))
        let stickerBoard = StickerBoardStore(testing: testing, reset: testing && ProcessInfo.processInfo.arguments.contains("--reset"))
        #if DEBUG
        if testing && ProcessInfo.processInfo.arguments.contains("--sticker-fixture") {
            StickerUITestFixture.seed(stickerBoard, populated: ProcessInfo.processInfo.arguments.contains("--populated-sticker-fixture"))
        }
        #endif
        _stickers = StateObject(wrappedValue: stickerBoard)
        let travelStore = TravelStore(file: file, reset: ProcessInfo.processInfo.arguments.contains("--reset"))
        if testing && ProcessInfo.processInfo.arguments.contains("--today-trip") {
            travelStore.trips[0].startDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
            travelStore.trips[0].status = .planning
        }
        _store = StateObject(wrappedValue: travelStore)
    }
    var body: some Scene {
        WindowGroup {
            RootView().modifier(TripImportModifier()).id(language.identifier).environmentObject(store).environmentObject(backgrounds).environmentObject(stickers)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        language.refresh()
                        store.collectPendingShares()
                        store.purgeExpiredTrash()
                        Task { await backgrounds.synchronize(); await store.cloud?.synchronize() }
                        Task { await stickers.cloud?.synchronize() }
                    }
                }
                .tint(.blue)
                .environmentObject(language)
                .environment(\.locale, language.locale)
                .sheet(isPresented: $language.isSettingsPresented) {
                    LanguageSettingsView().environmentObject(language).environment(\.locale, language.locale)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in language.refresh() }
                .alert("保存遇到问题", isPresented: Binding(get: { store.saveError != nil }, set: { if !$0 { store.saveError = nil } })) {
                    Button("重试") { store.saveError = nil; store.save() }
                } message: { Text(store.saveError ?? "") }
        }
    }
}
