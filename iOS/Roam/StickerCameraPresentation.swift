import CoreGraphics
import Foundation

/// Gesture intent and presentation lifetime, independent of SwiftUI's animation clock.
struct StickerCameraPresentation {
    enum Phase: Equatable {
        case hidden, pulling, opening, open, dragging, closing
    }

    private enum Direction {
        case undecided, accepted, rejected
    }

    private(set) var phase: Phase = .hidden
    private(set) var progress: CGFloat = 0
    private(set) var presentationID = UUID()
    private var completionToken = UUID()
    private var committed = false
    private var sessionActivated = false
    private var openingDirection: Direction = .undecided
    private var closingDirection: Direction = .undecided

    var isMounted: Bool { phase != .hidden }
    var showsCamera: Bool { committed }
    var isActive: Bool { sessionActivated }
    var isInteractive: Bool { phase == .open || phase == .dragging }
    var isDragging: Bool { phase == .pulling || phase == .dragging }
    var hidesStatusBar: Bool { committed }

    /// Returns whether this update belongs to an accepted opening drag.
    mutating func updateOpening(translation: CGSize, travel: CGFloat) -> Bool {
        guard phase == .hidden || phase == .pulling else { return false }
        if openingDirection == .undecided {
            openingDirection = Self.direction(for: translation, opening: true)
        }
        guard openingDirection == .accepted else { return false }
        if phase == .hidden {
            presentationID = UUID()
            phase = .pulling
        }
        progress = min(0.95, max(0, translation.height / max(1, travel)))
        return true
    }

    /// Returns whether this update belongs to an accepted closing drag.
    mutating func updateClosing(translation: CGSize, travel: CGFloat) -> Bool {
        guard phase == .open || phase == .dragging else { return false }
        if closingDirection == .undecided {
            closingDirection = Self.direction(for: translation, opening: false)
        }
        guard closingDirection == .accepted else { return false }
        phase = .dragging
        progress = min(1, max(0, 1 + translation.height / max(1, travel)))
        return true
    }

    /// An endpoint is returned only when a recognized drag needs to settle.
    mutating func finishOpening(translation: CGSize, predicted: CGSize) -> Bool? {
        defer { openingDirection = .undecided }
        guard phase == .pulling, openingDirection == .accepted else { return nil }
        return Self.passesThreshold(actual: translation.height, projected: predicted.height)
    }

    mutating func finishClosing(translation: CGSize, predicted: CGSize) -> Bool? {
        defer { closingDirection = .undecided }
        guard phase == .dragging, closingDirection == .accepted else { return nil }
        return !Self.passesThreshold(actual: -translation.height, projected: -predicted.height)
    }

    mutating func cancelDrag() -> Bool? {
        resetDirection()
        switch phase {
        case .pulling: return false
        case .dragging: return true
        default: return nil
        }
    }

    /// The caller animates this endpoint change and completes it with the returned token.
    @discardableResult
    mutating func settle(open: Bool) -> UUID {
        completionToken = UUID()
        resetDirection()
        if open {
            if phase == .hidden { presentationID = UUID() }
            committed = true
            phase = .opening
            progress = 1
        } else {
            sessionActivated = false
            phase = .closing
            progress = 0
        }
        return completionToken
    }

    @discardableResult
    mutating func complete(token: UUID) -> Bool {
        guard token == completionToken else { return false }
        switch phase {
        case .opening:
            phase = .open
            progress = 1
            sessionActivated = true
        case .closing:
            phase = .hidden
            progress = 0
            committed = false
            sessionActivated = false
        default:
            return false
        }
        resetDirection()
        return true
    }

    mutating func reset() {
        completionToken = UUID()
        phase = .hidden
        progress = 0
        committed = false
        sessionActivated = false
        resetDirection()
    }

    private mutating func resetDirection() {
        openingDirection = .undecided
        closingDirection = .undecided
    }

    private static func direction(for translation: CGSize, opening: Bool) -> Direction {
        guard hypot(translation.width, translation.height) >= 10 else { return .undecided }
        let vertical = opening ? translation.height : -translation.height
        return vertical > abs(translation.width) * 1.25 ? .accepted : .rejected
    }

    private static func passesThreshold(actual: CGFloat, projected: CGFloat) -> Bool {
        actual >= 76 || (actual >= 26 && projected >= 150)
    }
}
