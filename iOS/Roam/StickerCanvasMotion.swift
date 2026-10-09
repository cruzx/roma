import Observation
import UIKit

/// Keeps frame-by-frame browsing local to the canvas; persistence happens after it rests.
@MainActor
@Observable
final class StickerCanvasMotion {
    private(set) var translation: CGFloat = 0
    @ObservationIgnored private(set) var isDragging = false
    @ObservationIgnored private var dragOrigin: CGFloat = 0
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var displayLinkTarget: StickerCanvasDisplayLinkTarget?
    @ObservationIgnored private var deceleration: StickerCanvasDeceleration?
    @ObservationIgnored private var previousTimestamp: CFTimeInterval?
    @ObservationIgnored private var elapsed: TimeInterval = 0
    @ObservationIgnored private var completion: (@MainActor () -> Void)?

    var isMoving: Bool { isDragging || displayLink != nil }

    deinit { displayLink?.invalidate() }

    func drag(to distance: CGFloat) {
        guard distance.isFinite else { return }
        if !isDragging {
            // A new touch catches the moving canvas exactly where it currently appears.
            stop()
            dragOrigin = translation
            isDragging = true
        }
        let next = dragOrigin + distance
        if next.isFinite { translation = next }
    }

    func endDrag(predictedAdditionalTravel: CGFloat, viewportWidth: CGFloat,
                 reduceMotion: Bool, onRest: @escaping @MainActor () -> Void) {
        guard isDragging else { return }
        isDragging = false
        let motion = StickerCanvasDeceleration(start: translation,
                                               predictedAdditionalTravel: predictedAdditionalTravel,
                                               viewportWidth: viewportWidth,
                                               reduceMotion: reduceMotion)
        deceleration = motion
        completion = onRest
        elapsed = 0
        previousTimestamp = nil
        guard motion.duration > 0 else {
            finish()
            return
        }

        let target = StickerCanvasDisplayLinkTarget(motion: self)
        let link = CADisplayLink(target: target, selector: #selector(StickerCanvasDisplayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        displayLinkTarget = target
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    /// Interrupting motion never commits it or moves the canvas back to its old origin.
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkTarget = nil
        deceleration = nil
        previousTimestamp = nil
        elapsed = 0
        completion = nil
        isDragging = false
    }

    func reset() {
        stop()
        dragOrigin = 0
        translation = 0
    }

    // Timestamp input also makes interruption and settling deterministic to verify.
    func advance(at timestamp: CFTimeInterval) {
        guard displayLink != nil, let deceleration else { return }
        guard timestamp.isFinite else {
            finish()
            return
        }
        if let previousTimestamp {
            elapsed += max(0, timestamp - previousTimestamp)
        }
        previousTimestamp = timestamp
        translation = deceleration.translation(at: elapsed)
        if elapsed >= deceleration.duration { finish() }
    }

    private func finish() {
        if let deceleration { translation = deceleration.end }
        let onRest = completion
        // Clear first: the completion may synchronously reset or begin another gesture.
        stop()
        onRest?()
    }
}

/// A display link retains its target; the proxy keeps that ownership away from the controller.
@MainActor
private final class StickerCanvasDisplayLinkTarget: NSObject {
    private weak var motion: StickerCanvasMotion?

    init(motion: StickerCanvasMotion) { self.motion = motion }

    @objc func tick(_ link: CADisplayLink) { motion?.advance(at: link.timestamp) }
}

/// Pure timing and distance rules, independent of display refresh rate or persisted coordinates.
struct StickerCanvasDeceleration {
    let start: CGFloat
    let distance: CGFloat
    let duration: TimeInterval

    var end: CGFloat { start + distance }

    init(start: CGFloat, predictedAdditionalTravel: CGFloat, viewportWidth: CGFloat,
         reduceMotion: Bool = false) {
        self.start = start.isFinite ? start : 0
        let limit = viewportWidth.isFinite && viewportWidth > 0 ? viewportWidth * 0.55 : 0
        let bounded = predictedAdditionalTravel.isFinite
            ? min(limit, max(-limit, predictedAdditionalTravel)) : 0
        let canCoast = !reduceMotion && abs(bounded) >= 2 && (self.start + bounded).isFinite
        distance = canCoast ? bounded : 0
        duration = canCoast ? 0.25 + 0.20 * Double(abs(bounded) / limit) : 0
    }

    func translation(at elapsed: TimeInterval) -> CGFloat {
        guard duration > 0 else { return end }
        if elapsed == .infinity { return end }
        guard elapsed.isFinite else { return start }
        let progress = CGFloat(min(1, max(0, elapsed / duration)))
        let remaining = 1 - progress
        let eased = 1 - remaining * remaining * remaining
        return start + distance * eased
    }
}
