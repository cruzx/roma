import SwiftUI
import UIKit

struct PlacePhotoThumbnail: View {
    let photo: PlacePhoto
    var size: CGFloat = 76
    var identifier: String? = nil
    @State private var isPresented = false

    var body: some View {
        Button { AppHaptics.tap(); isPresented = true } label: {
            Image(photo.thumbnail)
                .resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottomTrailing) {
                    DoodleIcon(systemName: "arrow.up.left.and.arrow.down.right", size: 9)
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.4), in: Circle())
                        .padding(5)
                }
                .overlay(alignment: .topLeading) {
                    if photo.note != nil {
                        Text("周边实景").font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule()).padding(4)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.format("查看%@的照片", photo.title))
        .accessibilityHint("打开大图，可以放大查看")
        .accessibilityIdentifier(identifier ?? "place-photo-\(photo.id)")
        #if targetEnvironment(macCatalyst)
        .sheet(isPresented: $isPresented) { PlacePhotoViewer(photo: photo) }
        #else
        .fullScreenCover(isPresented: $isPresented) { PlacePhotoViewer(photo: photo) }
        #endif
    }
}

private struct PlacePhotoViewer: View {
    let photo: PlacePhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZoomablePlacePhoto(asset: photo.asset, title: photo.title)
                .background(.black)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let note = photo.note {
                            Text(note).foregroundStyle(.white.opacity(0.85))
                        }
                        Text(photo.author)
                            .foregroundStyle(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 16) {
                            Link(photo.license, destination: photo.licenseURL)
                            Link("图片来源", destination: photo.sourceURL)
                        }
                        Text("图片经缩放、压缩，显示时可能裁切；其许可独立于应用代码。")
                            .foregroundStyle(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption2)
                    .tint(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.black)
                }
                .navigationTitle(photo.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbarBackground(.black, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { AppHaptics.tap(); dismiss() } label: {
                            DoodleIcon(systemName: "xmark")
                        }
                        .accessibilityLabel("关闭照片")
                        .accessibilityIdentifier("close-sight-photo")
                        .keyboardShortcut(.cancelAction)
                    }
                }
                .tint(.white)
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("sight-photo-viewer")
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 600, minHeight: 560)
        #endif
    }
}

private struct ZoomablePlacePhoto: UIViewRepresentable {
    let asset: String
    let title: String

    func makeUIView(context: Context) -> PlacePhotoScrollView {
        let view = PlacePhotoScrollView()
        view.setImage(asset: asset, title: title)
        return view
    }

    func updateUIView(_ view: PlacePhotoScrollView, context: Context) {
        view.setImage(asset: asset, title: title)
    }
}

private final class PlacePhotoScrollView: UIScrollView, UIScrollViewDelegate {
    private let photoView = UIImageView()
    private var assetName: String?
    private var fittedBounds: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .black
        photoView.contentMode = .scaleAspectFit
        photoView.isAccessibilityElement = true
        photoView.accessibilityIdentifier = "sight-photo-image"
        photoView.accessibilityValue = "100%"
        addSubview(photoView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setImage(asset: String, title: String) {
        photoView.accessibilityLabel = title
        photoView.accessibilityHint = AppLocalization.text("双指缩放或轻点两次放大照片")
        guard assetName != asset else { return }
        assetName = asset
        photoView.image = UIImage(named: asset)
        fittedBounds = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if fittedBounds != bounds.size {
            fittedBounds = bounds.size
            setZoomScale(1, animated: false)
            photoView.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { photoView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        photoView.accessibilityValue = "\(Int(zoomScale * 100))%"
    }

    @objc private func toggleZoom(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > 1.01 {
            setZoomScale(1, animated: true)
        } else {
            let point = recognizer.location(in: photoView)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                           width: size.width, height: size.height), animated: true)
        }
    }
}
