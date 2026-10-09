import SwiftUI
import UIKit

struct StickerBorderColorEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var color: String
    @State private var saveError: String?
    let item: StickerCanvasItem
    let image: UIImage?
    let onSave: (String) -> String?

    private let presets: [(hex: String, name: String)] = [
        ("#FFFFFF", "白色"), ("#1D1D1F", "黑色"), ("#BC534B", "砖红色"), ("#AD823D", "赭黄色"),
        ("#63835E", "绿色"), ("#3E637A", "蓝色"), ("#8B6BB1", "紫色"), ("#D77DA7", "粉色")
    ]

    init(item: StickerCanvasItem, image: UIImage?, onSave: @escaping (String) -> String?) {
        self.item = item
        self.image = image
        self.onSave = onSave
        _color = State(initialValue: item.borderColorHex)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    preview
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(presets, id: \.hex) { preset in
                            Button {
                                guard color != preset.hex else { return }
                                color = preset.hex
                                AppHaptics.selection()
                            } label: {
                                Circle().fill(stickerTextColor(preset.hex))
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(.gray.opacity(0.4), lineWidth: 1))
                                    .padding(4)
                                    .overlay(Circle().stroke(color == preset.hex ? Color.primary : .clear, lineWidth: 2))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(AppLocalization.text(preset.name))
                            .accessibilityAddTraits(color == preset.hex ? .isSelected : [])
                            .accessibilityIdentifier("sticker-border-color-\(preset.hex.dropFirst())")
                        }
                    }
                    ColorPicker("自定颜色", selection: Binding(
                        get: { stickerTextColor(color) },
                        set: { color = Self.hex(from: $0) }
                    ), supportsOpacity: false)
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("sticker-border-custom-color")
                }
                .padding(20)
            }
            .navigationTitle("描边颜色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { AppHaptics.tap(); dismiss() }
                        .accessibilityIdentifier("sticker-cancel-border-color")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveError = onSave(color)
                        if saveError == nil { AppHaptics.success(); dismiss() }
                        else { AppHaptics.error() }
                    }
                    .accessibilityIdentifier("sticker-save-border-color")
                }
            }
            .alert("描边未能保存", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("好") { saveError = nil }
            } message: { Text(saveError ?? "") }
        }
        .tint(.black)
        .presentationDetents([.height(440), .large])
        .presentationDragIndicator(.visible)
    }

    private var preview: some View {
        let aspect = max(0.1, item.aspectRatio)
        let size = aspect >= 1 ? CGSize(width: 130, height: 130 / aspect) : CGSize(width: 130 * aspect, height: 130)
        let dashed = item.borderStyle == .dashed
        return ZStack {
            if let image {
                ZStack {
                    StickerSubjectOutline(contours: item.contours)
                        .stroke(stickerTextColor(color), style: StrokeStyle(lineWidth: 8, lineCap: dashed ? .butt : .round,
                                                                          lineJoin: .round, dash: dashed ? [8, 6] : []))
                    Image(uiImage: image).resizable().scaledToFit()
                }
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(stickerTextColor(color), style: StrokeStyle(lineWidth: 4, dash: dashed ? [8, 6] : []))
                    .frame(width: 100, height: 100)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 155)
        .background(Color(red: 0.96, green: 0.945, blue: 0.91), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityHidden(true)
    }

    private static func hex(from color: Color) -> String {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let rgb = UIColor(color).cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let components = rgb.components, components.count >= 3 else { return "#FFFFFF" }
        let channels = components.prefix(3).map { Int((min(1, max(0, $0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }
}
