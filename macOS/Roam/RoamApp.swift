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
            RootView().modifier(TripImportModifier()).environmentObject(store)
                .background(MacWindowSetup())
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
            scene.title = "漫游"
        }
    }
}
#else
struct MacWindowSetup: View { var body: some View { EmptyView() } }
#endif
