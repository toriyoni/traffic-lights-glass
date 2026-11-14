import Foundation
import Testing
@testable import TrafficLightsPlus

private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suiteName = "TrafficLightsPlusTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(defaults)
}

@Test func preferenceDefaultsAreUsable() {
    withDefaults { defaults in
        let preferences = Preferences(defaults: defaults, preferredLanguages: ["zh-Hans-CN"])
        #expect(preferences.language == .simplifiedChinese)
        #expect(preferences.menuBarIconVisible)
        #expect(preferences.enabled)
        #expect(preferences.size == 28)
        #expect(preferences.spacing == 0)
        #expect(preferences.style == .liquidGlass)
        #expect(preferences.followSystemGlassTransparency)
        #expect(preferences.hiddenTrafficLightsEnabled)
        #expect(preferences.hiddenTrafficLightRevealMode == .group)
        #expect(!preferences.showInFullScreen)
        #expect(preferences.dockClickMinimizesActiveWindow)
        #expect(preferences.stageManagerCloseButtonsEnabled)
        #expect(preferences.quitOnCloseEnabled)
        #expect(preferences.closeBehavior == .closeWindow)
        #expect(preferences.minimizeBehavior == .minimizeWindow)
        #expect(preferences.zoomBehavior == .zoomWindow)
        #expect(preferences.quitOnCloseApplications.isEmpty)
    }
}

@Test func systemGlassTransparencyChoicePersistsAcrossLaunches() {
    withDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        preferences.followSystemGlassTransparency = false
        #expect(!Preferences(defaults: defaults).followSystemGlassTransparency)
        preferences.followSystemGlassTransparency = true
        #expect(Preferences(defaults: defaults).followSystemGlassTransparency)
    }
}

@Test func fixedGlassOverridesOnlyItsApplicationAndFollowingReleasesTheOverride() {
    withDefaults { defaults in
        let center = NotificationCenter()
        // Simulate an inherited system value, including a future change. An
        // opt-in must remove the override, not copy and freeze today's value.
        let inheritedName = "TrafficLightsPlusTests.Inherited.\(UUID().uuidString)"
        let inherited = UserDefaults(suiteName: inheritedName)!
        inherited.set(0.75, forKey: GlassTransparency.tintAmountKey)
        inherited.set(true, forKey: GlassTransparency.legacyDiffusionKey)
        defaults.addSuite(named: inheritedName)
        defer {
            defaults.removeSuite(named: inheritedName)
            inherited.removePersistentDomain(forName: inheritedName)
        }
        defaults.set("keep", forKey: "unrelatedPreference")
        let globalBefore = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        GlassTransparency.apply(followsSystem: false, defaults: defaults, notificationCenter: center)
        #expect(defaults.double(forKey: GlassTransparency.tintAmountKey) == 0)
        #expect(!defaults.bool(forKey: GlassTransparency.legacyDiffusionKey))
        GlassTransparency.apply(followsSystem: true, defaults: defaults, notificationCenter: center)
        #expect(defaults.double(forKey: GlassTransparency.tintAmountKey) == 0.75)
        #expect(defaults.bool(forKey: GlassTransparency.legacyDiffusionKey))
        inherited.set(0.35, forKey: GlassTransparency.tintAmountKey)
        #expect(defaults.double(forKey: GlassTransparency.tintAmountKey) == 0.35)
        #expect(defaults.string(forKey: "unrelatedPreference") == "keep")
        let globalAfter = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        for key in [GlassTransparency.tintAmountKey, GlassTransparency.legacyDiffusionKey] {
            #expect((globalBefore?[key] as? NSNumber) == (globalAfter?[key] as? NSNumber))
        }
    }
}

@Test func glassRefreshIsLocalAndArrivesAfterTheNewPreference() {
    withDefaults { defaults in
        let center = NotificationCenter()
        let token = center.addObserver(forName: GlassTransparency.materialDidChange, object: nil, queue: nil) { _ in
            #expect(defaults.double(forKey: GlassTransparency.tintAmountKey) == 0)
            defaults.set(true, forKey: "testObservedRefresh")
        }
        defer { center.removeObserver(token) }
        GlassTransparency.apply(followsSystem: false, defaults: defaults, notificationCenter: center)
        #expect(defaults.bool(forKey: "testObservedRefresh"))
    }
}

@Test func recommendedHiddenTrafficLightCopyIsStable() {
    #expect(AppLocalization.string(.overlayEnabled, language: .simplifiedChinese) == "放大红绿灯")
    #expect(AppLocalization.string(.overlayEnabled, language: .english) == "Enlarged Traffic Lights")
    #expect(AppLocalization.string(.hiddenTrafficLights, language: .simplifiedChinese) == "隐藏式红绿灯（推荐）")
    #expect(AppLocalization.string(.hiddenTrafficLights, language: .english) == "Hidden Traffic Lights (Recommended)")
    #expect(AppLocalization.string(.dockClickMinimize, language: .simplifiedChinese) == "Dock 栏最小化")
        #expect(AppLocalization.string(.dockClickMinimize, language: .english) == "Dock Click to Minimize")
        #expect(AppLocalization.string(.stageManagerCloseButtons, language: .simplifiedChinese) == "台前调度关闭按钮")
        #expect(AppLocalization.string(.stageManagerCloseButtons, language: .english) == "Stage Manager Close Buttons")
        #expect(AppLocalization.string(.quitOnCloseEnabled, language: .simplifiedChinese) == "关闭时退出应用")
    #expect(AppLocalization.string(.quitOnCloseEnabled, language: .english) == "Quit Apps on Close")
    #expect(AppLocalization.string(.menuBarIconVisible, language: .simplifiedChinese) == "显示菜单栏图标")
    #expect(AppLocalization.string(.menuBarIconVisible, language: .english) == "Show Menu Bar Icon")
    #expect(HiddenTrafficLightRevealMode.group.title(language: .english) == "Group")
    #expect(HiddenTrafficLightRevealMode.nearest.title(language: .english) == "Single")
}

@Test func systemLanguageSelectionMapsChineseToSimplifiedChineseAndOthersToEnglish() {
    #expect(AppLanguage.systemDefault(preferredLanguages: ["zh-Hans-CN"]) == .simplifiedChinese)
    #expect(AppLanguage.systemDefault(preferredLanguages: ["zh-Hant-TW"]) == .simplifiedChinese)
    #expect(AppLanguage.systemDefault(preferredLanguages: ["en-US"]) == .english)
    #expect(AppLanguage.systemDefault(preferredLanguages: ["fr-FR"]) == .english)
    #expect(AppLanguage.systemDefault(preferredLanguages: []) == .english)
}

@Test func languagePreferencePersistsAndCorruptValuesFollowTheSystem() {
    withDefaults { defaults in
        let preferences = Preferences(defaults: defaults, preferredLanguages: ["en-US"])
        #expect(preferences.language == .english)

        preferences.language = .simplifiedChinese
        #expect(Preferences(defaults: defaults, preferredLanguages: ["en-US"]).language == .simplifiedChinese)

        defaults.set("unknown", forKey: "appLanguage")
        let recovered = Preferences(defaults: defaults, preferredLanguages: ["en-US"])
        #expect(recovered.language == .english)
        #expect(defaults.string(forKey: "appLanguage") == AppLanguage.english.rawValue)
    }
}

@Test func bothLocalizationTablesContainEveryApplicationString() {
    #expect(AppLocalization.missingKeys(for: .simplifiedChinese).isEmpty)
    #expect(AppLocalization.missingKeys(for: .english).isEmpty)
}

@Test func dockClickFeatureCanStayEnabledWhileOverlaysAreDisabled() {
    withDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        preferences.enabled = false

        #expect(!preferences.enabled)
        #expect(preferences.dockClickMinimizesActiveWindow)
    }
}

@Test func quitOnCloseFeatureCanStayEnabledWhileOverlaysAreDisabled() {
    withDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        preferences.enabled = false
        preferences.addQuitOnCloseApplication(
            bundleIdentifier: "com.example.editor",
            displayName: "Editor"
        )

        #expect(!preferences.enabled)
        #expect(preferences.quitOnCloseEnabled)
        #expect(preferences.shouldQuitOnClose(bundleIdentifier: "com.example.editor"))
        #expect(WindowTracker.shouldTrackWindows(
            overlaysEnabled: preferences.enabled,
            quitOnCloseEnabled: preferences.quitOnCloseEnabled,
            hasQuitOnCloseApplications: !preferences.quitOnCloseApplications.isEmpty
        ))
    }
}

@Test func disablingQuitOnCloseKeepsTheListWithoutApplyingIt() {
    withDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        preferences.addQuitOnCloseApplication(
            bundleIdentifier: "com.example.editor",
            displayName: "Editor"
        )
        preferences.quitOnCloseEnabled = false

        #expect(!preferences.shouldQuitOnClose(bundleIdentifier: "com.example.editor"))
        #expect(preferences.quitOnCloseApplications.count == 1)
        #expect(!WindowTracker.shouldTrackWindows(
            overlaysEnabled: false,
            quitOnCloseEnabled: preferences.quitOnCloseEnabled,
            hasQuitOnCloseApplications: true
        ))
    }
}

@Test func fullScreenPreferenceIsDisabledWhileTheFeatureIsInDevelopment() {
    withDefaults { defaults in
        defaults.set(true, forKey: "showInFullScreen")

        let preferences = Preferences(defaults: defaults)

        #expect(!preferences.showInFullScreen)
        #expect(!defaults.bool(forKey: "showInFullScreen"))
    }
}

@Test func preferencesPersist() {
    withDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        preferences.language = .english
        preferences.menuBarIconVisible = false
        preferences.enabled = false
        preferences.size = 42
        preferences.spacing = 12
        preferences.style = .edgeSquares
        preferences.hiddenTrafficLightsEnabled = false
        preferences.hiddenTrafficLightRevealMode = .group
        preferences.dockClickMinimizesActiveWindow = false
        preferences.stageManagerCloseButtonsEnabled = false
        preferences.quitOnCloseEnabled = false
        preferences.closeBehavior = .quitApplication
        preferences.minimizeBehavior = .hideApplication
        preferences.zoomBehavior = .doNothing
        preferences.addQuitOnCloseApplication(
            bundleIdentifier: "com.example.editor",
            displayName: "Editor"
        )

        let restored = Preferences(defaults: defaults)
        #expect(restored.language == .english)
        #expect(!restored.menuBarIconVisible)
        #expect(!restored.enabled)
        #expect(restored.size == 42)
        #expect(restored.spacing == 12)
        #expect(restored.style == .edgeSquares)
        #expect(!restored.hiddenTrafficLightsEnabled)
        #expect(restored.hiddenTrafficLightRevealMode == .group)
        #expect(!restored.showInFullScreen)
        #expect(!restored.dockClickMinimizesActiveWindow)
        #expect(!restored.stageManagerCloseButtonsEnabled)
        #expect(!restored.quitOnCloseEnabled)
        #expect(restored.closeBehavior == .quitApplication)
        #expect(restored.minimizeBehavior == .hideApplication)
        #expect(restored.zoomBehavior == .doNothing)
        #expect(restored.quitOnCloseApplications == [
            QuitOnCloseApplication(bundleIdentifier: "com.example.editor", displayName: "Editor")
        ])
    }
}

@Test func hiddenMenuBarIconReopensSettingsOnTheNextLaunch() {
    #expect(!AppDelegate.shouldOpenSettingsAtLaunch(menuBarIconVisible: true))
    #expect(AppDelegate.shouldOpenSettingsAtLaunch(menuBarIconVisible: false))
}

@Test func quitOnCloseApplicationsCanBeAddedDeduplicatedAndRemoved() {
    withDefaults { defaults in
        let preferences = Preferences(defaults: defaults)

        #expect(preferences.addQuitOnCloseApplication(
            bundleIdentifier: "com.example.editor",
            displayName: "Editor"
        ))
        #expect(!preferences.addQuitOnCloseApplication(
            bundleIdentifier: "COM.EXAMPLE.EDITOR",
            displayName: "Duplicate"
        ))
        #expect(preferences.quitOnCloseApplications.count == 1)
        #expect(preferences.shouldQuitOnClose(bundleIdentifier: "COM.EXAMPLE.EDITOR"))

        preferences.removeQuitOnCloseApplication(bundleIdentifier: "com.example.editor")
        #expect(preferences.quitOnCloseApplications.isEmpty)
        #expect(!preferences.shouldQuitOnClose(bundleIdentifier: "com.example.editor"))
    }
}

@Test func corruptStoredQuitOnCloseApplicationsFallBackToEmpty() {
    withDefaults { defaults in
        defaults.set(Data("not-json".utf8), forKey: "quitOnCloseApplications")
        #expect(Preferences(defaults: defaults).quitOnCloseApplications.isEmpty)
    }
}

@Test func quitOnCloseOnlyOverridesConfiguredCloseBehaviors() {
    withDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        preferences.addQuitOnCloseApplication(
            bundleIdentifier: "com.example.editor",
            displayName: "Editor"
        )

        #expect(preferences.effectiveBehavior(
            for: .close,
            bundleIdentifier: "com.example.editor"
        ) == .quitApplication)
        #expect(preferences.effectiveBehavior(
            for: .close,
            bundleIdentifier: "com.example.other"
        ) == .closeWindow)

        preferences.minimizeBehavior = .closeWindow
        #expect(preferences.effectiveBehavior(
            for: .minimize,
            bundleIdentifier: "com.example.editor"
        ) == .quitApplication)

        preferences.zoomBehavior = .zoomWindow
        #expect(preferences.effectiveBehavior(
            for: .zoom,
            bundleIdentifier: "com.example.editor"
        ) == .zoomWindow)
    }
}

@Test func quitOnCloseApplicationsSurviveBehaviorVisibilityAndResetChanges() {
    withDefaults { defaults in
        let preferences = Preferences(defaults: defaults)
        preferences.addQuitOnCloseApplication(
            bundleIdentifier: "com.example.editor",
            displayName: "Editor"
        )

        preferences.closeBehavior = .doNothing
        preferences.minimizeBehavior = .minimizeWindow
        preferences.zoomBehavior = .zoomWindow
        #expect(!preferences.hasCloseWindowBehavior)
        #expect(preferences.quitOnCloseApplications.count == 1)

        preferences.resetButtonBehaviors()
        #expect(preferences.hasCloseWindowBehavior)
        #expect(preferences.quitOnCloseApplications.count == 1)
    }
}

@Test func corruptStoredRevealModeFallsBackToGroup() {
    withDefaults { defaults in
        defaults.set("unknown", forKey: "hiddenTrafficLightRevealMode")
        #expect(Preferences(defaults: defaults).hiddenTrafficLightRevealMode == .group)
    }
}

@Test func corruptStoredBehaviorsFallBackToNativeDefaults() {
    withDefaults { defaults in
        defaults.set("unknown", forKey: "closeButtonBehavior")
        defaults.set("unknown", forKey: "minimizeButtonBehavior")
        defaults.set("unknown", forKey: "zoomButtonBehavior")

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.closeBehavior == .closeWindow)
        #expect(preferences.minimizeBehavior == .minimizeWindow)
        #expect(preferences.zoomBehavior == .zoomWindow)
    }
}

@Test func buttonBehaviorNativeActionMappingIsStable() {
    #expect(ButtonBehavior.closeWindow.nativeWindowAction == .close)
    #expect(ButtonBehavior.minimizeWindow.nativeWindowAction == .minimize)
    #expect(ButtonBehavior.zoomWindow.nativeWindowAction == .zoom)
    #expect(ButtonBehavior.quitApplication.nativeWindowAction == nil)
}

@Test func corruptStoredSizeIsClamped() {
    withDefaults { defaults in
        defaults.set(500, forKey: "controlSize")
        #expect(Preferences(defaults: defaults).size == 48)

        defaults.set(-20, forKey: "controlSize")
        #expect(Preferences(defaults: defaults).size == 18)

        defaults.set(Double.nan, forKey: "controlSize")
        #expect(Preferences(defaults: defaults).size == ControlLayout.defaultSize)

        defaults.set(Double.infinity, forKey: "controlSize")
        #expect(Preferences(defaults: defaults).size == ControlLayout.defaultSize)
    }
}

@Test func corruptStoredSpacingIsClamped() {
    withDefaults { defaults in
        defaults.set(500, forKey: "controlSpacingAdjustment")
        #expect(Preferences(defaults: defaults).spacing == 32)

        defaults.set(-500, forKey: "controlSpacingAdjustment")
        #expect(Preferences(defaults: defaults).spacing == -8)

        defaults.set(Double.nan, forKey: "controlSpacingAdjustment")
        #expect(Preferences(defaults: defaults).spacing == ControlLayout.defaultSpacingAdjustment)

        defaults.set(-Double.infinity, forKey: "controlSpacingAdjustment")
        #expect(Preferences(defaults: defaults).spacing == ControlLayout.defaultSpacingAdjustment)
    }
}

@Test func glassStylePreservesStoredClassicPreferences() {
    withDefaults { defaults in
        defaults.set(ControlStyle.macOS.rawValue, forKey: "controlStyle")
        defaults.set(HiddenTrafficLightRevealMode.nearest.rawValue, forKey: "hiddenTrafficLightRevealMode")
        defaults.set(36.0, forKey: "controlSize")
        defaults.set(false, forKey: "dockClickMinimizesActiveWindow")

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.style == .macOS)
        #expect(preferences.hiddenTrafficLightRevealMode == .nearest)
        #expect(preferences.effectiveHiddenTrafficLightRevealMode == .nearest)
        #expect(preferences.size == 36)
        #expect(!preferences.dockClickMinimizesActiveWindow)

        preferences.style = .liquidGlass
        #expect(preferences.effectiveHiddenTrafficLightRevealMode == .group)
        #expect(preferences.hiddenTrafficLightRevealMode == .nearest)
        #expect(defaults.string(forKey: "hiddenTrafficLightRevealMode") == "nearest")

        let restored = Preferences(defaults: defaults)
        #expect(restored.style == .liquidGlass)
        #expect(restored.effectiveHiddenTrafficLightRevealMode == .group)
        restored.style = .macOS
        #expect(restored.effectiveHiddenTrafficLightRevealMode == .nearest)
    }
}
