import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        Task { @MainActor in
            var texts: [String] = []
            for item in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
                if let title = item.attributedTitle?.string, !title.isEmpty { texts.append(title) }
                if let text = item.attributedContentText?.string, !text.isEmpty { texts.append(text) }
                for provider in item.attachments ?? [] {
                    for type in [UTType.url.identifier, UTType.plainText.identifier] where provider.hasItemConformingToTypeIdentifier(type) {
                        if let value = try? await provider.loadItem(forTypeIdentifier: type, options: nil) {
                            if let url = value as? URL, ["https", "http"].contains(url.scheme?.lowercased() ?? "") { texts.append(url.absoluteString) }
                            else if let text = value as? String { texts.append(text) }
                        }
                    }
                }
            }
            var seen = Set<String>()
            let text = texts.filter { seen.insert($0).inserted }.joined(separator: "\n\n")
            let host = UIHostingController(rootView: ShareCaptureView(text: text) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            } cancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
            }.environment(\.locale, AppLocalization.locale))
            addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor), host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
            host.didMove(toParent: self)
        }
    }
}

struct ShareCaptureView: View {
    @State private var text: String
    @State private var title: String
    @State private var tripID: UUID?
    @State private var dayID: UUID?
    @State private var error: String?
    @State private var saved = false
    private let destinations = ShareBridge.destinations()
    let done: () -> Void
    let cancel: () -> Void
    init(text: String, done: @escaping () -> Void, cancel: @escaping () -> Void) {
        _text = State(initialValue: text)
        _title = State(initialValue: text.split(separator: "\n").first.map { String($0.prefix(60)) } ?? AppLocalization.text("分享收藏"))
        self.done = done; self.cancel = cancel
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("内容") {
                    TextField("备忘标题", text: $title)
                    TextEditor(text: $text).frame(minHeight: 150)
                }
                Section("保存位置") {
                    Picker("旅行", selection: $tripID) {
                        Text("稍后归档").tag(nil as UUID?)
                        ForEach(destinations) { Text($0.title).tag(Optional($0.id)) }
                    }.onChange(of: tripID) { _, id in dayID = destinations.first { $0.id == id }?.days.first?.id }
                    if let trip = destinations.first(where: { $0.id == tripID }) {
                        Picker("日期", selection: $dayID) { ForEach(trip.days) { Text($0.title).tag(Optional($0.id)) } }
                    }
                    Text("下次打开漫游时，会放入所选日期的备忘；稍后归档的内容可在首页设置里的「分享收集箱」找到。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("存到漫游备忘").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: cancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try ShareBridge.save(CollectedNote(title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppLocalization.text("分享收藏") : title, text: text, tripID: tripID, dayID: dayID))
                            saved = true; done()
                        } catch { self.error = AppLocalization.text("暂时无法保存，请先打开一次漫游后重试。内容超过 10 万字时请分段收藏。") }
                    }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 100_000 || saved || (tripID != nil && dayID == nil))
                }
            }
        }
    }
}
