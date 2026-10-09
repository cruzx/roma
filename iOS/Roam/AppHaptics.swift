import UIKit

/// Feedback belongs to explicit UI actions, never background saves or every drag update.
@MainActor
enum AppHaptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let firm = UIImpactFeedbackGenerator(style: .rigid)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()
    private static let shutter = CameraShutterHaptics()
    private static var lastFeedbackTime = -Double.infinity
    private static var feedbackReservedUntil = -Double.infinity

    static func prepareCameraShutter() {
        guard UIApplication.shared.applicationState == .active else { return }
        shutter.prepare()
        firm.prepare()
        light.prepare()
    }

    static func cameraShutter() {
        play {
            let requestedAt = ProcessInfo.processInfo.systemUptime
            // Keep the return click distinct from selection/dismissal feedback.
            feedbackReservedUntil = requestedAt + 0.25
            shutter.play(requestedAt: requestedAt) { played in
                DispatchQueue.main.async {
                    if played {
                        // Count from playback, including an engine restart's small delay.
                        feedbackReservedUntil = max(feedbackReservedUntil, ProcessInfo.processInfo.systemUptime + 0.25)
                        return
                    }
                    guard UIApplication.shared.applicationState == .active,
                          ProcessInfo.processInfo.systemUptime - requestedAt < 0.12 else { return }
                    // Older hardware and temporary engine failures retain a two-part click.
                    feedbackReservedUntil = ProcessInfo.processInfo.systemUptime + 0.25
                    firm.impactOccurred(intensity: 0.85)
                    light.prepare()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.175) {
                        guard UIApplication.shared.applicationState == .active,
                              ProcessInfo.processInfo.systemUptime - requestedAt < 0.35 else { return }
                        light.impactOccurred(intensity: 0.65)
                    }
                }
            }
        }
    }

    static func tap() {
        play {
            light.impactOccurred(intensity: 0.55)
            light.prepare()
        }
    }

    static func selection() {
        play {
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
        }
    }

    static func impact() {
        play {
            firm.impactOccurred(intensity: 0.65)
            firm.prepare()
        }
    }

    static func success() { notify(.success) }
    static func warning() { notify(.warning) }
    static func error() { notify(.error) }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        play {
            notification.notificationOccurred(type)
            notification.prepare()
        }
    }

    private static func play(_ feedback: () -> Void) {
        guard UIApplication.shared.applicationState == .active else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // A single tap can also select, dismiss or end a gesture. Do not stack pulses.
        guard now >= feedbackReservedUntil, now - lastFeedbackTime >= 0.075 else { return }
        lastFeedbackTime = now
        feedback()
    }
}
