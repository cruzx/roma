import CoreHaptics
import Foundation

/// All engine work stays off the UI and camera-session queues.
final class CameraShutterHaptics: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.roam.camera-shutter-haptics", qos: .userInteractive)
    private var engine: CHHapticEngine?
    private var player: (any CHHapticPatternPlayer)?

    func prepare() {
        queue.async { [self] in
            do {
                guard let engine = try preparedEngine() else { return }
                try engine.start()
                try preparePlayer(using: engine)
            } catch {
                player = nil
            }
        }
    }

    func play(requestedAt: TimeInterval, completion: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            // Never replay an old shutter tap after a slow engine startup.
            guard ProcessInfo.processInfo.systemUptime - requestedAt < 0.12 else {
                completion(false)
                return
            }
            do {
                guard let engine else {
                    completion(false)
                    return
                }
                // Restart after an interruption or the engine's idle shutdown.
                try engine.start()
                try preparePlayer(using: engine)
                guard ProcessInfo.processInfo.systemUptime - requestedAt < 0.12 else {
                    completion(false)
                    return
                }
                try player?.start(atTime: CHHapticTimeImmediate)
                completion(true)
            } catch {
                player = nil
                completion(false)
            }
        }
    }

    private func preparedEngine() throws -> CHHapticEngine? {
        if let engine { return engine }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        let engine = try CHHapticEngine()
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        engine.resetHandler = { [weak self] in
            guard let self else { return }
            self.queue.async { self.player = nil }
        }
        self.engine = engine
        return engine
    }

    private func preparePlayer(using engine: CHHapticEngine) throws {
        guard player == nil else { return }
        let release = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.72),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.45)
        ], relativeTime: 0, duration: 0.12)
        let returnClick = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.85),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.95)
        ], relativeTime: 0.175)
        let pattern = try CHHapticPattern(events: [release, returnClick], parameters: [])
        player = try engine.makePlayer(with: pattern)
    }
}
