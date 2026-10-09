import SwiftUI

/// Interpolate the reveal itself, keeping the camera preview's layout unchanged.
struct StickerCameraMorph: ViewModifier, Animatable {
    var progress: CGFloat
    let expandedSize: CGSize
    let collapsedSize: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let amount = min(1, max(0, progress))
        let outline = StickerCameraMorphShape(progress: amount,
                                              expandedSize: expandedSize,
                                              collapsedSize: collapsedSize)
        let fade = min(1, amount / 0.06)
        let opacity = fade * fade * (3 - 2 * fade)

        ZStack(alignment: .top) {
            // Only the opaque backing casts a shadow; the live camera layer does not.
            outline
                .fill(.black)
                .shadow(color: .black.opacity(0.20 * amount), radius: 20, x: 0, y: 10 * amount)

            content
                .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
                .clipShape(outline)
        }
        .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
        .contentShape(outline)
        .opacity(opacity)
    }
}

/// Geometry comes from the modifier's animated progress, with no second animation.
struct StickerCameraMorphShape: Shape {
    let progress: CGFloat
    let expandedSize: CGSize
    let collapsedSize: CGSize

    func path(in rect: CGRect) -> Path {
        let amount = min(1, max(0, progress))
        let width = collapsedSize.width + (expandedSize.width - collapsedSize.width) * amount
        let height = collapsedSize.height + (expandedSize.height - collapsedSize.height) * amount
        let collapsedRadius = collapsedSize.height / 2
        let radius = collapsedRadius + (34 - collapsedRadius) * amount
        let bounds = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: height)
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: bounds)
    }
}
