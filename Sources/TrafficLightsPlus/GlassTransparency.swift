import Foundation

/// App-scoped compatibility with the native glass appearance preference.
/// AppKit has no public per-app opt-out API. Keep these undocumented keys and
/// its local invalidation notification together; never write the global domain.
/// Ignoring an unknown key on older systems leaves their native material intact.
enum GlassTransparency {
    static let tintAmountKey = "NSGlassTintAmount"
    static let legacyDiffusionKey = "NSGlassDiffusionSetting"
    static let materialDidChange = Notification.Name("NSGlassEffectDiffusionDidChangeNotification")

    /// Call on the main thread, before creating glass at launch and when the
    /// switch changes. Both AppKit and SwiftUI cache the glass environment;
    /// writing defaults alone does not refresh existing material.
    static func apply(
        followsSystem: Bool,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        if followsSystem {
            defaults.removeObject(forKey: tintAmountKey)
            defaults.removeObject(forKey: legacyDiffusionKey)
        } else {
            // macOS 27 uses the continuous amount; macOS 26 uses the earlier
            // clear/tinted selection. Only this application's domain is set.
            defaults.set(0.0, forKey: tintAmountKey)
            defaults.set(false, forKey: legacyDiffusionKey)
        }
        // Deliberately local, not DistributedNotificationCenter: updating our
        // material must not invalidate or change other applications' settings.
        notificationCenter.post(name: materialDidChange, object: nil)
    }
}
