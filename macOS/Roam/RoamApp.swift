import SwiftUI

@main
struct RoamApp: App {
    @StateObject private var language = AppLanguageStore()
    @StateObject private var store: TravelStore
    @Environment(\.scenePhase) private var scenePhase
    init() {
        DoodleIcon.configureNativeControls()
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting") ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
        let file = testing ? FileManager.default.temporaryDirectory.appendingPathComponent("roam-ui-tests.json") : nil
        _store = StateObject(wrappedValue: TravelStore(file: file, reset: ProcessInfo.processInfo.arguments.contains("--reset")))
    }
    var body: some Scene {
        WindowGroup {
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
