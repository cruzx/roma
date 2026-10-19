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
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            RootView().modifier(TripImportModifier()).id(language.identifier).environmentObject(store)
                .background(MacWindowSetup())
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { language.refresh(); store.collectPendingShares(); store.purgeExpiredTrash(); Task { await store.cloud?.synchronize() } }
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
        }, resume: {
            store.cloud?.start()
        })
    }
}

#if targetEnvironment(macCatalyst)
import UIKit
struct MacWindowSetup: UIViewRepresentable {
    func makeUIView(context: Context) -> WindowView { WindowView() }
    func updateUIView(_ view: WindowView, context: Context) { view.configure() }
    final class WindowView: UIView {
        override func didMoveToWindow() { super.didMoveToWindow(); configure() }
        func configure() {
            guard let scene = window?.windowScene else { return }
            scene.sizeRestrictions?.minimumSize = CGSize(width: 860, height: 640)
            scene.title = AppLocalization.text("漫游")
        }
    }
}
#else
struct MacWindowSetup: View { var body: some View { EmptyView() } }
#endif

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
    init() {
        DoodleIcon.configureNativeControls()
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting") ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
        let file = testing ? FileManager.default.temporaryDirectory.appendingPathComponent("roam-ui-tests.json") : nil
        store = TravelStore(file: file, reset: ProcessInfo.processInfo.arguments.contains("--reset"))
    }
}
