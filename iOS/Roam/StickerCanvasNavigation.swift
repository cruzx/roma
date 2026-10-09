import CoreGraphics
import Foundation

/// Locks each browse gesture to one purpose without changing persisted canvas coordinates.
struct StickerCanvasNavigation {
    enum Intent: Equatable {
        case undecided, horizontal, camera, ignored
    }

    private(set) var intent: Intent = .undecided
    private(set) var horizontalTranslation: CGFloat = 0

    @discardableResult
    mutating func update(translation: CGSize) -> Intent {
        if intent == .undecided, hypot(translation.width, translation.height) >= 10 {
            let horizontal = abs(translation.width)
            let vertical = abs(translation.height)
            if horizontal > vertical * 1.25 {
                intent = .horizontal
            } else if vertical > horizontal * 1.25 {
                intent = translation.height > 0 ? .camera : .ignored
            }
        }
        horizontalTranslation = intent == .horizontal ? translation.width : 0
        return intent
    }

    mutating func reset() {
        intent = .undecided
        horizontalTranslation = 0
    }
}
