import SwiftUI

struct LanguageSettingsView: View {
    @EnvironmentObject private var language: AppLanguageStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    languageRow(.system, title: AppLocalization.text("Follow System"))
                    languageRow(.chinese, title: "简体中文")
                    languageRow(.english, title: "English")
                } header: {
                    Text("App language")
                } footer: {
                    Text("语言设置会立即生效，并保留你的旅行和手账内容。")
                }
            }
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("language-settings-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func languageRow(_ value: AppLanguage, title: String) -> some View {
        Button {
            language.select(value)
        } label: {
            HStack {
                Text(verbatim: title).foregroundStyle(.primary)
                Spacer()
                if language.selection == value {
                    DoodleIcon(systemName: "checkmark", size: 20).foregroundStyle(.blue)
                }
            }.contentShape(Rectangle())
        }
        .accessibilityIdentifier("app-language-\(value.rawValue)")
        .accessibilityAddTraits(language.selection == value ? .isSelected : [])
    }
}
