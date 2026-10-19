import SwiftUI

@main
struct RoamApp: App {
    @StateObject private var workspace = AccountWorkspaceState.shared
    var body: some Scene {
        WindowGroup {
            RoamWorkspaceView().id(workspace.revision)
                .disabled(workspace.switching)
                .overlay { if workspace.switching { ProgressView("正在准备账号资料…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        }
    }
}

struct RoamWorkspaceView: View {
    @ObservedObject private var account = AccountService.shared
    @ObservedObject private var membership = MembershipStore.shared
    @StateObject private var language = AppLanguageStore()
    @StateObject private var models = WorkspaceModels.current
    private var store: TravelStore { models.store }
    private var backgrounds: HomeBackgroundStore { models.backgrounds }
    private var stickers: StickerBoardStore { models.stickers }
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
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
        .task {
            while !Task.isCancelled {
                await reconcileWorkspace()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .sheet(isPresented: $membership.showPurchaseIntentAccount) {
            CloudSyncView().environmentObject(store).environmentObject(language)
                .environment(\.locale, language.locale)
        }
        .onChange(of: account.session?.user.id) { _, _ in Task { await reconcileWorkspace() } }
        .onChange(of: membership.active) { _, active in if active { Task { await reconcileWorkspace() } } }
    }
    private func reconcileWorkspace() async {
        await AccountWorkspaceState.shared.reconcile(store: store, expectedRevision: models.revision, stop: {
            await store.cloud?.stopAndDrain()
            await stickers.cloud?.stopAndDrain()
            await backgrounds.stopAndDrain()
        }, resume: {
            store.cloud?.start()
            stickers.cloud?.start()
            backgrounds.start()
        })
    }
}

@MainActor final class WorkspaceModels: ObservableObject {
    private static var cached: WorkspaceModels?
    static var current: WorkspaceModels {
        if let cached, cached.revision == AccountWorkspaceState.shared.revision { return cached }
        let model = WorkspaceModels()
        cached = model
        return model
    }
    let revision = AccountWorkspaceState.shared.revision
    let store: TravelStore
    let backgrounds: HomeBackgroundStore
    let stickers: StickerBoardStore
    init() {
        DoodleIcon.configureNativeControls()
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting") ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
        let file = testing ? FileManager.default.temporaryDirectory.appendingPathComponent("roam-ui-tests.json") : nil
        backgrounds = HomeBackgroundStore(testing: testing, reset: ProcessInfo.processInfo.arguments.contains("--reset"))
        let stickerBoard = StickerBoardStore(testing: testing, reset: testing && ProcessInfo.processInfo.arguments.contains("--reset"))
        #if DEBUG
        if testing && ProcessInfo.processInfo.arguments.contains("--sticker-fixture") {
            StickerUITestFixture.seed(stickerBoard, populated: ProcessInfo.processInfo.arguments.contains("--populated-sticker-fixture"))
        }
        #endif
        stickers = stickerBoard
        let travelStore = TravelStore(file: file, reset: ProcessInfo.processInfo.arguments.contains("--reset"))
        if testing && ProcessInfo.processInfo.arguments.contains("--today-trip") {
            travelStore.trips[0].startDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
            travelStore.trips[0].status = .planning
        }
        store = travelStore
    }
}
