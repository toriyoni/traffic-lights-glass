import Combine
import Foundation
import Testing
@testable import TrafficLightsPlus

private func withApplicationDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suite = "TrafficLightsPlusApplicationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
}

@Test func applicationOverridesTakePriorityInBothDirections() {
    withApplicationDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        preferences.addApplication(bundleIdentifier: "com.netease.uuremote", displayName: "UU 远程")
        let cases: [(Bool, ApplicationOverlayMode, Bool)] = [
            (true, .followGlobal, true), (false, .followGlobal, false),
            (true, .enabled, true), (false, .enabled, true),
            (true, .disabled, false), (false, .disabled, false)
        ]
        for (globalEnabled, mode, expected) in cases {
            preferences.enabled = globalEnabled
            preferences.setOverlayMode(mode, bundleIdentifier: "com.netease.uuremote")
            #expect(preferences.overlaysEnabled(bundleIdentifier: "COM.NETEASE.UUREMOTE") == expected)
            #expect(preferences.shouldTrackApplication(bundleIdentifier: "com.netease.uuremote") == expected)
            #expect(preferences.overlaysEnabled(bundleIdentifier: "com.apple.finder") == globalEnabled)
            #expect(preferences.overlaysEnabled(bundleIdentifier: nil) == globalEnabled)
            #expect(!preferences.shouldQuitOnClose(bundleIdentifier: "com.netease.uuremote"))
        }
    }
}

@Test func explicitApplicationEnableKeepsTrackingAliveWithGlobalOff() {
    withApplicationDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        preferences.enabled = false
        preferences.quitOnCloseEnabled = false
        preferences.addApplication(bundleIdentifier: "com.example.editor", displayName: "Editor")
        #expect(!preferences.hasEnabledOverlays)

        preferences.setOverlayMode(.enabled, bundleIdentifier: "com.example.editor")
        #expect(preferences.hasEnabledOverlays)
        #expect(WindowTracker.shouldTrackWindows(
            overlaysEnabled: preferences.hasEnabledOverlays,
            quitOnCloseEnabled: preferences.quitOnCloseEnabled,
            hasQuitOnCloseApplications: !preferences.quitOnCloseApplications.isEmpty
        ))
        #expect(preferences.shouldTrackApplication(bundleIdentifier: "com.example.editor"))
        #expect(!preferences.shouldTrackApplication(bundleIdentifier: "com.example.other"))

        preferences.setOverlayMode(.followGlobal, bundleIdentifier: "com.example.editor")
        #expect(!preferences.hasEnabledOverlays)
    }
}

@Test func applicationRulesPersistWithoutChangingOtherAppsOrQuitMembership() {
    withApplicationDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.addApplication(bundleIdentifier: "com.example.remote", displayName: "Remote"))
        #expect(preferences.addApplication(bundleIdentifier: "com.example.editor", displayName: "Editor"))
        preferences.setOverlayMode(.disabled, bundleIdentifier: "com.example.remote")
        preferences.setOverlayMode(.enabled, bundleIdentifier: "com.example.editor")
        preferences.enabled = false
        #expect(!preferences.addApplication(bundleIdentifier: "COM.EXAMPLE.REMOTE", displayName: "Duplicate"))
        #expect(!preferences.addApplication(bundleIdentifier: "  ", displayName: "Invalid"))

        let restored = Preferences(defaults: defaults)
        #expect(restored.applicationRules.count == 2)
        #expect(!restored.overlaysEnabled(bundleIdentifier: "com.example.remote"))
        #expect(restored.overlaysEnabled(bundleIdentifier: "com.example.editor"))
        #expect(restored.quitOnCloseApplications.isEmpty)
        restored.enabled = true
        #expect(!restored.overlaysEnabled(bundleIdentifier: "com.example.remote"))
        #expect(restored.overlaysEnabled(bundleIdentifier: "com.example.other"))
    }
}

@Test func followingGlobalAndRemovingRulesRestoreTheCurrentDefault() {
    withApplicationDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        preferences.addApplication(bundleIdentifier: "com.example.remote", displayName: "Remote")
        preferences.setOverlayMode(.disabled, bundleIdentifier: "com.example.remote")
        preferences.setOverlayMode(.followGlobal, bundleIdentifier: "com.example.remote")
        #expect(preferences.overlaysEnabled(bundleIdentifier: "com.example.remote"))
        preferences.enabled = false
        #expect(!preferences.overlaysEnabled(bundleIdentifier: "com.example.remote"))

        preferences.setOverlayMode(.enabled, bundleIdentifier: "com.example.remote")
        preferences.removeApplication(bundleIdentifier: "COM.EXAMPLE.REMOTE")
        #expect(!preferences.overlaysEnabled(bundleIdentifier: "com.example.remote"))
        #expect(!preferences.hasEnabledOverlays)
        #expect(Preferences(defaults: defaults).applicationRules.isEmpty)
    }
}

@Test func legacyQuitListMigratesWithoutChangingEnlargementOrQuittingOtherApps() throws {
    try withApplicationDefaults { defaults in
        let legacy = [
            QuitOnCloseApplication(bundleIdentifier: "com.example.editor", displayName: "Editor"),
            QuitOnCloseApplication(bundleIdentifier: "COM.EXAMPLE.EDITOR", displayName: "Duplicate"),
            QuitOnCloseApplication(bundleIdentifier: "", displayName: "Invalid")
        ]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "quitOnCloseApplications")
        defaults.set(false, forKey: "enabled")
        defaults.set(false, forKey: "quitOnCloseEnabled")

        let migrated = Preferences(defaults: defaults)
        #expect(migrated.applicationRules.count == 1)
        #expect(migrated.overlayMode(bundleIdentifier: "com.example.editor") == .followGlobal)
        #expect(!migrated.overlaysEnabled(bundleIdentifier: "com.example.editor"))
        #expect(!migrated.shouldQuitOnClose(bundleIdentifier: "com.example.editor"))
        migrated.quitOnCloseEnabled = true
        #expect(migrated.shouldQuitOnClose(bundleIdentifier: "com.example.editor"))
        #expect(!migrated.shouldQuitOnClose(bundleIdentifier: "com.example.other"))

        migrated.removeApplication(bundleIdentifier: "com.example.editor")
        #expect(Preferences(defaults: defaults).applicationRules.isEmpty)
    }
}

@Test func enlargementExceptionIsIndependentOfQuitOnCloseAndCanRetainCloseObservation() {
    withApplicationDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        preferences.addApplication(bundleIdentifier: "com.example.editor", displayName: "Editor")
        preferences.setOverlayMode(.disabled, bundleIdentifier: "com.example.editor")
        preferences.quitOnCloseEnabled = false
        #expect(!preferences.shouldTrackApplication(bundleIdentifier: "com.example.editor"))
        preferences.setQuitOnClose(true, bundleIdentifier: "com.example.editor")
        #expect(!preferences.shouldQuitOnClose(bundleIdentifier: "com.example.editor"))

        preferences.quitOnCloseEnabled = true
        #expect(preferences.shouldTrackApplication(bundleIdentifier: "com.example.editor"))
        #expect(!preferences.overlaysEnabled(bundleIdentifier: "com.example.editor"))
        #expect(preferences.shouldQuitOnClose(bundleIdentifier: "com.example.editor"))
        preferences.removeQuitOnCloseApplication(bundleIdentifier: "com.example.editor")
        #expect(preferences.overlayMode(bundleIdentifier: "com.example.editor") == .disabled)
    }
}

@Test func ruleEditsNotifyTheUIAndWindowTracker() {
    withApplicationDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        preferences.addApplication(bundleIdentifier: "com.example.remote", displayName: "Remote")
        var changeCount = 0
        let subscription = preferences.objectWillChange.sink { changeCount += 1 }
        preferences.setOverlayMode(.disabled, bundleIdentifier: "com.example.remote")
        preferences.setQuitOnClose(true, bundleIdentifier: "com.example.remote")
        preferences.removeApplication(bundleIdentifier: "com.example.remote")
        #expect(changeCount == 3)
        withExtendedLifetime(subscription) {}
    }
}

@Test func malformedRulesDoNotReactivateTheLegacyQuitList() throws {
    try withApplicationDefaults { defaults in
        defaults.set(try JSONEncoder().encode([
            QuitOnCloseApplication(bundleIdentifier: "com.example.editor", displayName: "Editor")
        ]), forKey: "quitOnCloseApplications")
        defaults.set(Data("not-json".utf8), forKey: "applicationRules")
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.applicationRules.isEmpty)
        #expect(!preferences.shouldQuitOnClose(bundleIdentifier: "com.example.editor"))
    }
}
